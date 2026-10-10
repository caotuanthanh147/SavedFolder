import { describe, expect, test } from "bun:test";
import { existsSync } from "node:fs";
import { generateStub } from "../src/generator";
import { packageInit } from "../src/initpack";
import { $ } from "bun";

const enc = (s: string) => new TextEncoder().encode(s);

// The mock init fixture: counts runs via the harness recorder global (_REC)
// and returns its entry function, which records the payload the stub passes.
const INIT_SRC = `-- mock init fixture (harness contract: chunk returns entry function)
_REC.initRuns = _REC.initRuns + 1
return function(p)
  _REC.entryCalls = _REC.entryCalls + 1
  _REC.payload = p
  return true
end
`;

const SCRIPT_ID = "0123456789abcdef0123456789abcdef";
const BASE = {
  scriptId: SCRIPT_ID,
  apiBase: "https://auth.example.net",
  staticBase: "https://cdn.example.net",
};

// Lua 5.4 toolchain resolution: portable install from the session bootstrap
// (~/.lua54/bin) first, then PATH.
function findBin(name: string): string {
  const home = process.env.HOME ?? "/home/z";
  for (const dir of [`${home}/.lua54/bin`, `${home}/bin`]) {
    const candidate = `${dir}/${name}`;
    if (existsSync(candidate)) return candidate;
  }
  return name;
}

const LUA = process.env.LUA54 ?? findBin("lua5.4");
const LUAC = process.env.LUAC54 ?? findBin("luac5.4");
const HARNESS = import.meta.dir + "/../lua/harness.lua";

let counter = 0;

async function setup(): Promise<{ dir: string; stub1: string; stub2: string; init: string }> {
  const dir = `/tmp/m13-harness-${Date.now()}-${counter++}`;
  await $`mkdir -p ${dir}`;
  const initBytes = enc(INIT_SRC);
  const build = await packageInit(initBytes, 1760001234);
  const stub1 = generateStub({ ...BASE, build: build.build, initBytes, nowSec: 1760001234 });
  const stub2 = generateStub({ ...BASE, build: build.build, initBytes, nowSec: 1760001300 });
  const stub1Path = `${dir}/stub1.lua`;
  const stub2Path = `${dir}/stub2.lua`;
  const initPath = `${dir}/init.lua`;
  await Bun.write(stub1Path, stub1.body);
  await Bun.write(stub2Path, stub2.body);
  await Bun.write(initPath, initBytes);
  return { dir: dir, stub1: stub1Path, stub2: stub2Path, init: initPath };
}

async function runScenario(scenario: string): Promise<{ exitCode: number; output: string }> {
  const s = await setup();
  const proc = await $`${LUA} ${HARNESS} ${scenario} ${s.stub1} ${s.stub2} ${s.init} ${s.dir}`.nothrow().quiet();
  await $`rm -rf ${s.dir}`;
  return { exitCode: proc.exitCode, output: proc.stdout.toString() + proc.stderr.toString() };
}

describe("lua harness: executor-environment scenarios", () => {
  test("fresh: download, validate, cache, run, correct payload", async () => {
    const r = await runScenario("fresh");
    expect(r.output).toContain("scenario fresh: 0 failure(s)");
    expect(r.exitCode).toBe(0);
  });

  test("cache-hit: second stub run uses the cached init", async () => {
    const r = await runScenario("cache-hit");
    expect(r.output).toContain("scenario cache-hit: 0 failure(s)");
    expect(r.exitCode).toBe(0);
  });

  test("corrupt-cache: tampered bytes detected and repaired", async () => {
    const r = await runScenario("corrupt-cache");
    expect(r.output).toContain("scenario corrupt-cache: 0 failure(s)");
    expect(r.exitCode).toBe(0);
  });

  test("truncated-cache: size mismatch detected and repaired", async () => {
    const r = await runScenario("truncated-cache");
    expect(r.output).toContain("scenario truncated-cache: 0 failure(s)");
    expect(r.exitCode).toBe(0);
  });

  test("no-bit32: DJB2+size validation still works", async () => {
    const r = await runScenario("no-bit32");
    expect(r.output).toContain("scenario no-bit32: 0 failure(s)");
    expect(r.exitCode).toBe(0);
  });

  test("write-fail: init runs even when the cache write fails", async () => {
    const r = await runScenario("write-fail");
    expect(r.output).toContain("scenario write-fail: 0 failure(s)");
    expect(r.exitCode).toBe(0);
  });

  test("download-fail: generic failure, nothing loaded or cached", async () => {
    const r = await runScenario("download-fail");
    expect(r.output).toContain("scenario download-fail: 0 failure(s)");
    expect(r.exitCode).toBe(0);
  });

  test("bad-body: tampered download rejected before loadstring", async () => {
    const r = await runScenario("bad-body");
    expect(r.output).toContain("scenario bad-body: 0 failure(s)");
    expect(r.exitCode).toBe(0);
  });

  test("no-request: clean generic failure", async () => {
    const r = await runScenario("no-request");
    expect(r.output).toContain("scenario no-request: 0 failure(s)");
    expect(r.exitCode).toBe(0);
  });

  test("no-loadstring: clean generic failure", async () => {
    const r = await runScenario("no-loadstring");
    expect(r.output).toContain("scenario no-loadstring: 0 failure(s)");
    expect(r.exitCode).toBe(0);
  });
});

describe("generated stub syntax gates", () => {
  test("luac5.4 -p accepts the generated stub (valid plain Lua)", async () => {
    const s = await setup();
    const proc = await $`${LUAC} -p ${s.stub1}`.nothrow().quiet();
    await $`rm -rf ${s.dir}`;
    expect(proc.exitCode).toBe(0);
  });

  test("harness rejects a stub whose expected values do not match the served init", async () => {
    // Regenerate the init with different content AFTER packaging: the stub
    // then carries stale expected hashes and must refuse to run the init.
    const dir = `/tmp/m13-negative-${Date.now()}`;
    await $`mkdir -p ${dir}`;
    const initBytes = enc(INIT_SRC);
    const build = await packageInit(initBytes, 1760001234);
    const stub = generateStub({ ...BASE, build: build.build, initBytes, nowSec: 1760001234 });
    await Bun.write(`${dir}/stub1.lua`, stub.body);
    await Bun.write(`${dir}/stub2.lua`, stub.body);
    await Bun.write(`${dir}/init.lua`, enc(INIT_SRC + "-- mutated\n"));
    const proc = await $`${LUA} ${HARNESS} fresh ${dir}/stub1.lua ${dir}/stub2.lua ${dir}/init.lua ${dir}`.nothrow().quiet();
    const out = proc.stdout.toString();
    await $`rm -rf ${dir}`;
    expect(out).toContain("FAIL fresh: init entry received payload");
    expect(proc.exitCode).toBe(1);
  });
});
