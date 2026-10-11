/**
 * M6 corpus end-to-end runner (NOT shipped as a test — the corpus is the
 * project's captured material; run it locally like M4's corpus.ts):
 *
 *   bun run tests/corpus-e2e.ts <corpus-root>
 *
 * Full §10.2 pipeline per file: M4 parse → M5 compile+pack → M6 emit
 * (containerless) → run under real lua5.4 as {b,c,s} entry → compare
 * stdout byte-for-byte against the original source run directly.
 *
 * Honest oracle model (the corpus is game-script material, not test
 * fixtures): a file participates only when its ORACLE is runnable —
 * exits 0 within the timeout and produces stdout — and deterministic
 * (two oracle runs byte-equal). Everything else is counted in its own
 * bucket (host-dep/error, no-output, nondeterministic, parse-reject,
 * compile-reject) — never silently skipped.
 */

import { spawnSync } from 'node:child_process';
import { mkdtempSync, writeFileSync, rmSync, readFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { readdirSync, statSync } from 'node:fs';
import { parse } from '../../src/parser';
import { compileProgram } from '../../compiler/src/compile';
import { pack } from '../../compiler/src/container';
import { emitRuntime } from '../src/emit';
import { sha256Raw } from '../../compiler/src/opcode';

const LUA54 = process.env.LUA54 ?? join(process.env.HOME ?? '/home/z', '.lua54', 'bin', 'lua5.4');
const RUN_TIMEOUT_MS = 15_000;

function* walk(dir: string): Generator<string> {
  for (const entry of readdirSync(dir)) {
    const p = join(dir, entry);
    if (statSync(p).isDirectory()) yield* walk(p);
    else if (entry.endsWith('.lua')) yield p;
  }
}

interface RunResult {
  ok: boolean;
  out: string;
  err: string;
}

function runLuaMain(files: Record<string, string>, main: string): RunResult {
  const dir = mkdtempSync(join(tmpdir(), 'm6cor-'));
  try {
    for (const [name, content] of Object.entries(files)) {
      writeFileSync(join(dir, name), content, 'utf8');
    }
    const res = spawnSync(LUA54, [main], { encoding: 'utf8', timeout: RUN_TIMEOUT_MS, cwd: dir });
    if (res.error) return { ok: false, out: '', err: String(res.error) };
    if (res.status !== 0 || res.signal) return { ok: false, out: res.stdout ?? '', err: (res.stderr ?? '').slice(0, 200) };
    return { ok: true, out: res.stdout ?? '', err: '' };
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
}

function luaByteString(bytes: Uint8Array): string {
  let out = '';
  for (let i = 0; i < bytes.length; i++) out += `\\${String(bytes[i]!).padStart(3, '0')}`;
  return out;
}

/** deterministic seeds from the file path (reproducible runs). */
function seedsFor(path: string): { constKey: Uint8Array; opcodeSeed: Uint8Array; vmSeed: Uint8Array } {
  const h1 = sha256Raw(Buffer.from(`m6corpus-c:${path}`, 'utf8'));
  const h2 = sha256Raw(Buffer.from(`m6corpus-o:${path}`, 'utf8'));
  const h3 = sha256Raw(Buffer.from(`m6corpus-v:${path}`, 'utf8'));
  return { constKey: h1, opcodeSeed: h2, vmSeed: h3 };
}

const root = process.argv[2];
if (!root) {
  console.error('usage: bun run tests/corpus-e2e.ts <corpus-root>');
  process.exit(2);
}

type Bucket = 'match' | 'error-parity' | 'parse-reject' | 'compile-reject' | 'oracle-fail' | 'no-output' | 'nondeterministic' | 'MISMATCH' | 'emit-reject';
const results = new Map<Bucket, string[]>();
const note = (b: Bucket, f: string, why = '') => {
  const arr = results.get(b) ?? [];
  arr.push(why ? `${f} (${why})` : f);
  results.set(b, arr);
};

let total = 0;
for (const file of walk(root)) {
  total++;
  const rel = file.slice(root.length + 1);
  const source = readFileSync(file, 'utf8');

  let chunk;
  try {
    chunk = parse(source);
  } catch (e) {
    note('parse-reject', rel, String((e as Error).message).slice(0, 80));
    continue;
  }

  // ---- pipeline FIRST (M5 compile + pack, M6 emit) — coverage signal ----
  let protos;
  try {
    protos = compileProgram(chunk).protos;
  } catch (e) {
    note('compile-reject', rel, String((e as Error).message).slice(0, 60));
    continue;
  }
  const seeds = seedsFor(rel);
  let container;
  try {
    ({ container } = pack(protos, { constKey: seeds.constKey, opcodeSeed: seeds.opcodeSeed }));
  } catch (e) {
    note('compile-reject', rel, `pack: ${String((e as Error).message).slice(0, 60)}`);
    continue;
  }
  let runtimeLua;
  try {
    runtimeLua = emitRuntime({ container: null, opcodeSeed: seeds.opcodeSeed, vmSeed: seeds.vmSeed, dispatch: 'chain' }).lua;
  } catch (e) {
    note('emit-reject', rel, String((e as Error).message).slice(0, 80));
    continue;
  }

  // ---- oracle: the original source under the same lua5.4, twice ----
  const oracle1 = runLuaMain({ 'src.lua': source }, 'src.lua');
  if (!oracle1.ok && oracle1.out.length === 0 && oracle1.err === 'Error: Spawn TIMED OUT') {
    // bucket below via protected-timeout parity
  }
  if (oracle1.ok && oracle1.out.length === 0) {
    note('no-output', rel);
    continue;
  }
  let oracle: string;
  if (oracle1.ok) {
    const oracle2 = runLuaMain({ 'src.lua': source }, 'src.lua');
    if (!oracle2.ok || oracle2.out !== oracle1.out) {
      note('nondeterministic', rel);
      continue;
    }
    oracle = oracle1.out;
  } else {
    oracle = '';
  }

  // ---- protected run ----
  const main = `local entry = dofile("runtime.lua")
local ok, e1 = pcall(entry, {
  b = "${luaByteString(container)}",
  c = "${luaByteString(seeds.constKey)}",
  s = "corpus-e2e",
  args = {}, nargs = 0,
})
if not ok then error(e1, 0) end`;
  const protectedRun = runLuaMain({ 'runtime.lua': runtimeLua, 'main.lua': main }, 'main.lua');

  if (oracle1.ok) {
    // execution differential (oracle produced deterministic output)
    if (protectedRun.ok && protectedRun.out === oracle) {
      note('match', rel);
    } else {
      note('MISMATCH', rel, protectedRun.ok ? 'stdout differs' : `protected failed: ${protectedRun.err.split('\n')[0]!.slice(0, 80)}`);
    }
    continue;
  }

  // oracle failed: the corpus is game-script material — the honest check is
  // ERROR PARITY: the protected form must reach the guest's own failure
  // boundary (a guest-level error or the same timeout), never an M6-level
  // load failure ("load failed" = decode/dispatch/pool stage).
  if (!protectedRun.ok) {
    const firstErr = protectedRun.err.split('\n')[0] ?? '';
    if (firstErr.includes('load failed')) {
      note('MISMATCH', rel, 'protected: M6-level load failure (guest never reached)');
      continue;
    }
    note('error-parity', rel, firstErr.slice(0, 60));
    continue;
  }
  // protected SUCCEEDED where the oracle failed — suspicious in general,
  // but the oracle failure may be timing-dependent (timeout); report as
  // its own bucket for inspection.
  note('oracle-fail', rel, `oracle: ${oracle1.err.split('\n')[0]?.slice(0, 60)} / protected: ok`);
}

console.log(`\nM6 corpus end-to-end — root: ${root}`);
console.log(`total files: ${total}`);
for (const bucket of ['match', 'error-parity', 'MISMATCH', 'parse-reject', 'compile-reject', 'oracle-fail', 'no-output', 'nondeterministic', 'emit-reject'] as Bucket[]) {
  const arr = results.get(bucket) ?? [];
  console.log(`${bucket}: ${arr.length}`);
  if (bucket === 'MISMATCH' || bucket === 'error-parity' || bucket === 'no-output' || bucket === 'nondeterministic') {
    for (const f of arr.slice(0, 20)) console.log(`    - ${f}`);
    if (arr.length > 20) console.log(`    ... and ${arr.length - 20} more`);
  }
  if (bucket === 'compile-reject') {
    const hist = new Map<string, number>();
    for (const f of arr) {
      const cause = f.slice(f.indexOf('(') + 1, f.lastIndexOf(')'));
      hist.set(cause, (hist.get(cause) ?? 0) + 1);
    }
    const sorted = [...hist.entries()].sort((a, b) => b[1] - a[1]);
    for (const [cause, n] of sorted) console.log(`    ${n}x ${cause}`);
  }
}
const mismatches = (results.get('MISMATCH') ?? []).length;
process.exit(mismatches > 0 ? 1 : 0);
