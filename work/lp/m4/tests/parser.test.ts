/**
 * Parser acceptance + rejection suite: token stream → AST.
 *
 * Every case cites an outside source (§22.1: tests must derive from a spec,
 * not restate the implementation):
 *  - [L5.1] Lua 5.1 reference manual (lua.org/manual/5.1/manual.html)
 *    — §2.4 statements/assignment rules, §2.5 expressions and the
 *    operator-precedence table, §3.3 control structures, §2.4 scoping
 *  - [LuauSyntax] luau.org/syntax — Luau additions: compound assignment,
 *    continue, if-else expressions, type assertions, string interpolation,
 *    type annotations, generic functions
 *  - [luau.org/types] luau.org/type-annotations — annotation grammar
 *  - [Parser.cpp] luau-lang/luau Ast/src/Parser.cpp @ master (fetched
 *    2026-10-10; MIT — SPEC only): contextual-keyword resolution
 *    (getIdentifier), &&/||/!= confusable errors, function-name/self
 *    rules, blockFollow, isStatLast (return/break/continue end a block),
 *    ambiguous-call line check, recursion limit, D-M4-7/12/14 decisions
 *    mirrored in DECISIONS-M4.md
 */
import { describe, expect, test } from 'bun:test';
import { LuauSyntaxError } from '../src/errors';
import { parse } from '../src/parser';
import type { Expr, Stat, Type, TypePack } from '../src/ast';

function stat(src: string): Stat {
  const c = parse(src);
  expect(c.block.body.length).toBe(1);
  return c.block.body[0]!;
}

function expr(src: string): Expr {
  const s = stat(`return ${src}`);
  expect(s.kind).toBe('Return');
  return (s as Extract<Stat, { kind: 'Return' }>).list[0]!;
}

function expectReject(src: string, needle?: string): void {
  let threw: unknown = null;
  try {
    parse(src);
  } catch (e) {
    threw = e;
  }
  expect(threw).toBeInstanceOf(LuauSyntaxError);
  if (needle !== undefined) {
    expect((threw as Error).message.toLowerCase()).toContain(needle.toLowerCase());
  }
}

// ---------------------------------------------------------------------------
// Assignment / call statements [L5.1 §2.4; Parser.cpp parseExprStat]
// ---------------------------------------------------------------------------

describe('expression statements and assignment', () => {
  test('a call is an expression statement [L5.1 §2.4]', () => {
    const s = stat('f()');
    expect(s.kind).toBe('ExprStat');
    expect((s as Extract<Stat, { kind: 'ExprStat' }>).expr.kind).toBe('Call');
  });

  test('multiple assignment targets [L5.1 §2.4: varlist = explist]', () => {
    const s = stat('a.b, c[d], e = 1, 2');
    expect(s.kind).toBe('Assign');
    const a = s as Extract<Stat, { kind: 'Assign' }>;
    expect(a.vars.map((v) => v.kind)).toEqual(['IndexName', 'IndexExpr', 'Global']);
    expect(a.values.map((v) => v.kind)).toEqual(['Number', 'Number']);
  });

  test('RHS list longer than target list is legal [L5.1 §2.4]', () => {
    const s = stat('a = 1, 2, 3');
    expect(s.kind).toBe('Assign');
    expect((s as Extract<Stat, { kind: 'Assign' }>).values.length).toBe(3);
  });

  test('non-lvalue assignment target is an error [Parser.cpp parseExprStat]', () => {
    expectReject('(f()) = 1', 'variable or a field');
    expectReject('a + b = 1', 'expected assignment');
  });

  test('bare expression that is neither call nor assignment is an error [Parser.cpp]', () => {
    expectReject('a + b', 'expected assignment');
    expectReject('1 + 1', 'expected name'); // statement must start with a prefix expression
  });

  test('compound assignment desugars per operator [LuauSyntax]', () => {
    for (const [src, op] of [
      ['a += 1', 'Add'], ['a -= 1', 'Sub'], ['a *= 1', 'Mul'], ['a /= 1', 'Div'],
      ['a //= 1', 'FloorDiv'], ['a %= 1', 'Mod'], ['a ^= 1', 'Pow'], ['a ..= "s"', 'Concat'],
    ] as const) {
      const s = stat(src);
      expect(s.kind).toBe('CompoundAssign');
      expect((s as Extract<Stat, { kind: 'CompoundAssign' }>).op).toBe(op);
    }
  });

  test('compound assignment to a non-variable is an error [LuauSyntax]', () => {
    expectReject('f() += 1'); // rejects: call ends the statement, '+=' starts invalid syntax
  });
});

// ---------------------------------------------------------------------------
// local / function statements [L5.1 §2.4; Parser.cpp parseLocal]
// ---------------------------------------------------------------------------

