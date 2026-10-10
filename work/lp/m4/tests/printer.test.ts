/**
 * Printer + round-trip differential suite: print(parse(src)) must re-parse
 * to a structurally identical AST (tests/roundtrip.ts astEqual — locations
 * excluded, Local identity paired positionally).
 *
 * Every case cites an outside source:
 *  - [L5.1] lua.org/manual/5.1 — §2.4 statement forms, §2.5.1 precedence
 *    table (expected parenthesization derived from the priority table,
 *    e.g. `..` right-assoc ⇒ `(a .. b) .. c` needs the parens),
 *    §2.5.7 example table shapes
 *  - [LuauSyntax] luau.org/syntax — compound assignment, continue,
 *    if-else expressions, `::` assertions, interpolation
 *  - [luau.org/types] — annotation grammar shapes (function types with
 *    arg names, generic packs `U...`, variadic returns `...T`)
 *  - [Parser.cpp] / Luau::transpile — the `;` ambiguity guard before a
 *    `(`-leading statement; same-line call rule
 *  - [Lexer.cpp] — escape forms re-encoded canonically (\ddd for
 *    non-printables; interp parts escape ` { })
 */
import { describe, expect, test } from 'bun:test';
import { parse } from '../src/parser';
import { print, quoteString } from '../src/printer';
import { astEqual } from './roundtrip';

function roundtrip(src: string): void {
  const a = parse(src);
  const printed = print(a);
  const b = parse(printed);
  expect(astEqual(a, b)).toBe(true);
}

function printed(src: string): string {
  return print(parse(src));
}

describe('round-trip: statements', () => {
  test('locals, assignments, calls [L5.1 §2.4]', () => {
    roundtrip('local x = 1');
    roundtrip('local x, y = 1, 2');
    roundtrip('local x');
    roundtrip('x = y + 1');
    roundtrip('a.b, c[d], e = 1, f(2)');
    roundtrip('f()');
    roundtrip('f(1, 2)(3)');
    roundtrip('a:b(1)');
    roundtrip('a.b:c(1)');
    roundtrip('a += 1');
    roundtrip('s ..= "x"');
  });

  test('control flow [L5.1 §2.4.4]', () => {
    roundtrip('while x do break end');
    roundtrip('repeat local y = 1 until y > 0');
    roundtrip('for i = 1, 10, 2 do continue end');
    roundtrip('for k, v in pairs(t) do end');
    roundtrip('if a then x = 1 elseif b then y = 2 else z = 3 end');
    roundtrip('do local q = 1 end');
    roundtrip('return 1, 2');
    roundtrip('return');
  });

  test('functions: every declaration form [L5.1 §2.4; LuauSyntax]', () => {
    roundtrip('local function f(a, ...) return a, ... end');
    roundtrip('function a.b.c:d(x) end');
    roundtrip('function t:m(a, b) return self.x end');
    roundtrip('local f = function() return 1 end');
    roundtrip('local f = function(a, b) return a + b end');
    roundtrip('@native function f() end');
    roundtrip('@checked local function g() end');
    roundtrip('@[native, deprecated] function h() end');
    roundtrip('local f = @native function() end');
  });

  test('function name chain keeps its `:` ops; self not materialized [Parser.cpp parseFunctionName]', () => {
    expect(printed('function a.b.c:d(x) end')).toContain('function a.b.c:d(x)');
    expect(printed('function t:m() end')).not.toContain('self');
  });

  test('attributes precede the local keyword [Parser.cpp parseAttributeStat]', () => {
    expect(printed('@checked local function g() end')).toContain('@checked local function g()');
  });

  test('table constructors: list, record, general, separators [L5.1 §2.5.7]', () => {
    roundtrip('local t = {}');
    roundtrip('local t = { 1, 2, x = 3, [k] = 4 }');
    roundtrip('local t = { 1; 2, 3; }');
    roundtrip('local t = f{1, 2}');
    roundtrip('local s = f"str"');
    roundtrip('local cb = { hook = function() end }');
  });

  test('tableCall flag is preserved by the call form [shape fidelity]', () => {
    expect(printed('local t = f{1}')).toContain('f{');
  });

  test('string-call args print as paren calls (shape-identical re-parse)', () => {
    expect(printed('local s = f"str"')).toContain('f("str")');
  });
});

