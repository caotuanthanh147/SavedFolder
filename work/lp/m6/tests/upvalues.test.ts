/**
 * Upvalue cell-sharing regressions (D-M6-14). Found 2026-10-12 through
 * the standalone obfuscate CLI demo: sibling closures capturing the SAME
 * parent register each got their OWN cell (NEWCLOSURE created one per
 * capture), so the frame's RETURN closed them into divergent snapshots —
 * the writer's updates were invisible to the reader (peek stayed at the
 * capture-time value). PUC findupval semantics: one shared cell per
 * (frame, register); the fix adds the fr.uv reg->cell cache with CLOSEUP
 * invalidation (register recycling after a scope close must open a fresh
 * cell — the stale-closed guard covers a defensive hit).
 *
 * Each case is parsed with the REAL M4 parser (integration shape), then
 * packed + emitted for every dispatch strategy and run under real
 * lua5.4.7 against the source oracle — byte-for-byte, per
 * differential.test.ts discipline. The sibling case also runs
 * containerless (entry b) — the deployment shape must share the fix.
 *
 * Sources deliberately avoid 2+ CALLS inside one concat chain (the open
 * M5 compileCall arg-window finding, msg'd to glm6 — fixtures must stay
 * green independent of that fix).
 */

import { describe, expect, test } from 'bun:test';
import { parse } from '../../src/parser';
import { compileProgram } from '../../compiler/src/compile';
import { pack } from '../../compiler/src/container';
import { emitRuntime } from '../src/emit';
import type { DispatchKind } from '../src/dispatch';
import { runLua, luaByteString } from './helpers';

const STRATEGIES: ReadonlyArray<{ dispatch?: DispatchKind; runtimeBuilt?: boolean }> = [
  { dispatch: 'chain' },
  { dispatch: 'tree' },
  { dispatch: 'closure', runtimeBuilt: false },
  { dispatch: 'closure', runtimeBuilt: true },
];

interface Built {
  readonly lua: string;
  readonly container: Uint8Array;
  readonly constKey: Uint8Array;
}

function build(source: string, opts: { dispatch?: DispatchKind; runtimeBuilt?: boolean }, vmSeed: Uint8Array): Built {
  const chunk = parse(source);
  const { protos } = compileProgram(chunk);
  const constKey = new Uint8Array(32).fill(7);
  const opcodeSeed = new Uint8Array(32).fill(11);
  const { container } = pack(protos, { constKey, opcodeSeed });
  const emit = emitRuntime({ container, opcodeSeed, vmSeed, dispatch: opts.dispatch, runtimeBuilt: opts.runtimeBuilt });
  return { lua: emit.lua, container, constKey };
}

function buildContainerless(source: string, opts: { dispatch?: DispatchKind; runtimeBuilt?: boolean }, vmSeed: Uint8Array): Built {
  const chunk = parse(source);
  const { protos } = compileProgram(chunk);
  const constKey = new Uint8Array(32).fill(7);
  const opcodeSeed = new Uint8Array(32).fill(11);
  const { container } = pack(protos, { constKey, opcodeSeed });
  const emit = emitRuntime({ container: null, opcodeSeed, vmSeed, dispatch: opts.dispatch, runtimeBuilt: opts.runtimeBuilt });
  return { lua: emit.lua, container, constKey };
}

const vmSeed = new Uint8Array(32).fill(3);

function runEmbedded(b: Built): string {
  const main = `local entry = dofile("runtime.lua")
local ok, e1 = pcall(entry, { c = "${luaByteString(b.constKey)}", s = "\\1\\2\\3\\4", args = {}, nargs = 0 })
if not ok then error(e1, 0) end`;
  return runLua({ 'runtime.lua': b.lua, 'main.lua': main }, 'main.lua');
}

function runContainerless(b: Built): string {
  const main = `local entry = dofile("runtime.lua")
local ok, e1 = pcall(entry, { c = "${luaByteString(b.constKey)}", s = "\\1\\2\\3\\4", b = "${luaByteString(b.container)}", args = {}, nargs = 0 })
if not ok then error(e1, 0) end`;
  return runLua({ 'runtime.lua': b.lua, 'main.lua': main }, 'main.lua');
}

describe('upvalue cell sharing (D-M6-14 regression) — real parser, all strategies', () => {
  test('siblings sharing one parent register survive the frame return', () => {
    const source = `local function mk()
  local n = 0
  local function inc()
    n = n + 1
    return n
  end
  local function peek()
    return n
  end
  return inc, peek
end
local inc, peek = mk()
inc()
inc()
print(peek())
inc()
print(peek())
print(inc())
`;
    const expected = runLua({ 'src.lua': source }, 'src.lua');
    expect(expected).toBe('2\n3\n4\n');
    for (const strat of STRATEGIES) {
      expect(runEmbedded(build(source, strat, vmSeed))).toBe(expected);
    }
    for (const strat of STRATEGIES) {
      expect(runContainerless(buildContainerless(source, strat, vmSeed))).toBe(expected);
    }
  });

  test('scope-close register recycling: a recycled reg index opens a fresh cell', () => {
    const source = `local fs = {}
do
  local x = "first"
  fs[1] = function() return x end
end
do
  local x = "second"
  fs[2] = function() return x end
end
print(fs[1]())
print(fs[2]())
`;
    const expected = runLua({ 'src.lua': source }, 'src.lua');
    expect(expected).toBe('first\nsecond\n');
    for (const strat of STRATEGIES) {
      expect(runEmbedded(build(source, strat, vmSeed))).toBe(expected);
    }
  });

  test('open-frame writes visible to a sibling created after the writes', () => {
    const source = `local function f()
  local n = 0
  local function inc2()
    n = n + 2
  end
  inc2()
  inc2()
  local function get2()
    return n
  end
  return get2
end
print(f()())
`;
    const expected = runLua({ 'src.lua': source }, 'src.lua');
    expect(expected).toBe('4\n');
    for (const strat of STRATEGIES) {
      expect(runEmbedded(build(source, strat, vmSeed))).toBe(expected);
    }
  });

  test('kd==2 passthrough: cousins through a middle closure share the grandparent cell', () => {
    const source = `local function outer()
  local count = 0
  local function middle()
    local function bump()
      count = count + 1
    end
    local function readc()
      return count
    end
    return bump, readc
  end
  return middle
end
local bump, readc = outer()()
bump()
bump()
bump()
print(readc())
`;
    const expected = runLua({ 'src.lua': source }, 'src.lua');
    expect(expected).toBe('3\n');
    for (const strat of STRATEGIES) {
      expect(runEmbedded(build(source, strat, vmSeed))).toBe(expected);
    }
  });
});