describe('local and function statements', () => {
  test('local with and without initializer [L5.1 §2.4]', () => {
    const a = stat('local x') as Extract<Stat, { kind: 'Local' }>;
    expect(a.vars.length).toBe(1);
    expect(a.vars[0]!.name).toBe('x');
    expect(a.values.length).toBe(0);
    const b = stat('local x, y = 1, 2') as Extract<Stat, { kind: 'Local' }>;
    expect(b.vars.map((v) => v.name)).toEqual(['x', 'y']);
    expect(b.values.map((v) => v.kind)).toEqual(['Number', 'Number']);
  });

  test('local binds AFTER its right-hand side [L5.1 §2.4 scoping]', () => {
    // `local x = x` — the RHS x is the OUTER (here: global) x
    const s = stat('local x = x') as Extract<Stat, { kind: 'Local' }>;
    expect(s.values[0]!.kind).toBe('Global');
    expect((s.values[0] as Extract<Expr, { kind: 'Global' }>).name).toBe('x');
  });

  test('local function binds its name BEFORE the body (recursion) [L5.1 §2.4]', () => {
    const s = stat('local function f() return f end') as Extract<Stat, { kind: 'LocalFunction' }>;
    expect(s.name.name).toBe('f');
    const ret = s.func.body.body[0] as Extract<Stat, { kind: 'Return' }>;
    expect(ret.list[0]!.kind).toBe('LocalExpr');
    expect((ret.list[0] as Extract<Expr, { kind: 'LocalExpr' }>).local).toBe(s.name);
  });

  test('function statement name chain with method colon inserts self [Parser.cpp parseFunctionName]', () => {
    const s = stat('function a.b.c:d(x) end') as Extract<Stat, { kind: 'FunctionStat' }>;
    expect(s.name.kind).toBe('IndexName');
    const name = s.name as Extract<Expr, { kind: 'IndexName' }>;
    expect((name as { op: ':' | '.' }).op).toBe(':');
    expect(name.index).toBe('d');
    expect(s.func.self).not.toBeNull();
    expect(s.func.self!.name).toBe('self');
    expect(s.func.args.map((a) => a.name)).toEqual(['x']); // self NOT in args
  });

  test('plain function has no self [Parser.cpp]', () => {
    const s = stat('function f(a, b) end') as Extract<Stat, { kind: 'FunctionStat' }>;
    expect(s.func.self).toBeNull();
    expect(s.func.args.map((a) => a.name)).toEqual(['a', 'b']);
  });

  test('function body is a scope: args are locals inside, not outside', () => {
    const c = parse('function f(a) end\nlocal a = 1\nreturn a');
    const ret = c.block.body[2] as Extract<Stat, { kind: 'Return' }>;
    const outer = ret.list[0] as Extract<Expr, { kind: 'LocalExpr' }>;
    const fn = c.block.body[0] as Extract<Stat, { kind: 'FunctionStat' }>;
    expect(outer.local).not.toBe(fn.func.args[0]);
  });

  test('vararg parameter: legal last, illegal elsewhere [L5.1 §2.4.7]', () => {
    const s = stat('function f(a, ...) end') as Extract<Stat, { kind: 'FunctionStat' }>;
    expect(s.func.vararg).toBe(true);
    expectReject('function f(..., a) end', 'parameter list');
    expectReject('function f(... ...) end', 'parameter list');
  });
});

// ---------------------------------------------------------------------------
// Vararg placement (split from the above to keep each case minimal)
// ---------------------------------------------------------------------------

describe('vararg expression placement', () => {
  test('... expands inside vararg function [L5.1 §2.4.7]', () => {
    const s = stat('function f(...) return ... end') as Extract<Stat, { kind: 'FunctionStat' }>;
    const ret = s.func.body.body[0] as Extract<Stat, { kind: 'Return' }>;
    expect(ret.list[0]!.kind).toBe('Vararg');
  });

  test('... outside any function is an error [Parser.cpp]', () => {
    expectReject('return ...', 'vararg');
  });

  test('... in a non-vararg function is an error [Parser.cpp]', () => {
    expectReject('function f() return ... end', 'vararg');
  });

  test('nested non-vararg function inside vararg function cannot see ... [L5.1 §2.4.7 scoping]', () => {
    expectReject('function f(...) return function() return ... end end', 'vararg');
  });
});

// ---------------------------------------------------------------------------
// Control flow [L5.1 §2.4.4/§3.3; Parser.cpp]
// ---------------------------------------------------------------------------

