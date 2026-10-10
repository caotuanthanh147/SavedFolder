/**
 * Tamper / wrong-key / wrong-seed tests (doc §10.2 item 9): corruption
 * must NEVER silently produce the oracle output — it either errors with a
 * generic message or produces garbage. The build hash + per-fetch `s`
 * validity select a DECOY constKey derivation (garbage constants), and
 * trap slots refuse to load.
 */

import { describe, expect, test } from 'bun:test';
import { FIXTURES } from '../../compiler/tests/fixtures';
import { buildProtected, cryptoBytes, runLua, runnerScript, luaByteString } from './helpers';
import { emitRuntime } from '../src/emit';
import { compileProgram } from '../../compiler/src/compile';
import { pack } from '../../compiler/src/container';

function tryRun(files: Record<string, string>, main: string): { ok: boolean; out: string } {
  try {
    return { ok: true, out: runLua(files, main) };
  } catch (e) {
    return { ok: false, out: String(e) };
  }
}

describe('tamper resistance (§10.2 item 9)', () => {
  const fixture = FIXTURES[2]!; // strings fixture (rich const pool)
  const oracle = runLua({ 'src.lua': fixture.source }, 'src.lua');

  test('bit flip in the pool section -> no oracle output', () => {
    const p = buildProtected(fixture, {
      tamperContainer: (b) => {
        const c = new Uint8Array(b);
        c[c.length - 6] ^= 0xff; // inside the last AEAD tag
        return c;
      },
    });
    const r = tryRun({ 'runtime.lua': p.emit.lua, 'main.lua': runnerScript(p) }, 'main.lua');
    expect(r.ok ? r.out : '').not.toBe(oracle);
    expect(r.ok ? r.out : r.out).not.toContain(oracle);
  });

  test('bit flip in the functions section -> no oracle output', () => {
    const p = buildProtected(fixture, {
      tamperContainer: (b) => {
        const c = new Uint8Array(b);
        c[40] ^= 0x55; // early functions byte
        return c;
      },
    });
    const r = tryRun({ 'runtime.lua': p.emit.lua, 'main.lua': runnerScript(p) }, 'main.lua');
    expect(r.ok ? r.out : '').not.toBe(oracle);
  });

  test('wrong constKey (right length) -> AEAD failure, no oracle output', () => {
    const p = buildProtected(fixture, {});
    const wrong = cryptoBytes(32);
    const main = `local entry = dofile("runtime.lua")
local ok, e1 = pcall(entry, { c = "${luaByteString(wrong)}", s = "q", args = {}, nargs = 0 })
if not ok then error(e1, 0) end`;
    const r = tryRun({ 'runtime.lua': p.emit.lua, 'main.lua': main }, 'main.lua');
    expect(r.ok ? r.out : '').not.toBe(oracle);
  });

  test('short constKey / non-string -> decoy path, no oracle output', () => {
    const p = buildProtected(fixture, {});
    const main = `local entry = dofile("runtime.lua")
local ok, e1 = pcall(entry, { c = "tooshort", s = "q", args = {}, nargs = 0 })
if not ok then error(e1, 0) end`;
    const r = tryRun({ 'runtime.lua': p.emit.lua, 'main.lua': main }, 'main.lua');
    expect(r.ok ? r.out : '').not.toBe(oracle);
  });

  test('oversized per-fetch s -> decoy path (per-fetch validity, §5.6)', () => {
    const p = buildProtected(fixture, {});
    const s65 = 'a'.repeat(65);
    const main = `local entry = dofile("runtime.lua")
local ok, e1 = pcall(entry, { c = "${luaByteString(p.constKey)}", s = "${s65}", args = {}, nargs = 0 })
if not ok then error(e1, 0) end`;
    const r = tryRun({ 'runtime.lua': p.emit.lua, 'main.lua': main }, 'main.lua');
    expect(r.ok ? r.out : '').not.toBe(oracle);
  });

  test('wrong opcodeSeed at emit (trap slots / garbage stream) -> no oracle output', () => {
    const { protos } = compileProgram(fixture.ast);
    const constKey = cryptoBytes(32);
    const opcodeSeed = cryptoBytes(32);
    const { container } = pack(protos, { constKey, opcodeSeed });
    const emit = emitRuntime({
      container,
      opcodeSeed: cryptoBytes(32), // DIFFERENT seed: wrong inverse map baked
      vmSeed: cryptoBytes(32),
    });
    const main = `local entry = dofile("runtime.lua")
local ok, e1 = pcall(entry, { c = "${luaByteString(constKey)}", s = "q", args = {}, nargs = 0 })
if not ok then error(e1, 0) end`;
    const r = tryRun({ 'runtime.lua': emit.lua, 'main.lua': main }, 'main.lua');
    expect(r.ok ? r.out : '').not.toBe(oracle);
  });

  test('truncated container -> generic failure', () => {
    const p = buildProtected(fixture, {
      tamperContainer: (b) => b.subarray(0, Math.floor(b.length / 2)),
    });
    const r = tryRun({ 'runtime.lua': p.emit.lua, 'main.lua': runnerScript(p) }, 'main.lua');
    expect(r.ok).toBe(false);
    expect(r.out).toContain('load failed');
  });

  test('CRC trailer is NOT checked by the runtime (D-M6-7) — flip is inert', () => {
    const p = buildProtected(fixture, {
      tamperContainer: (b) => {
        const c = new Uint8Array(b);
        c[c.length - 1] ^= 0xff; // last CRC byte
        return c;
      },
    });
    const out = runLua({ 'runtime.lua': p.emit.lua, 'main.lua': runnerScript(p) }, 'main.lua');
    expect(out).toBe(oracle); // inert by design: AEAD + build hash cover it
  });
});
