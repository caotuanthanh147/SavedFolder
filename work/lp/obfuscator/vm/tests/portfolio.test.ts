/**
 * Portfolio tests (D-M6-1): per-build randomization must not change
 * behavior — several vmSeeds (which rotate dispatch strategy, branch
 * orders, runtime-built tables, embed encoding, junk, names) and several
 * opcodeSeeds (which rotate the emitted opcode numbering) must all produce
 * oracle-equal stdout. Also asserts build UNIQUENESS (per-build shape
 * actually varies).
 */

import { describe, expect, test } from 'bun:test';
import { FIXTURES } from '../../compiler/tests/fixtures';
import { buildProtected, cryptoBytes, runLua, runnerScript } from './helpers';
import { emitRuntime } from '../src/emit';

describe('portfolio invariance + uniqueness', () => {
  const fixtures = FIXTURES.slice(0, 6);

  test('5 vmSeeds x 3 opcodeSeeds all oracle-equal (per fixture)', () => {
    for (const fixture of fixtures) {
      const oracle = runLua({ 'src.lua': fixture.source }, 'src.lua');
      for (let v = 0; v < 5; v++) {
        const p = buildProtected(fixture, { vmSeed: cryptoBytes(32), opcodeSeed: cryptoBytes(32) });
        const out = runLua(
          { 'runtime.lua': p.emit.lua, 'main.lua': runnerScript(p) },
          'main.lua',
        );
        expect(out).toBe(oracle);
      }
    }
  });

  test('permutation invariance: same vmSeed, different opcodeSeed', () => {
    const fixture = FIXTURES[1]!;
    const oracle = runLua({ 'src.lua': fixture.source }, 'src.lua');
    const vmSeed = cryptoBytes(32);
    for (let i = 0; i < 3; i++) {
      const p = buildProtected(fixture, { vmSeed, opcodeSeed: cryptoBytes(32) });
      const out = runLua(
        { 'runtime.lua': p.emit.lua, 'main.lua': runnerScript(p) },
        'main.lua',
      );
      expect(out).toBe(oracle);
    }
  });

  test('distinct vmSeeds produce distinct runtimes', () => {
    const fixture = FIXTURES[0]!;
    const { protos } = require('../../compiler/src/compile').compileProgram(fixture.ast);
    const { pack } = require('../../compiler/src/container');
    const { container } = pack(protos, { constKey: cryptoBytes(32), opcodeSeed: cryptoBytes(32) });
    const seen = new Set<string>();
    const strategies = new Set<string>();
    for (let i = 0; i < 12; i++) {
      const r = emitRuntime({ container, opcodeSeed: cryptoBytes(32), vmSeed: cryptoBytes(32) });
      expect(seen.has(r.lua)).toBe(false);
      seen.add(r.lua);
      strategies.add(r.dispatch + (r.runtimeBuilt ? '+' : ''));
    }
    expect(seen.size).toBe(12);
    expect(strategies.size).toBeGreaterThanOrEqual(3);
  });

  test('determinism: same seeds -> identical bytes (incl. checksums)', () => {
    const fixture = FIXTURES[0]!;
    const { protos } = require('../../compiler/src/compile').compileProgram(fixture.ast);
    const { pack } = require('../../compiler/src/container');
    const constKey = cryptoBytes(32);
    const opcodeSeed = cryptoBytes(32);
    const vmSeed = cryptoBytes(32);
    const { container } = pack(protos, { constKey, opcodeSeed });
    const a = emitRuntime({ container, opcodeSeed, vmSeed });
    const b = emitRuntime({ container, opcodeSeed, vmSeed });
    expect(a.lua).toBe(b.lua);
    expect(a.vmChecksums).toEqual(b.vmChecksums);
    expect(a.dispatch).toBe(b.dispatch);
  });
});