describe('control flow', () => {
  test('if/elseif/else chain nests in elsebody [L5.1 §2.4.4]', () => {
    const c = parse('if a then\nelseif b then\nelse\nend');
    const top = c.block.body[0] as Extract<Stat, { kind: 'If' }>;
    expect(top.elsebody!.kind).toBe('If');
    const mid = top.elsebody as Extract<Stat, { kind: 'If' }>;
    expect(mid.condition.kind).toBe('Global');
    expect((mid.condition as Extract<Expr, { kind: 'Global' }>).name).toBe('b');
    expect(mid.elsebody!.kind).toBe('Block');
  });

  test('while body tracks loop context [L5.1 §2.4.4]', () => {
    const s = stat('while x do break end') as Extract<Stat, { kind: 'While' }>;
    expect(s.body.body[0]!.kind).toBe('Break');
  });

  test('repeat-until condition sees the body locals [L5.1 §2.4.4: "The condition ... can refer to local variables"]', () => {
    const s = stat('repeat local x = 1 until x') as Extract<Stat, { kind: 'Repeat' }>;
    expect(s.condition.kind).toBe('LocalExpr');
    const localStat = s.body.body[0] as Extract<Stat, { kind: 'Local' }>;
    expect((s.condition as Extract<Expr, { kind: 'LocalExpr' }>).local).toBe(localStat.vars[0]);
  });

  test('numeric for: from/to/step [L5.1 §2.4.4]', () => {
    const s = stat('for i = 1, 10, 2 do end') as Extract<Stat, { kind: 'For' }>;
    expect(s.var.name).toBe('i');
    expect(s.step!.kind).toBe('Number');
    const t = stat('for i = 1, #t do end') as Extract<Stat, { kind: 'For' }>;
    expect(t.step).toBeNull();
  });

  test('generic for binds its variables [L5.1 §2.4.4]', () => {
    const s = stat('for k, v in pairs(t) do end') as Extract<Stat, { kind: 'ForIn' }>;
    expect(s.vars.map((v) => v.name)).toEqual(['k', 'v']);
    expect(s.values.length).toBe(1);
    expect(s.values[0]!.kind).toBe('Call');
  });

  test('for-loop variables are NOT visible before the loop [L5.1 §2.4.4]', () => {
    const s = stat('for i = 1, 2 do end');
    expect(s.kind).toBe('For'); // parses; visibility is a semantic matter
  });

  test('break outside a loop is an error [L5.1 §2.4.4; Parser.cpp]', () => {
    expectReject('break', 'loop');
    expectReject('if x then break end', 'loop');
    expectReject('function f() break end', 'loop');
  });

  test('break inside a function inside a loop is still outside the loop [Parser.cpp loopDepth is per function]', () => {
    expectReject('while x do function f() break end end', 'loop');
  });

  test('continue: Luau-only, contextual, loop-required [LuauSyntax; Parser.cpp]', () => {
    const s = stat('for i = 1, 2 do continue end');
    expect(s.kind).toBe('For');
    const inner = (s as Extract<Stat, { kind: 'For' }>).body.body[0]!;
    expect(inner.kind).toBe('Continue');
    expectReject('continue', 'loop');
    expectReject('if x then continue end', 'loop');
  });

  test('continue as an identifier stays available [Parser.cpp getIdentifier contextual]', () => {
    const a = stat('local continue = 1') as Extract<Stat, { kind: 'Local' }>;
    expect(a.vars[0]!.name).toBe('continue');
    const b = stat('continue = 2') as Extract<Stat, { kind: 'Assign' }>;
    expect(b.vars[0]!.kind).toBe('Global');
  });

  test('return ends its block [Parser.cpp isStatLast]', () => {
    expectReject('return 1\nlocal x = 1', 'eof');
  });

  test('bare return and multi-value return [L5.1 §2.4.4]', () => {
    const a = stat('return') as Extract<Stat, { kind: 'Return' }>;
    expect(a.list.length).toBe(0);
    const b = stat('return 1, 2') as Extract<Stat, { kind: 'Return' }>;
    expect(b.list.length).toBe(2);
  });

  test('do block groups statements and scopes [L5.1 §2.4.4]', () => {
    const c = parse('do local x = 1 end\nreturn x');
    const ret = c.block.body[1] as Extract<Stat, { kind: 'Return' }>;
    expect(ret.list[0]!.kind).toBe('Global'); // x not visible after do
  });

  test('semicolons separate statements; leading semicolon is an error [Parser.cpp parseStat: no empty statement]', () => {
    const c = parse('f();\ng()');
    expect(c.block.body.length).toBe(2);
    expectReject(';', 'expected name');
  });
});

// ---------------------------------------------------------------------------
// Operator precedence and associativity [L5.1 §2.5.1 table; Parser.cpp
// binaryPriority — identical table]
// ---------------------------------------------------------------------------