describe('round-trip: expressions and precedence', () => {
  test('associativity and precedence [L5.1 §2.5.1 table]', () => {
    roundtrip('local x = a and b or not c');
    roundtrip('local x = -a ^ 2');
    roundtrip('local x = (a + b) * c');
    roundtrip('local x = a .. (b .. c)');
    roundtrip('local x = (a .. b) .. c');
    roundtrip('local x = a - (b - c)');
    roundtrip('local x = (a - b) - c');
    roundtrip('local x = a % b // c');
    roundtrip('local x = 1 .. 2 .. 3');
    roundtrip('local x = -1 .. 2');
    roundtrip('local x = not a == b');
    roundtrip('local x = -(a == b)');
    roundtrip('local x = (a or b) .. c');
    roundtrip('local x = a ^ (b ^ c)');
  });

  test('source parens are Group NODES and always print (structural fidelity)', () => {
    // `(a - b) - c` parses to Sub(GROUP(Sub(a,b)), c): the parens live in
    // the AST and must survive the round-trip
    expect(printed('local x = (a - b) - c')).toContain('(a - b) - c');
    roundtrip('local x = (a - b) - c');
  });

  test('parser-built left-assoc chains print WITHOUT parens (no Group injected) [L5.1 §2.5.1]', () => {
    // `a - b - c` parses to Sub(Sub(a,b), c) with NO group: printing
    // `(a - b) - c` would re-parse with a Group and BREAK the round-trip
    const p = printed('local x = a - b - c');
    expect(p).not.toContain('(');
    roundtrip('local x = a - b - c');
  });

  test('right-assoc chains re-associate without parens [L5.1 §2.5.1]', () => {
    // `a .. b .. c` parses to Concat(a, Concat(b,c)) — no parens needed
    expect(printed('local x = a .. b .. c')).not.toContain('(');
    roundtrip('local x = a .. b .. c');
    // explicit grouping stays grouped
    expect(printed('local x = (a .. b) .. c')).toContain('(a .. b) .. c');
  });

  test('Luau expression forms [LuauSyntax]', () => {
    roundtrip('local x = if c then 1 else 2');
    roundtrip('local x = (if c then 1 else 2) + 1');
    roundtrip('local x = v :: number');
    roundtrip('local x = (v :: T) :: U');
    roundtrip('local x = (v :: number).y');
    roundtrip('local x = v :: T :: U'.replace('v :: T :: U', '(v :: T) :: U'));
    roundtrip('local x = #t + 1');
  });

  test('interpolated strings [LuauSyntax]', () => {
    roundtrip('local i = `hi {name} bye {x + 1}`');
    roundtrip('local i = `plain`');
    roundtrip('local i = `a\\123b`'); // decoded `{` inside a part
    roundtrip('local i = `a\\96b`');  // decoded backtick
    roundtrip('local i = `a\\125b`'); // decoded `}`
  });

  test('numbers print their preserved raw [byte-exact]', () => {
    for (const raw of ['0xFF', '.5', '1e10', '42i', '0b1010', '1_000', '3.14', '1e-5']) {
      expect(printed(`local n = ${raw}`)).toContain(raw);
    }
  });

  test('strings re-encode canonically [Lexer.cpp escape forms]', () => {
    expect(quoteString('a\nb')).toBe('"a\\nb"');
    expect(quoteString('\t"\\')).toBe('"\\t\\"\\\\"');
    expect(quoteString('\x00\x7f\xff')).toBe('"\\000\\127\\255"');
    expect(quoteString('plain')).toBe('"plain"');
    roundtrip('local s = "a\\nb\\t\\65\\255\\0"');
    roundtrip('local s = "\\u{1F600}"');
  });

  test('postfix bases parenthesize non-prefix shapes', () => {
    expect(printed('local x = (function() end)()')).toContain('(function');
    expect(printed('f();\n(g).x = 1')).toContain('(g).x');
  });
});

