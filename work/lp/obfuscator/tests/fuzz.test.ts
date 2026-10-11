/**
 * §10.3 fuzz suite (deterministic — fixed seeds; same batch every run).
 *
 * Oracles:
 *  1. Generated-AST round-trip: 300 seeded programs through
 *     parse→print→parse→astEqual. The generator builds parser-legal shapes
 *     only (operand shaping mirrors the parser's precedence + the
 *     IfElse-tail and `<`-after-assertion rules — see fuzz.ts comments).
 *  2. Mutation oracle: token-boundary splices of embedded sources must
 *     either parse or throw LuauSyntaxError — never any other throw
 *     (crash/hang class). Longer soaks: `bun run tests/fuzz.ts 5000`.
 *
 * Citations: doc.md §10.3 (random program generator for the supported
 * subset + differential testing); the round-trip property itself is
 * D-M4-17 (parens are data).
 */
import { describe, expect, test } from 'bun:test';
import { fuzzRoundtrip, fuzzMutations } from './fuzz';

const MUTATION_SOURCES = [
  { file: 'inline-a.lua', src: 'local t = {}\nfor i = 1, 10 do\n  t[i] = i * 2\nend\nreturn t\n' },
  { file: 'inline-b.lua', src: 'local function map(f, xs)\n  local r = {}\n  for i, x in ipairs(xs) do\n    r[i] = f(x)\n  end\n  return r\nend\nreturn map(function(x) return x + 1 end, {1, 2, 3})\n' },
  { file: 'inline-c.lua', src: 'type P = { x: number, y: number }\nlocal function len(p: P): number\n  return (p.x ^ 2 + p.y ^ 2) ^ 0.5\nend\nreturn len({ x = 3, y = 4 })\n' },
  { file: 'inline-d.lua', src: 'local s = "a\\nb\\255"\nlocal i = `n = {#s}`\nif #s > 2 then\n  return i, s .. "!"\nelse\n  return nil\nend\n' },
];

describe('§10.3 fuzzer (deterministic seeds)', () => {
  test('300 generated ASTs round-trip [oracle: parse→print→parse→astEqual]', () => {
    const failures = fuzzRoundtrip(300, 0xC0FFEE);
    for (const f of failures.slice(0, 3)) {
      console.error(`fuzz failure seed=${f.seed}: ${f.error ?? 'MISMATCH'}\n${f.printed.slice(0, 300)}`);
    }
    expect(failures).toEqual([]);
  });

  test('different seed batch also round-trips (seed independence)', () => {
    expect(fuzzRoundtrip(200, 0x5EED)).toEqual([]);
  });

  test('mutation oracle: splices never throw anything but LuauSyntaxError', () => {
    const failures = fuzzMutations(MUTATION_SOURCES, 15, 0xABCD);
    expect(failures).toEqual([]);
  });
});