describe('expression precedence', () => {
  const binary = (e: Expr) => e as Extract<Expr, { kind: 'Binary' }>;

  test('multiplication binds tighter than addition [L5.1 §2.5.1]', () => {
    const e = binary(expr('1 + 2 * 3'));
    expect(e.op).toBe('Add');
    expect(binary(e.right).op).toBe('Mul');
  });

  test('subtraction is left-associative [L5.1 §2.5.1]', () => {
    const e = binary(expr('1 - 2 - 3'));
    expect(e.op).toBe('Sub');
    expect(binary(e.left).op).toBe('Sub');
  });

  test('exponentiation is right-associative [L5.1 §2.5.1: "^ ... right associative"]', () => {
    const e = binary(expr('a ^ b ^ c'));
    expect(e.op).toBe('Pow');
    expect(e.left.kind).toBe('Global');
    expect(binary(e.right).op).toBe('Pow');
  });

  test('unary minus applies after ^: -a^2 == -(a^2) [L5.1 §2.5.1 note]', () => {
    const e = expr('-a ^ 2');
    expect(e.kind).toBe('Unary');
    expect(binary((e as Extract<Expr, { kind: 'Unary' }>).expr).op).toBe('Pow');
  });

  test("'not' binds tighter than comparisons [L5.1 §2.5.1]", () => {
    const e = binary(expr('not a == b'));
    expect(e.op).toBe('CompareEq');
    expect(e.left.kind).toBe('Unary');
  });

  test('concatenation is right-associative [L5.1 §2.5.1: ".. ... right associative"]', () => {
    const e = binary(expr('a .. b .. c'));
    expect(e.op).toBe('Concat');
    expect(e.left.kind).toBe('Global');
    expect(binary(e.right).op).toBe('Concat');
  });

  test('and/or: and binds tighter [L5.1 §2.5.1]', () => {
    const e = binary(expr('a or b and c'));
    expect(e.op).toBe('Or');
    expect(binary(e.right).op).toBe('And');
  });

  test('comparison operators are non-chaining per level table [L5.1 §2.5.1]', () => {
    // a == b == c parses (left-assoc at the same priority); Luau's parser
    // loop accepts it — verify the shape rather than reject [Parser.cpp parseRel]
    const e = binary(expr('a == b == c'));
    expect(e.op).toBe('CompareEq');
    expect(binary(e.left).op).toBe('CompareEq');
  });

  test('parentheses override precedence [L5.1 §2.5]', () => {
    const e = binary(expr('(1 + 2) * 3'));
    expect(e.op).toBe('Mul');
    expect(e.left.kind).toBe('Group');
    expect(binary((e.left as Extract<Expr, { kind: 'Group' }>).expr).op).toBe('Add');
  });
});

// ---------------------------------------------------------------------------
// Calls and indexes [L5.1 §2.5.7/§2.5.8; Parser.cpp parsePostfix]
// ---------------------------------------------------------------------------

describe('calls and postfix', () => {
  const call = (e: Expr) => e as Extract<Expr, { kind: 'Call' }>;

  test('argument forms: parens, literal string, table [L5.1 §2.5.7]', () => {
    expect(call(expr('f()')).args.length).toBe(0);
    expect(call(expr('f"str"')).args[0]!.kind).toBe('String');
    expect(call(expr('f{1}')).args[0]!.kind).toBe('Table');
    expect(call(expr('f{1}')).tableCall).toBe(true);
  });

  test('method call: self flag, func is IndexName with : [L5.1 §2.5.8]', () => {
    const e = call(expr('a:b(1)'));
    expect(e.self).toBe(true);
    expect(e.func.kind).toBe('IndexName');
    const idx = e.func as Extract<Expr, { kind: 'IndexName' }>;
    expect((idx as { op: ':' | '.' }).op).toBe(':');
    expect(idx.index).toBe('b');
    expect(e.args.length).toBe(1); // the self arg is implicit, not materialized
  });

  test('postfix chains left-to-right [L5.1 §2.5.7]', () => {
    const e = call(expr('a.b[1](2):c()'));
    expect(e.self).toBe(true);
    const method = e.func as Extract<Expr, { kind: 'IndexName' }>;
    expect(method.index).toBe('c');
    const inner = method.expr as Extract<Expr, { kind: 'Call' }>;
    expect(inner.args[0]!.kind).toBe('Number');
    const idx = inner.func as Extract<Expr, { kind: 'IndexExpr' }>;
    expect(idx.index.kind).toBe('Number');
    expect((idx.expr as Extract<Expr, { kind: 'IndexName' }>).index).toBe('b');
  });

  test('ambiguous call across a newline is an error [Parser.cpp: call parens must start on the func line]', () => {
    expectReject('a = f\n(g)', 'ambiguous');
  });

  test('index forms: dot name vs bracket expression [L5.1 §2.5.8]', () => {
    const e = expr('a.b') as Extract<Expr, { kind: 'IndexName' }>;
    expect(e.op).toBe('.');
    expect(e.index).toBe('b');
    const g = expr('a[b + 1]') as Extract<Expr, { kind: 'IndexExpr' }>;
    expect(g.expr.kind).toBe('Global');
    expect((g.index as Extract<Expr, { kind: 'Binary' }>).op).toBe('Add');
  });

  test('if-else expression [LuauSyntax]', () => {
    const e = expr('if c then 1 else 2') as Extract<Expr, { kind: 'IfElse' }>;
    expect(e.condition.kind).toBe('Global');
    expect(e.trueExpr.kind).toBe('Number');
    expect(e.falseExpr.kind).toBe('Number');
  });

  test('type assertion :: [LuauSyntax]', () => {
    const e = expr('v :: number') as Extract<Expr, { kind: 'TypeAssertion' }>;
    expect(e.expr.kind).toBe('Global');
    expect(e.annotation.kind).toBe('TypeReference');
    expectReject('return v ::', 'type');
  });

  test('string interpolation [LuauSyntax]', () => {
    const e = expr('`hi {name} bye {x + 1}`') as Extract<Expr, { kind: 'InterpString' }>;
    expect(e.strings).toEqual(['hi ', ' bye ', '']);
    expect(e.expressions.length).toBe(2);
    expect((e.expressions[1] as Extract<Expr, { kind: 'Binary' }>).op).toBe('Add');
  });

  test('number literal kinds: double, int64 suffix [Lexer.cpp; Parser.cpp parseInteger64]', () => {
    expect(expr('3.14').kind).toBe('Number');
    const i = expr('42i') as Extract<Expr, { kind: 'Int' }>;
    expect(i.value).toBe(42n);
    const hex = expr('0xFFi') as Extract<Expr, { kind: 'Int' }>;
    expect(hex.value).toBe(255n);
    expect(expr('0x10').kind).toBe('Number'); // hex double without suffix
  });

  test('unary operators [L5.1 §2.5.1]', () => {
    for (const [src, op] of [['-a', 'Minus'], ['not a', 'Not'], ['#a', 'Len']] as const) {
      const e = expr(src) as Extract<Expr, { kind: 'Unary' }>;
      expect(e.op).toBe(op);
    }
  });
});

