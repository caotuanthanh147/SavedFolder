/**
 * Differential fixtures: (source, AST) pairs in the Lua 5.1∩Luau∩5.4-safe
 * subset. The SOURCE runs under real Lua 5.4 (outside oracle, §22.1); the
 * AST runs through compile→pack→unpack→reference interpreter.
 *
 * Fixture discipline (RESEARCH-M5 "Differential oracle"):
 * - printed floats avoid the 5.4-integer/float vs Luau-single-double format
 *   split (no raw `/` results that are whole floats, no math.floor of such);
 *   `//`, integer arithmetic, and non-whole floats print identically;
 * - error() fixtures use level 0 (containers carry no debug info, D-M5-11);
 * - Luau-only syntax (continue, compound assign, interp strings, if-exprs,
 *   generalized iteration) appears ONLY in the AST; the source uses the
 *   documented 5.4 equivalent (goto continue, x = x op y, string.format
 *   with %s/%d, explicit if, pairs());
 * - pairs() fixtures use array-only tables (or single hash keys) so the
 *   iteration order is identical in both engines.
 */

import type {
  BinaryOp, Block, CallExpr, Chunk, Expr, ExprStat, ForInStat, ForStat,
  IfElseExpr, IfStat, IndexExpr, IndexNameExpr, InterpStringExpr, Local,
  LocalFunctionStat, LocalStat, RepeatStat, ReturnStat, Stat, TableExpr,
  TableItem, UnaryOp, VarargExpr, WhileStat,
} from '../../src/ast';

const L = { start: { line: 1, column: 0, offset: 0 }, end: { line: 1, column: 1, offset: 1 } };

// --- builders (Local identity is shared explicitly) ------------------------

export const num = (value: number): Expr => ({ kind: 'Number', value, raw: String(value), location: L });
export const str = (value: string): Expr => ({ kind: 'String', value, location: L });
const nilE = (): Expr => ({ kind: 'Nil', location: L });
const boolE = (value: boolean): Expr => ({ kind: 'Bool', value, location: L });
const varargE = (): VarargExpr => ({ kind: 'Vararg', location: L });
export const localE = (l: Local): Expr => ({ kind: 'LocalExpr', local: l, location: L });
export const glob = (name: string): Expr => ({ kind: 'Global', name, location: L });
const group = (expr: Expr): Expr => ({ kind: 'Group', expr, location: L });
export const call = (func: Expr, args: readonly Expr[]): CallExpr => ({
  kind: 'Call', func, args, self: false, tableCall: false, location: L,
});
const mcall = (recv: Expr, name: string, args: readonly Expr[]): CallExpr => ({
  kind: 'Call', func: idx(recv, name, ':'), args, self: true, tableCall: false, location: L,
});
const idx = (expr: Expr, index: string, op: '.' | ':' = '.'): IndexNameExpr => ({
  kind: 'IndexName', expr, index, op, location: L,
});
const idxe = (expr: Expr, index: Expr): IndexExpr => ({
  kind: 'IndexExpr', expr, index, location: L,
});
const bin = (op: BinaryOp, left: Expr, right: Expr): Expr => ({
  kind: 'Binary', op, left, right, location: L,
});
const un = (op: UnaryOp, expr: Expr): Expr => ({ kind: 'Unary', op, expr, location: L });
const interp = (strings: readonly string[], expressions: readonly Expr[]): InterpStringExpr => ({
  kind: 'InterpString', strings, expressions, location: L,
});
const ifElseE = (condition: Expr, trueExpr: Expr, falseExpr: Expr): IfElseExpr => ({
  kind: 'IfElse', condition, trueExpr, falseExpr, location: L,
});

/** Fresh Local binding (identity significant — never share between sites). */
export const local_ = (name: string): Local => ({ kind: 'Local', name, location: L });

const block = (...body: readonly Stat[]): Block => ({ kind: 'Block', body, location: L });
export const chunk = (...body: readonly Stat[]): Chunk => ({ kind: 'Chunk', block: block(...body), location: L });
export const ret = (...list: readonly Expr[]): ReturnStat => ({ kind: 'Return', list, location: L });
export const exprStat = (expr: Expr): ExprStat => ({ kind: 'ExprStat', expr, location: L });
const breakS = (): Stat => ({ kind: 'Break', location: L });
const continueS = (): Stat => ({ kind: 'Continue', location: L });

export const localStat = (vars: readonly Local[], values: readonly Expr[]): LocalStat => ({
  kind: 'Local', vars, values, location: L,
});

