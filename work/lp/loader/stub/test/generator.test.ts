import { describe, expect, test } from "bun:test";
import { generateStub } from "../src/generator";
import { escapeLuaString } from "../src/template";
import { packageInit } from "../src/initpack";

const enc = (s: string) => new TextEncoder().encode(s);

const INIT_SRC = `-- init fixture
_REC.initRuns = _REC.initRuns + 1
return function(p)
  _REC.entryCalls = _REC.entryCalls + 1
  _REC.payload = p
  return true
end
`;

const FIXED = (n: number): Uint8Array => {
  const b = new Uint8Array(n);
  for (let i = 0; i < n; i++) b[i] = (i * 37 + 11) % 256;
  return b;
};

const BASE = {
  scriptId: "0123456789abcdef0123456789abcdef",
  apiBase: "https://auth.example.net",
  staticBase: "https://cdn.example.net",
  nowSec: 1760001234,
};

describe("generateStub", () => {
  test("embeds script id, build, bases, and per-fetch values", async () => {
    const initBytes = enc(INIT_SRC);
    const build = await packageInit(initBytes, BASE.nowSec);
    const stub = generateStub({ ...BASE, build: build.build, initBytes });
    expect(stub.body).toContain(`local SCRIPT_ID = "${BASE.scriptId}"`);
    expect(stub.body).toContain(`local BUILD = "${build.build}"`);
    expect(stub.body).toContain(`local API = "${BASE.apiBase}"`);
    expect(stub.body).toContain(`local STATIC = "${BASE.staticBase}"`);
    expect(stub.body).toContain(`local FETCH_T = ${BASE.nowSec}`);
    expect(stub.body).toContain(`local EXPECT_LEN = ${initBytes.length}`);
    expect(stub.body).toContain(`local EXPECT_FNV = ${build.fnv}`);
    expect(stub.body).toContain(`local EXPECT_DJB = ${build.djb}`);
    expect(stub.body).toContain('local CACHE_DIR = "lp"');
  });

  test("unique per fetch: fresh stub id, random, fetch time", async () => {
    const initBytes = enc(INIT_SRC);
    const build = await packageInit(initBytes, BASE.nowSec);
    const a = generateStub({ ...BASE, build: build.build, initBytes });
    const b = generateStub({ ...BASE, build: build.build, initBytes });
    expect(a.body).not.toBe(b.body);
    expect(a.stubId).not.toBe(b.stubId);
    const ra = a.body.match(/local STUB_R = "([0-9a-f]{64})"/)?.[1];
    const rb = b.body.match(/local STUB_R = "([0-9a-f]{64})"/)?.[1];
    expect(ra).toBeDefined();
    expect(rb).toBeDefined();
    expect(ra).not.toBe(rb);
    expect(a.body).toContain(`local STUB_ID = "${a.stubId}"`);
  });

  test("different fetch time -> different body", async () => {
    const initBytes = enc(INIT_SRC);
    const build = await packageInit(initBytes, BASE.nowSec);
    const a = generateStub({ ...BASE, build: build.build, initBytes, nowSec: 1000 });
    const b = generateStub({ ...BASE, build: build.build, initBytes, nowSec: 2000 });
    expect(a.body).not.toBe(b.body);
  });

  test("deterministic under injected randomness", async () => {
    const initBytes = enc(INIT_SRC);
    const build = await packageInit(initBytes, BASE.nowSec);
    const seq = FIXED(64);
    let pos = 0;
    const rnd = (n: number) => {
      const out = seq.slice(pos, pos + n);
      pos += n;
      return out;
    };
    const a = generateStub({ ...BASE, build: build.build, initBytes, randomBytes: rnd });
    pos = 0;
    const b = generateStub({ ...BASE, build: build.build, initBytes, randomBytes: rnd });
    expect(a.body).toBe(b.body);
  });

  test("response headers: text/plain + no-store (unique per fetch)", async () => {
    const initBytes = enc(INIT_SRC);
    const build = await packageInit(initBytes, BASE.nowSec);
    const stub = generateStub({ ...BASE, build: build.build, initBytes });
    expect(stub.headers["content-type"]).toBe("text/plain; charset=utf-8");
    expect(stub.headers["cache-control"]).toBe("no-store");
  });

  test("rejects unsafe template numbers (NaN, out-of-range)", async () => {
    const initBytes = enc(INIT_SRC);
    const build = await packageInit(initBytes, BASE.nowSec);
    expect(() =>
      generateStub({ ...BASE, build: build.build, initBytes, nowSec: NaN }),
    ).toThrow();
    expect(() =>
      generateStub({ ...BASE, build: build.build, initBytes, nowSec: 1e20 }),
    ).toThrow();
  });
});

describe("escapeLuaString", () => {
  test("escapes backslash, quote, newline, control and non-ascii bytes", () => {
    expect(escapeLuaString('a"b\\c')).toBe('"a\\"b\\\\c"');
    expect(escapeLuaString("line\nbreak")).toBe('"line\\nbreak"');
    expect(escapeLuaString("tab\there")).toBe('"tab\\009here"');
    expect(escapeLuaString("del\x7f")).toBe('"del\\127"');
  });
  test("escaped output stays on one line", () => {
    const evil = "x\ny\r\nz\x00\x01";
    const out = escapeLuaString(evil);
    expect(out.includes("\n")).toBe(false);
    expect(out.includes("\r")).toBe(false);
  });
});

describe("renderStub shape", () => {
  test("contains no goto and no long-form 5.2+ syntax", async () => {
    const initBytes = enc(INIT_SRC);
    const build = await packageInit(initBytes, BASE.nowSec);
    const body = generateStub({ ...BASE, build: build.build, initBytes }).body;
    expect(body.includes("goto")).toBe(false);
    expect(body.includes("::")).toBe(false);
    expect(body.includes("+=")).toBe(false);
    expect(body.includes("continue")).toBe(false);
  });
});