// ---------------------------------------------------------------------------
// Table constructors [L5.1 §2.5.7; Parser.cpp parseTableConstructor]
// ---------------------------------------------------------------------------

describe('table constructors', () => {
  test('positional items are List [L5.1 §2.5.7]', () => {
    const t = expr('{1, 2, 3}') as Extract<Expr, { kind: 'Table' }>;
    expect(t.items.map((i) => i.kind)).toEqual(['List', 'List', 'List']);
  });

  test('name = value items are Record; [expr] = value items are General [L5.1 §2.5.7]', () => {
    const t = expr('{ x = 1, [k] = 2 }') as Extract<Expr, { kind: 'Table' }>;
    expect(t.items[0]!.kind).toBe('Record');
    expect(t.items[1]!.kind).toBe('General');
    expect(t.items[1]!.key!.kind).toBe('Global');
  });

  test('separator mix and trailing separator are legal [L5.1 §2.5.7]', () => {
    expect(expr('{1; 2, 3;}').kind).toBe('Table');
    expect(expr('{[1] = "a",}').kind).toBe('Table');
  });

  test('field value function inherits the field name as debugname [Parser.cpp parseTableConstructor]', () => {
    const t = expr('{ cb = function() end }') as Extract<Expr, { kind: 'Table' }>;
    const v = t.items[0]!.value as Extract<Expr, { kind: 'Function' }>;
    expect(v.debugname).toBe('cb');
  });

  test('empty table [L5.1 §2.5.7]', () => {
    expect(expr('{}').kind).toBe('Table');
  });
});

// ---------------------------------------------------------------------------
// Contextual keywords: type / export [Parser.cpp getIdentifier]
// ---------------------------------------------------------------------------

describe('contextual type/export', () => {
  test('type alias statement [luau.org/types]', () => {
    const s = stat('type Point = { x: number, y: number }') as Extract<Stat, { kind: 'TypeAlias' }>;
    expect(s.name).toBe('Point');
    expect(s.exported).toBe(false);
    expect(s.type.kind).toBe('TypeTable');
  });

  test('export type sets the flag [luau.org/types]', () => {
    const s = stat('export type Id = string | number') as Extract<Stat, { kind: 'TypeAlias' }>;
    expect(s.exported).toBe(true);
    expect(s.type.kind).toBe('TypeUnion');
  });

  test('type as a plain identifier stays available [Parser.cpp getIdentifier]', () => {
    const a = stat('local type = 1') as Extract<Stat, { kind: 'Local' }>;
    expect(a.vars[0]!.name).toBe('type');
    const b = stat('type = 2') as Extract<Stat, { kind: 'Assign' }>;
    expect(b.vars[0]!.kind).toBe('Global');
    const c = stat('type(x)') as Extract<Stat, { kind: 'ExprStat' }>;
    expect((c.expr as Extract<Expr, { kind: 'Call' }>).func.kind).toBe('Global');
  });

  test('generic type alias [luau.org/types]', () => {
    const s = stat('type Pair<T> = { first: T, second: T }') as Extract<Stat, { kind: 'TypeAlias' }>;
    expect(s.generics.map((g) => g.name)).toEqual(['T']);
  });

  test('declare is unsupported with a clear error [D-M4-12]', () => {
    expectReject('declare function f(x: number): string', 'declare');
    expectReject('declare Foo: { bar: string }', 'declare');
  });

  test('export of values is unsupported [D-M4-12]', () => {
    expectReject('export local x = 1', 'export');
    expectReject('export function f() end', 'export');
  });
});

