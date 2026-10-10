/**
 * API / determinism / syntax-safety / entry-contract tests.
 */

import { describe, expect, test } from 'bun:test';
import { spawnSync } from 'node:child_process';
import { FIXTURES } from '../../compiler/tests/fixtures';
import { buildProtected, cryptoBytes, runLua, luaByteString } from './helpers';
import { emitRuntime } from '../src/emit';
import { deriveConstKey } from '../src';
import { compileProgram } from '../../compiler/src/compile';
import { pack } from '../../compiler/src/container';
import { join } from 'node:path';
import { mkdtempSync, writeFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';

const LUAC54 = process.env.LUAC54 ?? join(process.env.HOME ?? '/home/z', '.lua54', 'bin', 'luac5.4');

describe('api surface', () => {
  const fixture = FIXTURES[0]!;
  const { protos } = compileProgram(fixture.ast);
  const constKey = cryptoBytes(32);
  const opcodeSeed = cryptoBytes(32);
  const { container } = pack(protos, { constKey, opcodeSeed });

  test('placeholder pre-pass -> real pass: code region stable (checksums equal)', () => {
    const vmSeed = cryptoBytes(32);
    const pre = emitRuntime({ container: { placeholderLength: container.length }, opcodeSeed, vmSeed, dispatch: 'chain' });
    const real = emitRuntime({ container, opcodeSeed, vmSeed, dispatch: 'chain' });
    expect(pre.vmChecksums).toEqual(real.vmChecksums);
    expect(pre.blobLength).toBe(real.blobLength);
    expect(pre.dispatch).toBe(real.dispatch);
  });

  test('deriveConstKey: checksum sensitivity (§10.2 item 9 build-time leg)', () => {
    const vmSeed = cryptoBytes(32);
    const a = emitRuntime({ container, opcodeSeed, vmSeed });
    const b = emitRuntime({ container, opcodeSeed, vmSeed: cryptoBytes(32) });
    const k1 = deriveConstKey(cryptoBytes(32), a.vmChecksums);
    const k2 = deriveConstKey(cryptoBytes(32), b.vmChecksums);
    expect(k1.length).toBe(32);
    expect(Buffer.from(k1).equals(Buffer.from(k2))).toBe(false);
  });

  test('emitted source: no goto, no //, no compound assign, no continue', () => {
    for (const dispatch of ['chain', 'tree', 'closure'] as const) {
      for (let i = 0; i < 3; i++) {
        const r = emitRuntime({ container, opcodeSeed, vmSeed: cryptoBytes(32), dispatch });
        expect(/\bgoto\b/.test(r.lua)).toBe(false);
        expect(/\/\//.test(r.lua)).toBe(false);
        expect(/\+=|-=|\*=|\/=|%=|\^=|\.\.=/.test(r.lua)).toBe(false);
        expect(/\bcontinue\b/.test(r.lua)).toBe(false);
        expect(/^--/m.test(r.lua)).toBe(false); // comment-free
      }
    }
  });

  test('luac5.4 -p parses every strategy + both embed variants', () => {
    const dir = mkdtempSync(join(tmpdir(), 'm6-luac-'));
    try {
      const variants = [
        { dispatch: 'chain' as const }, { dispatch: 'tree' as const },
        { dispatch: 'closure' as const, runtimeBuilt: false },
        { dispatch: 'closure' as const, runtimeBuilt: true },
      ];
      for (const v of variants) {
        for (let i = 0; i < 2; i++) {
          const r = emitRuntime({ container, opcodeSeed, vmSeed: cryptoBytes(32), ...v });
          const f = join(dir, `rt_${v.dispatch}_${v.runtimeBuilt ? 'b' : 'd'}_${i}.lua`);
          writeFileSync(f, r.lua, 'utf8');
          const res = spawnSync(LUAC54, ['-p', f], { encoding: 'utf8' });
          if (res.status !== 0) throw new Error(`luac -p failed for ${v.dispatch}: ${res.stderr}`);
        }
      }
    } finally {
      rmSync(dir, { recursive: true, force: true });
    }
  });

  test('size sanity', () => {
    const r = emitRuntime({ container, opcodeSeed, vmSeed: cryptoBytes(32) });
    expect(r.lua.length).toBeGreaterThan(20_000);
    expect(r.lua.length).toBeLessThan(5_000_000);
  });
});

describe('entry contract (RUNTIME-M6.md)', () => {
  const fixture = FIXTURES[3]!; // closures/upvalues-ish fixture

  test('env passthrough: guest globals read a custom env', () => {
    const p = buildProtected(fixture, {});
    const main = `local entry = dofile("runtime.lua")
local myenv = { print = print, pairs = pairs, ipairs = ipairs, next = next, tostring = tostring, select = select, type = type, table = table, string = string, math = math, GREET = "hi-from-env" }
local ok, e1 = pcall(entry, { c = "${luaByteString(p.constKey)}", s = "q", env = myenv, args = {}, nargs = 0 })
if not ok then error(e1, 0) end`;
    const out = runLua({ 'runtime.lua': p.emit.lua, 'main.lua': main }, 'main.lua');
    expect(out.length).toBeGreaterThan(0);
    // The guest's output must be produced through the custom env's print.
    expect(out).toBe(runLua({ 'src.lua': fixture.source }, 'src.lua'));
  });

  test('args pass to the vararg main proto', () => {
    // Fixture with varargs: entry.args -> GETVARARGS.
    const vf = FIXTURES.find((f) => f.name.includes('vararg')) ?? FIXTURES[5]!;
    const p = buildProtected(vf, {});
    const main = `local entry = dofile("runtime.lua")
local ok, e1 = pcall(entry, { c = "${luaByteString(p.constKey)}", s = "q", args = {}, nargs = 0 })
if not ok then error(e1, 0) end`;
    const out = runLua({ 'runtime.lua': p.emit.lua, 'main.lua': main }, 'main.lua');
    expect(out).toBe(runLua({ 'src.lua': vf.source }, 'src.lua'));
  });

  test('double entry call works (state is per-call)', () => {
    const p = buildProtected(fixture, { dispatch: 'closure', runtimeBuilt: true });
    const main = `local entry = dofile("runtime.lua")
local c = "${luaByteString(p.constKey)}"
local a1 = select(1, entry({ c = c, s = "q", args = {}, nargs = 0 }))
local b1 = select(1, entry({ c = c, s = "q", args = {}, nargs = 0 }))
print("twice-ok")`;
    const out = runLua({ 'runtime.lua': p.emit.lua, 'main.lua': main }, 'main.lua');
    expect(out).toContain('twice-ok');
  });
});
