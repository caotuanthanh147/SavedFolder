/**
 * AST type module tests.
 *
 * §22.1 note: this module is TYPES ONLY — the outside-source spec is the
 * reference node set (luau-lang/luau Ast.h @ master, fetched 2026-10-10).
 * The tests verify: (1) every kind registry entry is unique and matches the
 * unions (compile-time via `satisfies`), (2) a kitchen-sink fixture exercises
 * EVERY node shape — if a field is missing/wrongly typed the fixture stops
 * compiling, (3) the discriminators classify correctly.
 */
import { describe, expect, test } from 'bun:test';
import {
  EXPR_KINDS, STAT_KINDS, TYPE_KINDS, TYPE_PACK_KINDS,
  isExpr, isStat, isType,
  type Expr, type Stat, type Type, type TypePack, type Local,
} from '../src/ast';
import type { Location } from '../src/tokens';

const loc: Location = { start: { line: 1, column: 0, offset: 0 }, end: { line: 1, column: 1, offset: 1 } };

describe('kind registries', () => {
  test('no duplicate kinds within any registry', () => {
    expect(new Set(EXPR_KINDS).size).toBe(EXPR_KINDS.length);
    expect(new Set(STAT_KINDS).size).toBe(STAT_KINDS.length);
    expect(new Set(TYPE_KINDS).size).toBe(TYPE_KINDS.length);
    expect(new Set(TYPE_PACK_KINDS).size).toBe(TYPE_PACK_KINDS.length);
  });

  test('registries are pairwise disjoint (discriminators unambiguous)', () => {
    for (const k of STAT_KINDS) expect(EXPR_KINDS).not.toContain(k);
    for (const k of STAT_KINDS) expect(TYPE_KINDS).not.toContain(k);
    for (const k of EXPR_KINDS) expect(TYPE_KINDS).not.toContain(k);
    // the LocalStat discriminator is 'Local'; the Local BINDING node kind is
    // also 'Local' but Local is never an Expr/Type, so unions stay disjoint
    expect(STAT_KINDS).toContain('Local');
    expect(EXPR_KINDS).toContain('LocalExpr');
  });
});