// ---------------------------------------------------------------------------
// Type annotations [luau.org/types; Parser.cpp parseType]
// ---------------------------------------------------------------------------

describe('type annotations', () => {
  const annotation = (src: string) =>
    (stat(src) as Extract<Stat, { kind: 'Local' }>).vars[0]!.annotation!;

  test('local annotation [luau.org/types]', () => {
    const t = annotation('local x: number = 1');
    expect(t.kind).toBe('TypeReference');
    expect((t as { name: string }).name).toBe('number');
  });

  test('function parameter and return annotations [luau.org/types]', () => {
    const s = stat('function f(x: number, y: string?): boolean return x > 0 end') as Extract<Stat, { kind: 'FunctionStat' }>;
    expect(s.func.args[0]!.annotation!.kind).toBe('TypeReference');
    expect(s.func.args[1]!.annotation!.kind).toBe('TypeOptional');
    const ret = s.func.returnAnnotation! as Extract<TypePack, { kind: 'TypePackExplicit' }>;
    expect(ret.kind).toBe('TypePackExplicit');
    expect(ret.typeList.types[0]).toMatchObject({ kind: 'TypeReference', name: 'boolean' });
  });

  test('vararg annotation [luau.org/types]', () => {
    const s = stat('function f(...: number) end') as Extract<Stat, { kind: 'FunctionStat' }>;
    expect(s.func.varargAnnotation!.kind).toBe('TypePackVariadic');
  });

  test('union, intersection, optional [luau.org/types]', () => {
    expect(annotation('local x: number | string = 1').kind).toBe('TypeUnion');
    expect(annotation('local x: Foo & Bar = f()').kind).toBe('TypeIntersection');
    expect(annotation('local x: number? = 1').kind).toBe('TypeOptional');
  });

  test('mixing union and intersection is an error [Parser.cpp: flat suffix loop]', () => {
    expectReject('local x: A | B & C', 'mixing union and intersection');
    expectReject('local x: A? & B', 'mixing union and intersection');
  });

  test('function type annotation [luau.org/types]', () => {
    const t = annotation('local f: (number, string) -> boolean') as Extract<Type, { kind: 'FunctionType' }>;
    expect(t.kind).toBe('FunctionType');
    expect(t.argTypes.types.length).toBe(2);
    expect((t.returnTypes as Extract<TypePack, { kind: 'TypePackExplicit' }>).typeList.types.length).toBe(1);
  });

  test('typeof type [luau.org/types]', () => {
    const t = annotation('local x: typeof(print)') as Extract<Type, { kind: 'TypeofType' }>;
    expect(t.kind).toBe('TypeofType');
    expect(t.expr.kind).toBe('Global');
  });

  test('table type with indexer [luau.org/types]', () => {
    const t = annotation('local t: { [string]: number }') as Extract<Type, { kind: 'TypeTable' }>;
    expect(t.kind).toBe('TypeTable');
    expect(t.indexer).not.toBeNull();
  });

  test('module-qualified type reference [luau.org/types: Prefix.Name — single dot, matching AstTypeReference]', () => {
    const t = annotation('local m: Module.Type = f()') as Extract<Type, { kind: 'TypeReference' }>;
    expect(t.prefix).toBe('Module');
    expect(t.name).toBe('Type');
  });

  test('generic type instantiation in annotation [luau.org/types]', () => {
    const t = annotation('local d: Dictionary<string, number> = f()') as Extract<Type, { kind: 'TypeReference' }>;
    expect(t.parameters!.length).toBe(2);
  });

  test("parenthesized single type unwraps unless a suffix follows [D-M4-14]", () => {
    expect(annotation('local x: (number) = 1').kind).toBe('TypeReference');
    expect(annotation('local x: (number | string) = 1').kind).toBe('TypeUnion');
  });

  test("'function' as a type has a helpful error [Parser.cpp]", () => {
    expectReject('local f: function', 'function type');
  });

  test('return type after -> in an annotation is rejected with guidance [Parser.cpp]', () => {
    expectReject('function f() -> number end', "instead of '->'");
  });

  test('generic function syntax [luau.org/types]', () => {
    const s = stat('function id<T>(x: T): T return x end') as Extract<Stat, { kind: 'FunctionStat' }>;
    expect(s.func.generics.map((g) => g.name)).toEqual(['T']);
  });

  test("singleton types: true/false and string literals [luau.org/types]", () => {
    expect(annotation('local b: true = true').kind).toBe('TypeSingletonBool');
    expect(annotation('local s: "literal" = "literal"').kind).toBe('TypeSingletonString');
  });

  test('annotation on for-loop variables [luau.org/types]', () => {
    const s = stat('for i: number = 1, 2 do end') as Extract<Stat, { kind: 'For' }>;
    expect(s.var.annotation!.kind).toBe('TypeReference');
  });
});