export const localFn = (
  fnLocal: Local, args: readonly Local[], body: readonly Stat[], vararg = false,
): LocalFunctionStat => ({
  kind: 'LocalFunction',
  name: fnLocal,
  func: {
    kind: 'Function',
    attributes: [], generics: [], genericPacks: [],
    self: null, args, vararg, body: block(...body),
    debugname: fnLocal.name, location: L,
  },
  location: L,
});

const fnE = (args: readonly Local[], body: readonly Stat[], vararg = false): Expr => ({
  kind: 'Function',
  attributes: [], generics: [], genericPacks: [],
  self: null, args, vararg, body: block(...body),
  debugname: null, location: L,
});

/** function Target.name(args) body end  (FunctionStat on an IndexName). */
const fnStat = (
  target: IndexNameExpr,
  args: readonly Local[],
  body: readonly Stat[],
  selfParam: Local | null = null,
): Stat => ({
  kind: 'FunctionStat',
  name: target,
  func: {
    kind: 'Function',
    attributes: [], generics: [], genericPacks: [],
    self: selfParam, args, vararg: false,
    body: block(...body), debugname: null, location: L,
  },
  location: L,
});

const ifS = (condition: Expr, thenbody: readonly Stat[], elsebody?: readonly Stat[]): IfStat => ({
  kind: 'If', condition, thenbody: block(...thenbody),
  elsebody: elsebody ? block(...elsebody) : null, location: L,
});

const whileS = (condition: Expr, body: readonly Stat[]): WhileStat => ({
  kind: 'While', condition, body: block(...body), location: L,
});

const repeatS = (condition: Expr, body: readonly Stat[]): RepeatStat => ({
  kind: 'Repeat', condition, body: block(...body), location: L,
});

const forS = (loopVar: Local, from: Expr, to: Expr, step: Expr | null, body: readonly Stat[]): ForStat => ({
  kind: 'For', var: loopVar, from, to, step, body: block(...body), location: L,
});

const forIn = (vars: readonly Local[], values: readonly Expr[], body: readonly Stat[]): ForInStat => ({
  kind: 'ForIn', vars, values, body: block(...body), location: L,
});

const assignS = (targets: readonly Expr[], values: readonly Expr[]): Stat => ({
  kind: 'Assign', vars: targets, values, location: L,
});

const compoundS = (op: BinaryOp, target: Expr, value: Expr): Stat => ({
  kind: 'CompoundAssign', op, var: target, value, location: L,
});

const listItem = (value: Expr): TableItem => ({ kind: 'List', key: null, value });
const recItem = (key: string, value: Expr): TableItem => ({
  kind: 'Record', key: str(key), value,
});
const genItem = (key: Expr, value: Expr): TableItem => ({ kind: 'General', key, value });
const tableE = (items: readonly TableItem[]): TableExpr => ({ kind: 'Table', items, location: L });

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

export interface Fixture {
  readonly name: string;
  readonly source: string;
  readonly ast: Chunk;
}