describe('kitchen-sink fixture (compile = shape proof)', () => {
  const local = (name: string): Local => ({ kind: 'Local', location: loc, name });

  // one of EVERY expression node
  const exprs: Expr[] = [
    { kind: 'Group', location: loc, expr: { kind: 'Nil', location: loc } },
    { kind: 'Nil', location: loc },
    { kind: 'Bool', location: loc, value: true },
    { kind: 'Number', location: loc, value: 1.5, raw: '1.5' },
    { kind: 'Int', location: loc, value: 42n, raw: '42i' },
    { kind: 'String', location: loc, value: 'hi' },
    {
      kind: 'InterpString', location: loc,
      strings: ['a', 'b', ''],
      expressions: [
        { kind: 'LocalExpr', location: loc, local: local('x') },
        { kind: 'Global', location: loc, name: 'y' },
      ],
    },
    { kind: 'LocalExpr', location: loc, local: local('x') },
    { kind: 'Global', location: loc, name: 'print' },
    { kind: 'Vararg', location: loc },
    {
      kind: 'Call', location: loc,
      func: { kind: 'IndexName', location: loc, expr: { kind: 'Global', location: loc, name: 't' }, index: 'f', op: ':' },
      args: [{ kind: 'Vararg', location: loc }],
      self: true, tableCall: false,
    },
    { kind: 'IndexName', location: loc, expr: { kind: 'Global', location: loc, name: 't' }, index: 'x', op: '.' },
    { kind: 'IndexExpr', location: loc, expr: { kind: 'Global', location: loc, name: 't' }, index: { kind: 'Number', location: loc, value: 1, raw: '1' } },
    {
      kind: 'Function', location: loc,
      attributes: [{ kind: 'Attribute', location: loc, name: 'native' }],
      generics: [{ name: 'T', location: loc }],
      genericPacks: [{ name: 'Rest', location: loc }],
      self: local('self'),
      args: [{ kind: 'Local', location: loc, name: 'a', annotation: { kind: 'TypeReference', location: loc, prefix: null, name: 'number', parameters: null } }],
      vararg: true,
      body: { kind: 'Block', location: loc, body: [] },
      debugname: 'named',
    },
    {
      kind: 'Table', location: loc,
      items: [
        { kind: 'List', key: null, value: { kind: 'Nil', location: loc } },
        { kind: 'Record', key: { kind: 'String', location: loc, value: 'k' }, value: { kind: 'Nil', location: loc } },
        { kind: 'General', key: { kind: 'Number', location: loc, value: 1, raw: '1' }, value: { kind: 'Nil', location: loc } },
      ],
    },
    { kind: 'Unary', location: loc, op: 'Not', expr: { kind: 'Nil', location: loc } },
    { kind: 'Binary', location: loc, op: 'FloorDiv', left: { kind: 'Nil', location: loc }, right: { kind: 'Nil', location: loc } },
    { kind: 'TypeAssertion', location: loc, expr: { kind: 'Global', location: loc, name: 'x' }, annotation: { kind: 'TypeReference', location: loc, prefix: null, name: 'number', parameters: null } },
    { kind: 'IfElse', location: loc, condition: { kind: 'Bool', location: loc, value: true }, trueExpr: { kind: 'Nil', location: loc }, falseExpr: { kind: 'Nil', location: loc } },
    { kind: 'Instantiate', location: loc, expr: { kind: 'Global', location: loc, name: 'f' }, typeArguments: [{ kind: 'TypeReference', location: loc, prefix: null, name: 'T', parameters: null }] },
  ];

  // one of EVERY type node
  const types: Type[] = [
    { kind: 'TypeReference', location: loc, prefix: 'M', name: 'T', parameters: [{ kind: 'TypeReference', location: loc, prefix: null, name: 'U', parameters: null }] },
    { kind: 'TypeTable', location: loc, props: [{ name: 'x', location: loc, type: { kind: 'TypeReference', location: loc, prefix: null, name: 'number', parameters: null } }], indexer: { indexType: { kind: 'TypeReference', location: loc, prefix: null, name: 'string', parameters: null }, resultType: { kind: 'TypeReference', location: loc, prefix: null, name: 'any', parameters: null }, location: loc }, isExact: true },
    { kind: 'FunctionType', location: loc, attributes: [], generics: [], genericPacks: [], argTypes: { types: [], tail: null }, argNames: [{ name: 'a', location: loc }, null], returnTypes: { kind: 'TypePackVariadic', location: loc, type: { kind: 'TypeReference', location: loc, prefix: null, name: 'number', parameters: null } } },
    { kind: 'TypeofType', location: loc, expr: { kind: 'Global', location: loc, name: 'x' } },
    { kind: 'TypeOptional', location: loc, type: { kind: 'TypeReference', location: loc, prefix: null, name: 'number', parameters: null } },
    { kind: 'TypeUnion', location: loc, types: [{ kind: 'TypeReference', location: loc, prefix: null, name: 'a', parameters: null }, { kind: 'TypeSingletonBool', location: loc, value: false }] },
    { kind: 'TypeIntersection', location: loc, types: [{ kind: 'TypeReference', location: loc, prefix: null, name: 'b', parameters: null }] },
    { kind: 'TypeSingletonBool', location: loc, value: true },
    { kind: 'TypeSingletonString', location: loc, value: 'lit' },
    { kind: 'TypeGroup', location: loc, type: { kind: 'TypeReference', location: loc, prefix: null, name: 'c', parameters: null } },
  ];

  // one of EVERY type pack node
  const packs: TypePack[] = [
    { kind: 'TypePackExplicit', location: loc, typeList: { types: [], tail: null } },
    { kind: 'TypePackVariadic', location: loc, type: { kind: 'TypeReference', location: loc, prefix: null, name: 'T', parameters: null } },
    { kind: 'TypePackGeneric', location: loc, name: 'Rest' },
  ];

  // one of EVERY statement node
  const stats: Stat[] = [
    { kind: 'Block', location: loc, body: [] },
    { kind: 'If', location: loc, condition: { kind: 'Nil', location: loc }, thenbody: { kind: 'Block', location: loc, body: [] }, elsebody: null },
    { kind: 'While', location: loc, condition: { kind: 'Nil', location: loc }, body: { kind: 'Block', location: loc, body: [] } },
    { kind: 'Repeat', location: loc, condition: { kind: 'Nil', location: loc }, body: { kind: 'Block', location: loc, body: [] } },
    { kind: 'Break', location: loc },
    { kind: 'Continue', location: loc },
    { kind: 'Return', location: loc, list: [] },
    { kind: 'ExprStat', location: loc, expr: exprs[10]! },
    { kind: 'Local', location: loc, vars: [local('v')], values: [] },
    { kind: 'For', location: loc, var: local('i'), from: { kind: 'Number', location: loc, value: 1, raw: '1' }, to: { kind: 'Number', location: loc, value: 2, raw: '2' }, step: null, body: { kind: 'Block', location: loc, body: [] } },
    { kind: 'ForIn', location: loc, vars: [local('k')], values: [{ kind: 'Global', location: loc, name: 'pairs' }], body: { kind: 'Block', location: loc, body: [] } },
    { kind: 'Assign', location: loc, vars: [{ kind: 'Global', location: loc, name: 'x' }], values: [{ kind: 'Nil', location: loc }] },
    { kind: 'CompoundAssign', location: loc, op: 'Add', var: { kind: 'Global', location: loc, name: 'x' }, value: { kind: 'Number', location: loc, value: 1, raw: '1' } },
    { kind: 'FunctionStat', location: loc, name: { kind: 'IndexName', location: loc, expr: { kind: 'Global', location: loc, name: 'a' }, index: 'f', op: '.' }, func: exprs[13] as Extract<Expr, { kind: 'Function' }> },
    { kind: 'LocalFunction', location: loc, name: local('g'), func: exprs[13] as Extract<Expr, { kind: 'Function' }> },
    { kind: 'TypeAlias', location: loc, name: 'X', nameLocation: loc, generics: [], genericPacks: [], type: types[0]!, exported: true },
    { kind: 'TypeFunction', location: loc, name: 'F', nameLocation: loc, body: exprs[13] as Extract<Expr, { kind: 'Function' }>, exported: false },
  ];

  test('fixture sizes match the registries', () => {
    expect(exprs).toHaveLength(EXPR_KINDS.length);
    expect(stats).toHaveLength(STAT_KINDS.length);
    expect(types).toHaveLength(TYPE_KINDS.length);
    expect(packs).toHaveLength(TYPE_PACK_KINDS.length);
  });

  test('discriminators classify every fixture node', () => {
    for (const e of exprs) expect(isExpr(e)).toBe(true);
    for (const s of stats) expect(isStat(s)).toBe(true);
    for (const t of types) expect(isType(t)).toBe(true);
    for (const e of exprs) expect(isStat(e) || isType(e)).toBe(false);
    for (const s of stats) expect(isExpr(s) || isType(s)).toBe(false);
    for (const t of types) expect(isExpr(t) || isStat(t)).toBe(false);
  });

  test('fixture kinds are exactly the registries (order-insensitive)', () => {
    expect([...exprs.map((e) => e.kind)].sort()).toEqual([...EXPR_KINDS].sort());
    expect([...stats.map((s) => s.kind)].sort()).toEqual([...STAT_KINDS].sort());
    expect([...types.map((t) => t.kind)].sort()).toEqual([...TYPE_KINDS].sort());
    expect([...packs.map((p) => p.kind)].sort()).toEqual([...TYPE_PACK_KINDS].sort());
  });

  test('InterpString invariant: strings = expressions + 1 [Ast.h contract]', () => {
    const interp = exprs.find((e) => e.kind === 'InterpString') as Extract<Expr, { kind: 'InterpString' }>;
    expect(interp.strings.length).toBe(interp.expressions.length + 1);
  });
});