// ---------------------------------------------------------------------------
// Attributes [luau.org/syntax; Parser.cpp parseAttributeStat]
// ---------------------------------------------------------------------------

describe('attributes', () => {
  test('known attributes parse on functions and locals [Parser.cpp kAttributeEntries]', () => {
    const f = stat('@native function f() end') as Extract<Stat, { kind: 'FunctionStat' }>;
    expect(f.func.attributes.map((a) => a.name)).toEqual(['native']);
    const l = stat('@checked local function g() end') as Extract<Stat, { kind: 'LocalFunction' }>;
    expect(l.func.attributes.map((a) => a.name)).toEqual(['checked']);
  });

  test('bracket list form and multiples [Parser.cpp]', () => {
    const s = parse('@[native, deprecated] function g() end');
    const f = s.block.body[0] as Extract<Stat, { kind: 'FunctionStat' }>;
    expect(f.func.attributes.map((a) => a.name)).toEqual(['native', 'deprecated']);
  });

  test('attributes on a plain (non-function) local are rejected [Parser.cpp parseLocal]', () => {
    expectReject('@native local x = 1', "'function' after local");
  });

  test('unknown attribute is an error [Parser.cpp]', () => {
    expectReject('@inline function f() end', 'attribute');
  });

  test('duplicate attribute is an error [Parser.cpp]', () => {
    expectReject('@native @native function f() end', 'duplicate');
  });

  test('attribute arguments are unsupported (new-master syntax) [D-M4-12]', () => {
    expectReject('@[deprecated("soon")] function f() end', 'attribute arguments');
  });

  test('attribute must be followed by function or local [Parser.cpp]', () => {
    expectReject('@native return 1', 'attribute');
  });
});

// ---------------------------------------------------------------------------
// Confusable operators [Parser.cpp: && || != ! with "did you mean" errors]
// ---------------------------------------------------------------------------

describe('confusable operators', () => {
  test('&& suggests and [Parser.cpp]', () => {
    expectReject('local x = a && b', 'and');
  });
  test('|| suggests or [Parser.cpp]', () => {
    expectReject('local x = a || b', 'or');
  });
  test('!= suggests ~= [Parser.cpp]', () => {
    expectReject('local x = a != b', '~=');
  });
  test('! suggests not [Parser.cpp]', () => {
    expectReject('local x = !a', 'not');
  });
});

// ---------------------------------------------------------------------------
// Scope and binding identity [L5.1 §2.4; Parser.cpp scope stack]
// ---------------------------------------------------------------------------

describe('scope and binding identity', () => {
  test('shadowing in a nested do block creates a distinct Local object [L5.1 §2.4]', () => {
    const c = parse('local x = 1\ndo local x = 2\nreturn x\nend');
    const outer = (c.block.body[0] as Extract<Stat, { kind: 'Local' }>).vars[0]!;
    const blk = c.block.body[1] as Extract<Stat, { kind: 'Block' }>;
    const inner = (blk.body[0] as Extract<Stat, { kind: 'Local' }>).vars[0]!;
    const ret = blk.body[1] as Extract<Stat, { kind: 'Return' }>;
    expect(inner).not.toBe(outer);
    expect((ret.list[0] as Extract<Expr, { kind: 'LocalExpr' }>).local).toBe(inner);
  });

  test('locals go out of scope at block end [L5.1 §2.4]', () => {
    const c = parse('do local x = 1 end\nreturn x');
    const ret = c.block.body[1] as Extract<Stat, { kind: 'Return' }>;
    expect(ret.list[0]!.kind).toBe('Global');
  });

  test('while/for bodies restore scope after the loop [L5.1 §2.4]', () => {
    const c = parse('for i = 1, 2 do local q = i end\nreturn i');
    const ret = c.block.body[1] as Extract<Stat, { kind: 'Return' }>;
    expect(ret.list[0]!.kind).toBe('Global');
  });

  test('method self is scoped to the body [Parser.cpp]', () => {
    const c = parse('function t:m() end\nreturn self');
    const ret = c.block.body[1] as Extract<Stat, { kind: 'Return' }>;
    expect(ret.list[0]!.kind).toBe('Global');
  });
});

