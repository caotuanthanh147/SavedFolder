/**
 * M6 corpus end-to-end runner (NOT shipped as a test — the corpus is the
 * project's captured material; run it locally like M4's corpus.ts):
 *
 *   bun run tests/corpus-e2e.ts <corpus-root> [--wm]
 *
 * --wm: pack WATERMARKED containers (CCP-M7 v1, per-version default key)
 * and verify per file that extractWatermark recovers the watermark from
 * the exact container bytes the runtime consumed.
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
import { generatePackMaterial, packWatermarked, extractWatermark } from '../../compiler/src/watermark';
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

/** Map a PUC-lua error line to an execution-error class ('' = not a
 * runtime-error line — parse/syntax failures fall here). Used by the
 * error-parity CLASS gate (session 22): when the oracle's failure is an
 * execution error, the protected run's first error must be the SAME class
 * — the guest reached its own first failing operation, not a different one. */
function errClass(line: string): string {
  if (/syntax error|unexpected symbol|near '/.test(line)) return 'parse';
  if (/attempt to call a nil value/.test(line)) return 'call-nil';
  if (/attempt to call a (number|string|boolean|table) value/.test(line)) return 'call-noncallable';
  if (/attempt to index a nil value/.test(line)) return 'index-nil';
  if (/attempt to index a (number|string|boolean) value/.test(line)) return 'index-nonindexable';
  if (/attempt to perform arithmetic/.test(line)) return 'arith';
  if (/attempt to concatenate/.test(line)) return 'concat';
  if (/attempt to compare/.test(line)) return 'compare';
  if (/stack overflow/.test(line)) return 'stack-overflow';
  if (/Spawn TIMED OUT|timeout/i.test(line)) return 'timeout';
  return 'other';
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
  console.error('usage: bun run tests/corpus-e2e.ts <corpus-root> [--wm]');
  process.exit(2);
}
/** --wm: pack WATERMARKED containers (CCP-M7 v1, per-version default key)
 * and verify per file that extractWatermark recovers the watermark from
 * the exact bytes the runtime consumed. */
const WM_MODE = process.argv.includes('--wm');

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
  let runtimeConstKey: Uint8Array = seeds.constKey;
  let runtimeOpcodeSeed: Uint8Array = seeds.opcodeSeed;
  let wmExtractOk = true;
  let wmExtractWhy = '';
  try {
    if (WM_MODE) {
      const wm = sha256Raw(Buffer.from(`m6corpus-w:${rel}`, 'utf8')).slice(0, 16);
      const { parts } = generatePackMaterial(protos);
      ({ container } = packWatermarked(parts, wm));
      runtimeConstKey = parts.constKey;
      runtimeOpcodeSeed = parts.opcodeSeed;
      const got = extractWatermark(container, parts);
      if (!got || !got.carrier1Ok) {
        wmExtractOk = false;
        wmExtractWhy = 'extraction failed post-pack';
      } else {
        const rec = Buffer.from(got.watermark);
        if (!rec.equals(Buffer.from(wm))) {
          wmExtractOk = false;
          wmExtractWhy = 'watermark bytes differ';
        }
      }
    } else {
      ({ container } = pack(protos, { constKey: seeds.constKey, opcodeSeed: seeds.opcodeSeed }));
    }
  } catch (e) {
    note('compile-reject', rel, `pack: ${String((e as Error).message).slice(0, 60)}`);
    continue;
  }
  if (WM_MODE && !wmExtractOk) {
    // the runtime run is skipped — a failed extraction is already a hard
    // failure of the watermark pipeline for this file
    note('MISMATCH', rel, `watermark extraction: ${wmExtractWhy}`);
    continue;
  }
  let runtimeLua;
  try {
    runtimeLua = emitRuntime({ container: null, opcodeSeed: runtimeOpcodeSeed, vmSeed: seeds.vmSeed, dispatch: 'chain' }).lua;
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
  c = "${luaByteString(runtimeConstKey)}",
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
    // CLASS gate (session 22): when the oracle's failure is an EXECUTION
    // error, the protected first error must carry the same class — same
    // guest operation, reached through the container. Oracle parse-fails
    // (Luau-only syntax under PUC lua5.4) have no execution class to
    // compare; guest-boundary reach is the check there (kept as its own
    // sub-tally so the two populations never blur).
    const oc = errClass(oracle1.err.split('\n')[0] ?? '');
    const pc = errClass(firstErr);
    if (oc && oc !== 'parse') {
      if (pc !== oc) {
        note('MISMATCH', rel, `error-class differs: oracle ${oc} vs protected ${pc || 'n/a'}`);
        continue;
      }
      note('error-parity', rel, `class=${oc}: ${firstErr.slice(0, 50)}`);
      continue;
    }
    note('error-parity', rel, `oracle-parse, prot ${pc || '?'}: ${firstErr.slice(0, 44)}`);
    continue;
  }
  // protected SUCCEEDED where the oracle failed — suspicious in general,
  // but the oracle failure may be timing-dependent (timeout); report as
  // its own bucket for inspection.
  note('oracle-fail', rel, `oracle: ${oracle1.err.split('\n')[0]?.slice(0, 60)} / protected: ok`);
}

console.log(`\nM6 corpus end-to-end — root: ${root}`);
console.log(`total files: ${total}`);
if (WM_MODE) console.log('watermark mode: ON — packWatermarked per file + extraction lockstep verified');
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