export const FIXTURES: readonly Fixture[] = [
  {
    name: 'arith-integer',
    source: `print(1 + 2 * 3, (1 + 2) * 3)
print(2 ^ 0.5 * 10, 7 // 2, 7 % 3, -7 // 2)
print(10 // -3, 2 ^ 0.5)
print(1 - 2 - 3, -(2 + 3), 10 % 3.25)
`,
    ast: chunk(
      exprStat(call(glob('print'), [bin('Add', num(1), bin('Mul', num(2), num(3))), bin('Mul', bin('Add', num(1), num(2)), num(3))])),
      exprStat(call(glob('print'), [bin('Mul', bin('Pow', num(2), num(0.5)), num(10)), bin('FloorDiv', num(7), num(2)), bin('Mod', num(7), num(3)), bin('FloorDiv', un('Minus', num(7)), num(2))])),
      exprStat(call(glob('print'), [bin('FloorDiv', num(10), un('Minus', num(3))), bin('Pow', num(2), num(0.5))])),
      exprStat(call(glob('print'), [bin('Sub', bin('Sub', num(1), num(2)), num(3)), un('Minus', bin('Add', num(2), num(3))), bin('Mod', num(10), num(3.25))])),
    ),
  },
  {
    name: 'strings',
    source: `local s = "hello" .. " " .. "world"
print(s, #s, s:upper(), s:sub(1, 5))
print(string.rep("ab", 3), ("x"):len())
print(string.format("%d %s %5d|%-5d|%.2f %x %%", 42, "ok", 7, 7, 3.14159, 255))
`,
    ast: (() => {
      const s = local_('s');
      return chunk(
        localStat([s], [bin('Concat', str('hello'), bin('Concat', str(' '), str('world')))]),
        exprStat(call(glob('print'), [
          localE(s), un('Len', localE(s)),
          mcall(localE(s), 'upper', []), mcall(localE(s), 'sub', [num(1), num(5)]),
        ])),
        exprStat(call(glob('print'), [
          call(idx(glob('string'), 'rep'), [str('ab'), num(3)]),
          mcall(group(str('x')), 'len', []),
        ])),
        exprStat(call(glob('print'), [
          call(idx(glob('string'), 'format'), [
            str('%d %s %5d|%-5d|%.2f %x %%'), num(42), str('ok'), num(7), num(7), num(3.14159), num(255),
          ]),
        ])),
      );
    })(),
  },
  {
    name: 'oop-metatables',
    source: `local Point = {}
Point.__index = Point
function Point.new(x, y)
  return setmetatable({x = x, y = y}, Point)
end
function Point:area()
  return self.x * self.y
end
function Point:__tostring()
  return "Point(" .. self.x .. "," .. self.y .. ")"
end
local p = Point.new(3, 4)
print(p:area())
print(tostring(p))
local q = setmetatable({}, {__index = function(t, k) return k .. "!" end})
print(q.hello, q.world)
`,
    ast: (() => {
      const Point = local_('Point');
      const x = local_('x');
      const y = local_('y');
      const p = local_('p');
      const q = local_('q');
      const t = local_('t');
      const k = local_('k');
      const selfArea = local_('self');
      const selfStr = local_('self');
      return chunk(
        localStat([Point], [tableE([])]),
        assignS([idx(localE(Point), '__index')], [localE(Point)]),
        fnStat(idx(localE(Point), 'new'), [x, y], [
          ret(call(glob('setmetatable'), [tableE([recItem('x', localE(x)), recItem('y', localE(y))]), localE(Point)])),
        ]),
        fnStat(idx(localE(Point), 'area'), [], [ret(bin('Mul', idx(localE(selfArea), 'x'), idx(localE(selfArea), 'y')))], selfArea),
        fnStat(idx(localE(Point), '__tostring'), [], [
          ret(bin('Concat', bin('Concat', bin('Concat', bin('Concat', str('Point('), idx(localE(selfStr), 'x')), str(',')), idx(localE(selfStr), 'y')), str(')'))),
        ], selfStr),
        localStat([p], [call(idx(localE(Point), 'new'), [num(3), num(4)])]),
        exprStat(call(glob('print'), [mcall(localE(p), 'area', [])])),
        exprStat(call(glob('print'), [call(glob('tostring'), [localE(p)])])),
        localStat([q], [call(glob('setmetatable'), [tableE([]), tableE([recItem('__index', fnE([t, k], [ret(bin('Concat', localE(k), str('!')))]))])])]),
        exprStat(call(glob('print'), [idx(localE(q), 'hello'), idx(localE(q), 'world')])),
      );
    })(),
  },
  {
    name: 'closures-upvalues',
    source: `local function counter()
  local n = 0
  return function()
    n = n + 1
    return n
  end
end
local c = counter()
print(c(), c(), c())
local fs = {}
for i = 1, 3 do
  fs[i] = function() return i end
end
print(fs[1](), fs[2](), fs[3]())
local base = 10
local function outer()
  local mid = 5
  return function()
    return base + mid
  end
end
print(outer()())
`,
    ast: (() => {
      const counter = local_('counter');
      const c = local_('c');
      const fs = local_('fs');
      const iv = local_('i');
      const base = local_('base');
      const outer = local_('outer');
      const n = local_('n');
      const mid = local_('mid');
      return chunk(
        localFn(counter, [], [
          localStat([n], [num(0)]),
          ret(fnE([], [
            assignS([localE(n)], [bin('Add', localE(n), num(1))]),
            ret(localE(n)),
          ])),
        ]),
        localStat([c], [call(localE(counter), [])]),
        exprStat(call(glob('print'), [call(localE(c), []), call(localE(c), []), call(localE(c), [])])),
        localStat([fs], [tableE([])]),
        forS(iv, num(1), num(3), null, [
          assignS([idxe(localE(fs), localE(iv))], [fnE([], [ret(localE(iv))])]),
        ]),
        exprStat(call(glob('print'), [
          call(idxe(localE(fs), num(1)), []), call(idxe(localE(fs), num(2)), []), call(idxe(localE(fs), num(3)), []),
        ])),
        localStat([base], [num(10)]),
        localFn(outer, [], [
          localStat([mid], [num(5)]),
          ret(fnE([], [ret(bin('Add', localE(base), localE(mid)))])),
        ]),
        exprStat(call(glob('print'), [call(call(localE(outer), []), [])])),
      );
    })(),
  },
  {
    name: 'varargs',
    source: `local function f(...)
  local n = select("#", ...)
  print(n, ...)
  return ...
end
local a, b, c = f(1, 2, 3)
print(a, b, c)
local function g(x, ...)
  print(x, select("#", ...))
  return x * 2, ...
end
local r1, r2, r3 = g(5, 6, 7)
print(r1, r2, r3)
print(f("tail"))
`,
    ast: (() => {
      const f = local_('f');
      const g = local_('g');
      const a = local_('a');
      const b = local_('b');
      const c = local_('c');
      const n = local_('n');
      const x = local_('x');
      const r1 = local_('r1');
      const r2 = local_('r2');
      const r3 = local_('r3');
      return chunk(
        localFn(f, [], [
          localStat([n], [call(glob('select'), [str('#'), varargE()])]),
          exprStat(call(glob('print'), [localE(n), varargE()])),
          ret(varargE()),
        ], true),
        localStat([a, b, c], [call(localE(f), [num(1), num(2), num(3)])]),
        exprStat(call(glob('print'), [localE(a), localE(b), localE(c)])),
        localFn(g, [x], [
          exprStat(call(glob('print'), [localE(x), call(glob('select'), [str('#'), varargE()])])),
          ret(bin('Mul', localE(x), num(2)), varargE()),
        ], true),
        localStat([r1, r2, r3], [call(localE(g), [num(5), num(6), num(7)])]),
        exprStat(call(glob('print'), [localE(r1), localE(r2), localE(r3)])),
        exprStat(call(glob('print'), [call(localE(f), [str('tail')])])),
      );
    })(),
  },
  {
    name: 'numeric-for',
    source: `for i = 1, 10, 2 do print("a", i) end
for i = 10, 1, -3 do print("b", i) end
for i = 0.3, 1.5, 0.3 do print("c", i) end
for i = 3, 1 do print("never") end
for i = 5, 5 do print("once", i) end
`,
    ast: (() => {
      const i1 = local_('i');
      const i2 = local_('i');
      const i3 = local_('i');
      const i4 = local_('i');
      const i5 = local_('i');
      return chunk(
        forS(i1, num(1), num(10), num(2), [exprStat(call(glob('print'), [str('a'), localE(i1)]))]),
        forS(i2, num(10), num(1), un('Minus', num(3)), [exprStat(call(glob('print'), [str('b'), localE(i2)]))]),
        forS(i3, num(0.3), num(1.5), num(0.3), [exprStat(call(glob('print'), [str('c'), localE(i3)]))]),
        forS(i4, num(3), num(1), null, [exprStat(call(glob('print'), [str('never')]))]),
        forS(i5, num(5), num(5), null, [exprStat(call(glob('print'), [str('once'), localE(i5)]))]),
      );
    })(),
  },
  {
    name: 'generic-for',
    source: `local t = {10, 20, 30}
for i, v in ipairs(t) do print("ip", i, v) end
for i, v in pairs(t) do print("p", i, v) end
local sum = 0
for i, v in pairs(t) do sum = sum + v end
print(sum)
local single = {only = 1}
for k, v in pairs(single) do print(k, v) end
`,
    ast: (() => {
      const t = local_('t');
      const sum = local_('sum');
      const single = local_('single');
      const i1 = local_('i');
      const v1 = local_('v');
      const i2 = local_('i');
      const v2 = local_('v');
      const i3 = local_('i');
      const v3 = local_('v');
      const k4 = local_('k');
      const v4 = local_('v');
      return chunk(
        localStat([t], [tableE([listItem(num(10)), listItem(num(20)), listItem(num(30))])]),
        forIn([i1, v1], [call(glob('ipairs'), [localE(t)])], [exprStat(call(glob('print'), [str('ip'), localE(i1), localE(v1)]))]),
        // generalized iteration: AST iterates the table directly (Luau);
        // the 5.4 source uses pairs() — documented equivalence.
        forIn([i2, v2], [localE(t)], [exprStat(call(glob('print'), [str('p'), localE(i2), localE(v2)]))]),
        localStat([sum], [num(0)]),
        forIn([i3, v3], [localE(t)], [assignS([localE(sum)], [bin('Add', localE(sum), localE(v3))])]),
        exprStat(call(glob('print'), [localE(sum)])),
        localStat([single], [tableE([recItem('only', num(1))])]),
        forIn([k4, v4], [localE(single)], [exprStat(call(glob('print'), [localE(k4), localE(v4)]))]),
      );
    })(),
  },
  {
    name: 'multret',
    source: `local function f() return 1, 2, 3 end
print(f())
print((f()))
local a, b, c = f()
print(a, b, c)
local t = {f()}
print(#t, t[1], t[3])
local t2 = {0, f()}
print(#t2, t2[1], t2[2])
local x, y = 10, f()
print(x, y)
`,
    ast: (() => {
      const f = local_('f');
      const a = local_('a');
      const b = local_('b');
      const c = local_('c');
      const t = local_('t');
      const t2 = local_('t2');
      const x = local_('x');
      const y = local_('y');
      return chunk(
        localFn(f, [], [ret(num(1), num(2), num(3))]),
        exprStat(call(glob('print'), [call(localE(f), [])])),
        exprStat(call(glob('print'), [group(call(localE(f), []))])),
        localStat([a, b, c], [call(localE(f), [])]),
        exprStat(call(glob('print'), [localE(a), localE(b), localE(c)])),
        localStat([t], [tableE([listItem(call(localE(f), []))])]),
        exprStat(call(glob('print'), [un('Len', localE(t)), idxe(localE(t), num(1)), idxe(localE(t), num(3))])),
        localStat([t2], [tableE([listItem(num(0)), listItem(call(localE(f), []))])]),
        exprStat(call(glob('print'), [un('Len', localE(t2)), idxe(localE(t2), num(1)), idxe(localE(t2), num(2))])),
        localStat([x, y], [num(10), call(localE(f), [])]),
        exprStat(call(glob('print'), [localE(x), localE(y)])),
      );
    })(),
  },
  {
    name: 'compound-assign',
    source: `local t = {x = 10, y = {20}}
t.x = t.x + 5
t.y[1] = t.y[1] * 2
local n = 7
n = n - 3
n = n // 2
print(t.x, t.y[1], n)
local calls = 0
local function box()
  calls = calls + 1
  return t
end
local b = box()
b.x = b.x + 100
print(t.x, calls)
`,
    ast: (() => {
      const t = local_('t');
      const n = local_('n');
      const calls = local_('calls');
      const box = local_('box');
      return chunk(
        localStat([t], [tableE([recItem('x', num(10)), recItem('y', tableE([listItem(num(20))]))])]),
        compoundS('Add', idx(localE(t), 'x'), num(5)),
        compoundS('Mul', idxe(idx(localE(t), 'y'), num(1)), num(2)),
        localStat([n], [num(7)]),
        compoundS('Sub', localE(n), num(3)),
        compoundS('FloorDiv', localE(n), num(2)),
        exprStat(call(glob('print'), [idx(localE(t), 'x'), idxe(idx(localE(t), 'y'), num(1)), localE(n)])),
        localStat([calls], [num(0)]),
        localFn(box, [], [
          assignS([localE(calls)], [bin('Add', localE(calls), num(1))]),
          ret(localE(t)),
        ]),
        // AST: single-evaluation compound (Luau semantics); source uses the
        // temp-variable equivalent (calls == 1 in both).
        compoundS('Add', idx(call(localE(box), []), 'x'), num(100)),
        exprStat(call(glob('print'), [idx(localE(t), 'x'), localE(calls)])),
      );
    })(),
  },
  {
    name: 'control-flow',
    source: `local sum = 0
for i = 1, 10 do
  if i % 2 == 0 then
    goto continue
  end
  sum = sum + i
  ::continue::
end
print(sum)
local i = 0
while true do
  i = i + 1
  if i > 3 then break end
  print("w", i)
end
local j = 0
repeat
  j = j + 1
  local d = j * 10
  print("r", d)
until j >= 3
`,
    ast: (() => {
      const sum = local_('sum');
      const iv = local_('i');
      const i = local_('i');
      const j = local_('j');
      const d = local_('d');
      return chunk(
        localStat([sum], [num(0)]),
        forS(iv, num(1), num(10), null, [
          ifS(bin('CompareEq', bin('Mod', localE(iv), num(2)), num(0)), [continueS()]),
          assignS([localE(sum)], [bin('Add', localE(sum), localE(iv))]),
        ]),
        exprStat(call(glob('print'), [localE(sum)])),
        localStat([i], [num(0)]),
        whileS(boolE(true), [
          assignS([localE(i)], [bin('Add', localE(i), num(1))]),
          ifS(bin('CompareGt', localE(i), num(3)), [breakS()]),
          exprStat(call(glob('print'), [str('w'), localE(i)])),
        ]),
        localStat([j], [num(0)]),
        repeatS(bin('CompareGe', localE(j), num(3)), [
          assignS([localE(j)], [bin('Add', localE(j), num(1))]),
          localStat([d], [bin('Mul', localE(j), num(10))]),
          exprStat(call(glob('print'), [str('r'), localE(d)])),
        ]),
      );
    })(),
  },
  {
    name: 'ifelse-expr',
    source: `local a, b = 1, 2
local m1
if a > b then m1 = a else m1 = b end
print(m1)
local m2 = 10
if a < b then m2 = a else m2 = b end
print(m2)
print(a > b and a or b)
print(not a, not nil, not 0, not "")
`,
    ast: (() => {
      const a = local_('a');
      const b = local_('b');
      const m1 = local_('m1');
      const m2 = local_('m2');
      return chunk(
        localStat([a, b], [num(1), num(2)]),
        localStat([m1], [ifElseE(bin('CompareGt', localE(a), localE(b)), localE(a), localE(b))]),
        exprStat(call(glob('print'), [localE(m1)])),
        localStat([m2], [ifElseE(bin('CompareLt', localE(a), localE(b)), localE(a), localE(b))]),
        exprStat(call(glob('print'), [localE(m2)])),
        exprStat(call(glob('print'), [bin('Or', bin('And', bin('CompareGt', localE(a), localE(b)), localE(a)), localE(b))])),
        exprStat(call(glob('print'), [un('Not', localE(a)), un('Not', nilE()), un('Not', num(0)), un('Not', str(''))])),
      );
    })(),
  },
  {
    name: 'interp-string',
    source: `local x, y = "one", "two"
print(string.format("a=%sb=%s", x, y))
local n = 2
print(string.format("n=%s", n))
print(string.format("mix=%s-%s-%s", x, y, n))
`,
    ast: (() => {
      const x = local_('x');
      const y = local_('y');
      const n = local_('n');
      return chunk(
        localStat([x, y], [str('one'), str('two')]),
        exprStat(call(glob('print'), [interp(['a=', 'b='], [localE(x), localE(y)])])),
        localStat([n], [num(2)]),
        // %* uses tostring semantics: number 2 -> "2" in Luau; the 5.4
        // equivalent of `n={n}` is string.format("n=%s", n) ONLY when n is
        // integer-valued (5.4 %s prints 2.0 for floats; Luau prints "2").
        exprStat(call(glob('print'), [interp(['n='], [localE(n)])])),
        exprStat(call(glob('print'), [interp(['mix=', '-', '-', ''], [localE(x), localE(y), localE(n)])])),
      );
    })(),
  },
  {
    name: 'errors-pcall',
    source: `local ok, err = pcall(error, "boom", 0)
print(ok, err)
local ok2, err2 = pcall(function() error("inner", 0) end)
print(ok2, err2)
local ok3, err3 = pcall(function() return nil + 1 end)
print(ok3, err3 ~= nil)
print(pcall(function() return 1, 2 end))
local ok4, err4 = pcall(assert, false, "custom")
print(ok4, err4)
`,
    ast: (() => {
      const ok = local_('ok');
      const err = local_('err');
      const ok2 = local_('ok2');
      const err2 = local_('err2');
      const ok3 = local_('ok3');
      const err3 = local_('err3');
      const ok4 = local_('ok4');
      const err4 = local_('err4');
      return chunk(
        localStat([ok, err], [call(glob('pcall'), [glob('error'), str('boom'), num(0)])]),
        exprStat(call(glob('print'), [localE(ok), localE(err)])),
        localStat([ok2, err2], [call(glob('pcall'), [fnE([], [exprStat(call(glob('error'), [str('inner'), num(0)]))])])]),
        exprStat(call(glob('print'), [localE(ok2), localE(err2)])),
        localStat([ok3, err3], [call(glob('pcall'), [fnE([], [ret(bin('Add', nilE(), num(1)))])])]),
        // err3 printed as ~= nil: runtime-error MESSAGES carry a
        // "chunkname:line:" prefix in real Lua (random tmp path + line
        // number); the container carries no debug info (D-M5-11), so the
        // differential compares catch-ness + non-nil, not the prefixed
        // text. Message-body equality is covered by the level-0 error
        // cases above and the assert case below.
        exprStat(call(glob('print'), [localE(ok3), bin('CompareNe', localE(err3), nilE())])),
        exprStat(call(glob('print'), [call(glob('pcall'), [fnE([], [ret(num(1), num(2))])])])),
        localStat([ok4, err4], [call(glob('pcall'), [glob('assert'), boolE(false), str('custom')])]),
        exprStat(call(glob('print'), [localE(ok4), localE(err4)])),
      );
    })(),
  },
  {
    name: 'metamethods',
    source: `local V = {}
V.__add = function(a, b) return a[1] + b[1] end
V.__eq = function(a, b) return a[1] == b[1] end
V.__lt = function(a, b) return a[1] < b[1] end
V.__len = function(a) return 99 end
V.__concat = function(a, b) return "V" end
V.__unm = function(a) return "neg" end
V.__idiv = function(a, b) return "idiv" end
V.__call = function(self, x) return x * 100 end
local a = setmetatable({1}, V)
local b = setmetatable({2}, V)
print(a + b, -a, a .. "x", #a, a // b, a(3))
print(a == b, a < b, b < a)
local same = setmetatable({1}, V)
print(a == same)
`,
    ast: (() => {
      const V = local_('V');
      const a = local_('a');
      const b = local_('b');
      const same = local_('same');
      const am = local_('a');
      const bm = local_('b');
      const selfM = local_('self');
      const xM = local_('x');
      const bM = local_('b');
      const a2 = local_('a');
      const b2 = local_('b');
      const a3 = local_('a');
      const a4 = local_('a');
      return chunk(
        localStat([V], [tableE([])]),
        assignS([idx(localE(V), '__add')], [fnE([am, bm], [ret(bin('Add', idxe(localE(am), num(1)), idxe(localE(bm), num(1))))])]),
        assignS([idx(localE(V), '__eq')], [fnE([a2, b2], [ret(bin('CompareEq', idxe(localE(a2), num(1)), idxe(localE(b2), num(1))))])]),
        assignS([idx(localE(V), '__lt')], [fnE([a3, bM], [ret(bin('CompareLt', idxe(localE(a3), num(1)), idxe(localE(bM), num(1))))])]),
        assignS([idx(localE(V), '__len')], [fnE([a4], [ret(num(99))])]),
        assignS([idx(localE(V), '__concat')], [fnE([local_('a'), local_('b')], [ret(str('V'))])]),
        assignS([idx(localE(V), '__unm')], [fnE([local_('a')], [ret(str('neg'))])]),
        assignS([idx(localE(V), '__idiv')], [fnE([local_('a'), local_('b')], [ret(str('idiv'))])]),
        assignS([idx(localE(V), '__call')], [fnE([selfM, xM], [ret(bin('Mul', localE(xM), num(100)))])]),
        localStat([a], [call(glob('setmetatable'), [tableE([listItem(num(1))]), localE(V)])]),
        localStat([b], [call(glob('setmetatable'), [tableE([listItem(num(2))]), localE(V)])]),
        exprStat(call(glob('print'), [
          bin('Add', localE(a), localE(b)), un('Minus', localE(a)), bin('Concat', localE(a), str('x')),
          un('Len', localE(a)), bin('FloorDiv', localE(a), localE(b)), call(localE(a), [num(3)]),
        ])),
        exprStat(call(glob('print'), [
          bin('CompareEq', localE(a), localE(b)), bin('CompareLt', localE(a), localE(b)), bin('CompareLt', localE(b), localE(a)),
        ])),
        localStat([same], [call(glob('setmetatable'), [tableE([listItem(num(1))]), localE(V)])]),
        exprStat(call(glob('print'), [bin('CompareEq', localE(a), localE(same))])),
      );
    })(),
  },
  {
    name: 'table-constructor',
    source: `local mixed = {1, 2, x = "ex", [10] = "ten", 3}
print(#mixed, mixed[1], mixed[3], mixed.x, mixed[10])
local nested = {a = {b = {c = "deep"}}}
print(nested.a.b.c)
local gen = {[1 + 1] = "two"}
print(gen[2])
local empty = {}
print(#empty)
`,
    ast: (() => {
      const mixed = local_('mixed');
      const nested = local_('nested');
      const gen = local_('gen');
      const empty = local_('empty');
      return chunk(
        localStat([mixed], [tableE([
          listItem(num(1)), listItem(num(2)), recItem('x', str('ex')),
          genItem(num(10), str('ten')), listItem(num(3)),
        ])]),
        exprStat(call(glob('print'), [
          un('Len', localE(mixed)), idxe(localE(mixed), num(1)), idxe(localE(mixed), num(3)),
          idx(localE(mixed), 'x'), idxe(localE(mixed), num(10)),
        ])),
        localStat([nested], [tableE([recItem('a', tableE([recItem('b', tableE([recItem('c', str('deep'))]))]))])]),
        exprStat(call(glob('print'), [idx(idx(idx(localE(nested), 'a'), 'b'), 'c')])),
        localStat([gen], [tableE([genItem(bin('Add', num(1), num(1)), str('two'))])]),
        exprStat(call(glob('print'), [idxe(localE(gen), num(2))])),
        localStat([empty], [tableE([])]),
        exprStat(call(glob('print'), [un('Len', localE(empty))])),
      );
    })(),
  },
  {
    name: 'repeat-captures',
    source: `local fs = {}
local i = 0
repeat
  i = i + 1
  local x = i * 10
  fs[i] = function() return x end
until i >= 3
print(fs[1](), fs[2](), fs[3]())
`,
    ast: (() => {
      const fs = local_('fs');
      const i = local_('i');
      const x = local_('x');
      return chunk(
        localStat([fs], [tableE([])]),
        localStat([i], [num(0)]),
        repeatS(bin('CompareGe', localE(i), num(3)), [
          assignS([localE(i)], [bin('Add', localE(i), num(1))]),
          localStat([x], [bin('Mul', localE(i), num(10))]),
          assignS([idxe(localE(fs), localE(i))], [fnE([], [ret(localE(x))])]),
        ]),
        exprStat(call(glob('print'), [
          call(idxe(localE(fs), num(1)), []), call(idxe(localE(fs), num(2)), []), call(idxe(localE(fs), num(3)), []),
        ])),
      );
    })(),
  },
  {
    name: 'upvalue-chains',
    source: `local a1 = 1
local function l2()
  local a2 = 10
  return function()
    local a3 = 100
    return function()
      return a1 + a2 + a3
    end
  end
end
print(l2()()())
local up = "up"
local function setu(v) up = v end
setu("changed")
print(up)
`,
    ast: (() => {
      const a1 = local_('a1');
      const l2 = local_('l2');
      const up = local_('up');
      const setu = local_('setu');
      const v = local_('v');
      const a2 = local_('a2');
      const a3 = local_('a3');
      return chunk(
        localStat([a1], [num(1)]),
        localFn(l2, [], [
          localStat([a2], [num(10)]),
          ret(fnE([], [
            localStat([a3], [num(100)]),
            ret(fnE([], [ret(bin('Add', bin('Add', localE(a1), localE(a2)), localE(a3)))])),
          ])),
        ]),
        exprStat(call(glob('print'), [call(call(call(localE(l2), []), []), [])])),
        localStat([up], [str('up')]),
        localFn(setu, [v], [assignS([localE(up)], [localE(v)])]),
        exprStat(call(localE(setu), [str('changed')])),
        exprStat(call(glob('print'), [localE(up)])),
      );
    })(),
  },
  {
    name: 'assign-order',
    source: `local i = 3
local t = {}
i, t[i] = i + 1, 20
print(i, t[3])
local a, b = 1, 2
a, b = b, a
print(a, b)
`,
    ast: (() => {
      const i = local_('i');
      const t = local_('t');
      const a = local_('a');
      const b = local_('b');
      return chunk(
        localStat([i], [num(3)]),
        localStat([t], [tableE([])]),
        // Lua 5.1 manual §2.4.3: all values first; a[3] stores the OLD i.
        assignS([localE(i), idxe(localE(t), localE(i))], [bin('Add', localE(i), num(1)), num(20)]),
        exprStat(call(glob('print'), [localE(i), idxe(localE(t), num(3))])),
        localStat([a, b], [num(1), num(2)]),
        assignS([localE(a), localE(b)], [localE(b), localE(a)]),
        exprStat(call(glob('print'), [localE(a), localE(b)])),
      );
    })(),
  },
];