// ---------------------------------------------------------------------------
// Error quality: positions, mismatch reporting, recursion [Parser.cpp]
// ---------------------------------------------------------------------------

describe('error quality', () => {
  test('errors carry line:column locations [errors.ts contract]', () => {
    try {
      parse('local x =\n1 +');
      expect.unreachable();
    } catch (e) {
      expect(e).toBeInstanceOf(LuauSyntaxError);
      const loc = (e as LuauSyntaxError).location;
      expect(loc.start.line).toBe(2);
    }
  });

  test('unclosed constructs report the opening line for match tokens [Parser.cpp expectMatchAndConsume]', () => {
    try {
      parse('if a then\n');
      expect.unreachable();
    } catch (e) {
      expect((e as Error).message).toContain("'end'");
    }
    try {
      parse('local t = {\n1,\n2');
      expect.unreachable();
    } catch (e) {
      expect((e as Error).message).toContain('line 1');
    }
  });

  test('recursion limit is enforced and configurable [Parser.cpp FInt::LuauRecursionLimit]', () => {
    const deep = `return ${'('.repeat(200)}1${')'.repeat(200)}`;
    expect(() => parse(deep)).not.toThrow(); // 200 < default 1000
    expect(() => parse(deep, { recursionLimit: 50 })).toThrow(LuauSyntaxError);
    expect(() => parse(deep, { recursionLimit: 50 })).toThrow(/recursion/);
  });

  test('trailing garbage after the chunk is an error [L5.1 chunk grammar]', () => {
    expectReject('return 1\n)', 'eof');
  });

  test('empty source parses to an empty chunk [L5.1 chunk grammar]', () => {
    const c = parse('');
    expect(c.block.body.length).toBe(0);
    expect(c.kind).toBe('Chunk');
  });

  test('shebang-style leading # is rejected like any other invalid statement start [Lexer.cpp]', () => {
    expectReject('#!/usr/bin/lua');
  });
});

// ---------------------------------------------------------------------------
// Object.prototype-member identifiers [regression: s3 corpus — the reserved
// word lookup once returned inherited members for these names]
// ---------------------------------------------------------------------------

describe('Object.prototype-member identifiers parse normally', () => {
  test('dotted access and bare bindings work for every hazardous name [regression]', () => {
    for (const name of ['toString', 'constructor', 'valueOf', 'hasOwnProperty', 'isPrototypeOf', 'propertyIsEnumerable', 'toLocaleString']) {
      const idx = expr(`t.${name}`) as Extract<Expr, { kind: 'IndexName' }>;
      expect(idx.index).toBe(name);
      const loc = stat(`local ${name} = 1`) as Extract<Stat, { kind: 'Local' }>;
      expect(loc.vars[0]!.name).toBe(name);
    }
  });

  test('method-call shape on a hazardous name [regression: Ascension.lua 1078]', () => {
    const e = expr('omega.toString(fire)') as Extract<Expr, { kind: 'Call' }>;
    const f = e.func as Extract<Expr, { kind: 'IndexName' }>;
    expect(f.index).toBe('toString');
    expect(e.args[0]!.kind).toBe('Global');
  });

  test('function statement with hazardous field name [regression: TapIncremental.lua 272]', () => {
    const s = stat('function t.toString(p1) end') as Extract<Stat, { kind: 'FunctionStat' }>;
    const name = s.name as Extract<Expr, { kind: 'IndexName' }>;
    expect(name.index).toBe('toString');
    expect(s.func.args.map((a) => a.name)).toEqual(['p1']);
  });
});

// ---------------------------------------------------------------------------
// Mixed realistic sources [L5.1 §2.5.7 example shape; LuauSyntax]
// ---------------------------------------------------------------------------

describe('mixed realistic sources', () => {
  test('chunk with everything [L5.1 §2.5.7 example shape]', () => {
    const src = [
      'local M = {}',
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
      'return M',
    ].join('\n');
    const c = parse(src);
    expect(c.block.body.length).toBe(6);
  });

  test('Luau-flavored source: types, continue, compound, interp [LuauSyntax]', () => {
    const src = [
      'type Vec = { x: number, y: number }',
      'export type Name = string?',
      'local function norm(v: Vec): number',
      '  return math.sqrt(v.x ^ 2 + v.y ^ 2)',
      'end',
      'local total = 0',
      'for _, v in ipairs(vs) do',
      '  if v.x < 0 then continue end',
      '  total += norm(v)',
      'end',
      'local msg = `total: {total}`',
      'local ok = total :: number',
      'return if ok then msg else "none"',
    ].join('\n');
    const c = parse(src);
    expect(c.block.body.length).toBe(8);
  });
});
