/**
 * Differential tests (doc §10.3, D-M5-13 applied to M6 runtimes):
 * every fixture's SOURCE runs under real Lua 5.4.7 (outside oracle); the
 * protected form (M5 compile → pack → M6 emitted runtime) runs under the
 * SAME real Lua 5.4.7. Stdout must match byte-for-byte — for every
 * dispatch strategy in the portfolio.
 */

import { describe, expect, test } from 'bun:test';
import { FIXTURES } from '../../compiler/tests/fixtures';
import { buildProtected, luaByteString, runLua, runnerScript } from './helpers';

function oracleOf(source: string): string {
  return runLua({ 'src.lua': source }, 'src.lua');
}

describe('differential vs real Lua 5.4 (all strategies)', () => {
  const strategies = [
    { dispatch: 'chain' as const },
    { dispatch: 'tree' as const },
    { dispatch: 'closure' as const, runtimeBuilt: false },
    { dispatch: 'closure' as const, runtimeBuilt: true },
  ];

  for (const fixture of FIXTURES) {
    test(`fixture ${fixture.name}: oracle vs all strategies`, () => {
      const expected = oracleOf(fixture.source);
      for (const strat of strategies) {
        const p = buildProtected(fixture, strat);
        const out = runLua(
          { 'runtime.lua': p.emit.lua, 'main.lua': runnerScript(p) },
          'main.lua',
        );
        expect(out).toBe(expected);
      }
    });
  }

  test('fixture count sanity', () => {
    const names = FIXTURES.map((f) => f.name);
    expect(new Set(names).size).toBe(names.length);
    expect(names.length).toBeGreaterThanOrEqual(15);
  });
});

describe('differential — containerless mode (v1.1, CCP-M7 D-M5-20): container arrives via entry b', () => {
  // The deployment shape of doc §8 step 10: a FIXED runtime (immutable init
  // build) consumes per-session container bytes handed in at the entry.
  // Watermarked containers are ordinary valid v1 containers, so the
  // differential must hold for every fixture × strategy unchanged.
  const strategies = [
    { dispatch: 'chain' as const },
    { dispatch: 'tree' as const },
    { dispatch: 'closure' as const, runtimeBuilt: false },
    { dispatch: 'closure' as const, runtimeBuilt: true },
  ];

  for (const fixture of FIXTURES.slice(0, 10)) {
    test(`fixture ${fixture.name}: b-entry runtime, all strategies == oracle`, () => {
      const expected = oracleOf(fixture.source);
      for (const strat of strategies) {
        const p = buildProtected(fixture, { ...strat, containerless: true });
        expect(p.emit.containerless).toBe(true);
        const out = runLua(
          { 'runtime.lua': p.emit.lua, 'main.lua': runnerScript(p) },
          'main.lua',
        );
        expect(out).toBe(expected);
      }
    });
  }

  test('same program, two sessions (two entry calls, same runtime file) == oracle', () => {
    const fixture = FIXTURES[0]!;
    const expected = oracleOf(fixture.source);
    const p = buildProtected(fixture, { containerless: true });
    const main = `local entry = dofile("runtime.lua")
local blob = "${luaByteString(p.container)}"
local c = "${luaByteString(p.constKey)}"
local ok1 = pcall(entry, { c = c, s = "sess-one", b = blob, args = {}, nargs = 0 })
local ok2 = pcall(entry, { c = c, s = "sess-two", b = blob, args = {}, nargs = 0 })
if not ok1 or not ok2 then error("session run failed", 0) end`;
    const out = runLua({ 'runtime.lua': p.emit.lua, 'main.lua': main }, 'main.lua');
    expect(out).toBe(expected + expected);
  });
});

describe('differential vs M5 reference interpreter (second-implementation rule, BYTECODE-M5 §10)', () => {
  // M5-TS output is collected via console.log capture (its print host).
  for (const fixture of FIXTURES.slice(0, 8)) {
    test(`fixture ${fixture.name}: M6 runtime output == M5 interpreter output`, async () => {
      const { runContainer, makeInterpreterEnv } = await import('../../compiler/src/interpreter');
      const { compileProgram } = await import('../../compiler/src/compile');
      const { pack, randomBytes } = await import('../../compiler/src/container');
      const { emitRuntime } = await import('../src/emit');

      const lines: string[] = [];
      const origLog = console.log;
      console.log = (...a: unknown[]) => lines.push(a.map(String).join('\t'));
      try {
        const { protos } = compileProgram(fixture.ast);
        const constKey = randomBytes(32);
        const opcodeSeed = randomBytes(32);
        const vmSeed = randomBytes(32);
        const { container } = pack(protos, { constKey, opcodeSeed });
        const env = makeInterpreterEnv();
        const loaded = { protos: [] as unknown[] };
        void loaded;
        // M5 reference run (uses its own stdlib env)
        const { unpack } = await import('../../compiler/src/container');
        const lc = unpack(container, { constKey, opcodeSeed });
        runContainer(lc, env);
        // M6 runtime run
        const emit = emitRuntime({ container, opcodeSeed, vmSeed, dispatch: 'tree' });
        const { runLua: rl, luaByteString } = await import('./helpers');
        const out = rl(
          {
            'runtime.lua': emit.lua,
            'main.lua': `local entry = dofile("runtime.lua")
local ok, e1 = pcall(entry, { c = "${luaByteString(constKey)}", s = "x", args = {}, nargs = 0 })
if not ok then error(e1, 0) end`,
          },
          'main.lua',
        );
        expect(out).toBe(lines.map((l) => l).join('\n') + (lines.length ? '\n' : ''));
      } finally {
        console.log = origLog;
      }
    });
  }
});
