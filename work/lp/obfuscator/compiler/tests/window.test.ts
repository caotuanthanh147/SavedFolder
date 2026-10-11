/**
 * Arg-window placement regressions (finding 2026-10-11, glm1 — msg
 * glm1-20261011T0900Z.md): calls compiled BELOW the live frontier
 * (concat-chain operand positions, interp-string expression slots —
 * right-nested concat trees are what the M4 parser produces for
 * `a .. b .. c`) must compile their arguments INTO the CALL's window
 * (base+1..), never at the raw allocation frontier, and the SELF path
 * must put the receiver at base+1 (the register CALL's B window counts
 * as the implicit self argument). The same fix session found a latent
 * compileTable bug: SETLIST stages items at the raw frontier but reads
 * them contiguously at target+1 — table args in window slots broke.
 *
 * Oracle discipline (§22.1): every case's SOURCE runs under real Lua
 * 5.4 (the outside oracle); the SAME source goes through the real M4
 * parser → M5 compile → pack/unpack → reference interpreter. Stdout
 * must match byte-for-byte. The interp-string case cannot run under
 * plain lua5.4 (Luau backtick syntax) — its expected output is stated
 * from the documented lowering (same discipline as the AST-only
 * fixtures in fixtures.ts).
 */
import { describe, expect, test } from 'bun:test';
import { spawnSync } from 'node:child_process';
import { mkdtempSync, writeFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { parse } from '../../src/parser';
import { compileProgram } from '../src/compile';
import { pack, unpack, randomBytes } from '../src/container';
import { runContainer, makeInterpreterEnv, type LuaValue, type HostFunction } from '../src/interpreter';

const LUA54 = process.env.LUA54 ?? join(process.env.HOME ?? '/home/z', '.lua54', 'bin', 'lua5.4');

function runRealLua(source: string): string {
  const dir = mkdtempSync(join(tmpdir(), 'm5-window-'));
  const file = join(dir, 'case.lua');
  // Byte-exact oracle I/O (D-M5-28): raw bytes, latin1 char-per-byte.
  writeFileSync(file, source, 'latin1');
  try {
    const res = spawnSync(LUA54, [file], { encoding: 'buffer', timeout: 10_000 });
    if (res.error) throw res.error;
    if (res.status !== 0) {
      throw new Error(`real lua failed (${res.status}): ${res.stderr}`);
    }
    return (res.stdout as Buffer).toString('latin1');
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
}

function runProtected(source: string): string {
  const lines: string[] = [];
  const { protos } = compileProgram(parse(source));
  const key = randomBytes(32);
  const seed = randomBytes(32);
  const { container } = pack(protos, { constKey: key, opcodeSeed: seed });
  const loaded = unpack(container, { constKey: key, opcodeSeed: seed });
  const env = makeInterpreterEnv();
  const print: HostFunction = (args: readonly LuaValue[]): LuaValue[] => {
    const tostring = env.get('tostring') as HostFunction;
    lines.push(args.map((a) => String(tostring([a])[0])).join('\t'));
    return [];
  };
  env.set('print', print);
  runContainer(loaded, env);
  return lines.join('\n') + (lines.length ? '\n' : '');
}

const CASES: ReadonlyArray<readonly [name: string, source: string]> = [
  ['two calls in concat chain (non-last operands)', `local function g(n) return n + 1 end
print("a" .. g(1) .. "," .. g(2))
`],
  ['C-function calls in concat chain', `print("a" .. string.byte("Lua", 1) .. "," .. string.byte("Lua", 2))
`],
  ['pcall + tostring in concat chain', `local pok, pres = pcall(function() return "R" end)
print("a=" .. tostring(pok) .. " b=" .. pres)
`],
  ['parenthesized calls in concat chain', `local function g(n) return n + 1 end
print("a" .. (g(1)) .. "b" .. (g(2)))
`],
  ['single call, last concat operand', `local function g(n) return n + 1 end
print("a," .. g(1))
`],
  ['calls hoisted to locals', `local function g(n) return n + 1 end
local a = g(1) local b = g(2)
print("a" .. a .. "," .. b)
`],
  ['two method calls in concat chain', `print(("a"):upper() .. "," .. ("b"):upper())
`],
  ['method call non-last + function call last', `local function g(n) return "g" .. n end
print(("a"):upper() .. "-" .. g(1))
`],
  ['method calls WITH args below frontier (self window)', `print("x" .. ("abcd"):sub(2, 3) .. "y" .. ("efgh"):sub(1, 2))
`],
  ['nested-call arg below frontier in concat', `local function g(n) return n + 1 end
local function h(n) return g(n) * 2 end
print("x" .. h(3) .. "y" .. h(4))
`],
  ['multret-last arg below frontier in concat', `local function g() return 7, 8 end
local function h(...) local s = 0 for _, v in ipairs({...}) do s = s + v end return "h" .. s end
print("x" .. h(1, g()) .. "y" .. "z")
`],
  ['multret-last deep below frontier (5-chain)', `local function g() return 7, 8 end
local function h(...) local s = 0 for _, v in ipairs({...}) do s = s + v end return "h" .. s end
print("a" .. h(1, g()) .. "b" .. "c" .. "d")
`],
  ['vararg multret-last below frontier', `local function pack(...) return select("#", ...) end
local function v(...) return "v" .. pack(...) end
local function main(...) print("x" .. v(1, ...) .. "y") end
main(4, 5, 6)
`],
  ['table arg in window slot (SETLIST staging)', `local function tt(t) return t[1] end
print("x" .. tt({"a"}) .. "y" .. "z")
`],
  ['record-item table arg in window slot', `local function tt(t) return t.k end
print("x" .. tt({k = "a"}) .. "y" .. "z")
`],
  ['computed-key table arg in window slot', `local function tt(t) return t[1] end
print("x" .. tt({[1] = "a"}) .. "y" .. "z")
`],
  ['table-call syntax arg in concat chain', `local function tt(t) return t[1] end
print("x" .. tt{"a"} .. "y" .. "z")
`],
  ['method call with table concat arg below frontier', `print("x" .. table.concat({"a","b"}, "-") .. "y" .. ("[%s]"):format("k"))
`],
  ['nested tables inside call args in concat chain', `local function sum(t) local s = 0 for _, v in ipairs(t) do s = s + v end return s end
print("a" .. sum({sum({1, 2}), 5}) .. "b" .. sum({2, 3}))
`],
  ['long concat chain with mixed calls (7 operands)', `local function g(n) return n end
print("1" .. g(2) .. "3" .. ("four"):upper() .. "5" .. tostring(6) .. "7" .. g(8))
`],
  ['call in both concat operand and its own args', `local function g(n) return n + 1 end
print("a" .. g(g(g(1))) .. "b" .. g(g(2)))
`],
];

describe('arg-window placement below the live frontier (parse-based differential)', () => {
  for (const [name, source] of CASES) {
    test(`${name}`, () => {
      const expected = runRealLua(source);
      const actual = runProtected(source);
      expect(actual).toBe(expected);
    });
  }

  test('case count sanity', () => {
    expect(CASES.length).toBeGreaterThanOrEqual(20);
  });
});

describe('interp-string slot windows (Luau syntax — protected-side expectation)', () => {
  // Real lua5.4 cannot parse backtick interp strings; expected output is
  // stated from the documented %* lowering (fixtures.ts discipline).
  test('two calls as interp slots', () => {
    const src = 'local function g(n) return n + 1 end\nprint(\x60a={g(1)},b={g(2)}\x60)\n';
    expect(runProtected(src)).toBe('a=2,b=3\n');
  });

  test('method call with args as interp slot amid concat', () => {
    const src = 'print(\x60x=\x60 .. ("abcd"):sub(2, 3) .. \x60 y=\x60 .. tostring(9))\n';
    expect(runProtected(src)).toBe('x=bc y=9\n');
  });
});