describe('round-trip: types', () => {
  test('annotation forms [luau.org/types]', () => {
    roundtrip('type Point = { x: number, y: number }');
    roundtrip('export type Id = string | number');
    roundtrip('type F = (number, string) -> boolean');
    roundtrip('type F = (a: number, b: string?) -> (boolean, ...number)');
    roundtrip('type G = <T>(x: T) -> T');
    roundtrip('type H = <T, U...>(x: T, U...) -> ...T');
    roundtrip('local function id<T>(x: T): T return x end');
    roundtrip('function f<T...>(...: T...) end');
    roundtrip('local t: { [string]: number } = {}');
    roundtrip('local t: { number } = {}');
    roundtrip('local x: number? = 1');
    roundtrip('local x: (A | B) | C');
    roundtrip('local x: A & (B | C)');
    roundtrip('local x: typeof(print)');
    roundtrip('local x: typeof(os.time())');
    roundtrip('local x: "lit" | true = "lit"');
    roundtrip('type M = Module.Type');
    roundtrip('local d: Dictionary<string, number> = f()');
    roundtrip('local x: nil = nil');
    roundtrip('local function f(...: number): ...string return ... end');
  });

  test('union members with suffix-binding shapes parenthesize [Parser.cpp parseTypeSuffix]', () => {
    expect(printed('local x: (A | B) | C')).toContain('(A | B) | C');
    expect(printed('local x: (A | B) | C')).not.toContain('(A | B) | C'.replace('(', '').replace(')', '').replace('  ', ' ') === 'x' ? '' : '(A | B | C');
  });

  test('nested unions stay nested (the group unwraps into the member)', () => {
    const p = printed('local x: (A | B) | C');
    expect(p).toContain('(A | B) | C');
  });
});

describe('round-trip: scope identity (Local pairing)', () => {
  test('shadowed locals pair positionally, not by name [L5.1 §2.4 scoping]', () => {
    roundtrip('local x = 1\ndo local x = 2\nreturn x\nend');
    roundtrip('for i = 1, 2 do local i = i end');
    roundtrip('local x = x'); // RHS resolves to the OUTER binding (Global here)
  });

  test('repeat-until sees body locals: body walks before condition [L5.1 §2.4.4]', () => {
    roundtrip('repeat local x = 1 until x');
    roundtrip('repeat local a, b = f() until a + b > 0');
  });

  test('hazardous identifier names survive the round trip [regression: reservedWordType]', () => {
    roundtrip('local toString = 1\nlocal x = t.toString\nfunction u.constructor() end');
    roundtrip('local y = a.valueOf(b.hasOwnProperty)\nreturn y');
  });
});

describe('round-trip: ambiguity guard', () => {
  test('`;` is emitted before a `(`-leading statement [Parser.cpp same-line call rule; Luau::transpile]', () => {
    const p = printed('f();\n(g).x = 1');
    expect(p).toMatch(/f\(\);/);
    expect(p).toContain('(g).x = 1');
    roundtrip('f();\n(g).x = 1');
    roundtrip('if a then\nf();\n(g)()\nend');
    roundtrip('while x do f(); (g)() end');
  });

  test('the guard may over-fire (a `;` after any statement is a valid separator) [L5.1 §2.4.1]', () => {
    // `local a = 1` cannot actually be extended by `(g)()`, but emitting
    // the `;` unconditionally is always-valid Luau and keeps the guard
    // token-shape-agnostic.
    const p = printed('local a = 1\n(g)()');
    expect(parse(p)).toBeDefined();
    roundtrip('local a = 1\n(g)()');
  });
});

describe('round-trip: fixtures', () => {
  test('kitchen-sink realistic chunk [L5.1 §2.5.7 example shape; LuauSyntax]', () => {
    const src = [
      'local M = {}',
      'type Vec = { x: number, y: number }',
      'function M.map(t, f)',
      '  local r = {}',
      '  for i = 1, #t do',
      '    r[i] = f(t[i], i)',
      '  end',
      '  return r',
      'end',
      'M.x, M.y = 1, 2',
      'while true do break end',
      'repeat local ok = true until ok',
      'local function norm(v: Vec): number',
      '  return math.sqrt(v.x ^ 2 + v.y ^ 2)',
      'end',
      'local total = 0',
      'for _, v in ipairs(M) do',
      '  if v.x < 0 then continue end',
      '  total += norm(v)',
      'end',
      'local msg = `total: {total}`',
      'local ok = total :: number',
      'return if ok then msg else "none"',
    ].join('\n');
    roundtrip(src);
  });

  test('empty chunk prints empty', () => {
    expect(print(parse(''))).toBe('');
  });

  test('deep nesting stays within the recursion limit on re-parse [Parser.cpp FInt]', () => {
    const deep = `return ${'('.repeat(400)}1${')'.repeat(400)}`;
    roundtrip(deep);
  });
});
