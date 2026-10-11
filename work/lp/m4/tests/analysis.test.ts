/**
 * Semantic-analysis + const-plan suite (IR.md Interface B, doc §10.2 items
 * 2 and 6).
 *
 * Every case cites an outside source (§22.1):
 *  - [L5.1 §2.6] Lua 5.1 reference manual — upvalues: closures share
 *    by-reference cells; "a closure may refer to outer local variables"
 *  - [L5.1 §2.4.3] for/for-in: the control variable is local to the loop
 *    and fresh per iteration (rebound by loop mechanics)
 *  - [L5.1 §2.4.4] repeat/until scope
 *  - [LuauSyntax] luau.org/syntax — if-else expressions with local
 *    bindings, string interpolation, type annotations (erased at runtime)
 *  - [BYTECODE-M5 §5, D-M5-5] upval kinds ref/upval/val — val reserved
 *    for M4 immutability facts (this module)
 *  - [IR.md §2.1/§2.2] the v0 interface this implements (D-M4-19..23)
 *  - [IEEE754] double rounding: sums needing > 53 significant bits lose
 *    low bits — the R1 key-collision evidence test
 */
import { describe, expect, test } from 'bun:test';
import { parse } from '../src/parser';
import { print } from '../src/printer';
import { analyze } from '../src/analysis';
import type {
  AnalysisResult, CaptureInfo, ConstEntry, FunctionUnit,
} from '../src/analysis';
import type { Chunk, Expr, Local, Stat } from '../src/ast';
import { Generator, Rng } from './fuzz';

const LOC = { start: { line: 1, column: 0, offset: 0 }, end: { line: 1, column: 0, offset: 0 } };

function run(src: string): { chunk: Chunk; result: AnalysisResult } {
  const chunk = parse(src);
  return { chunk, result: analyze(chunk) };
}

/** All runtime function units in deterministic structural order (type-level
 *  subtrees skipped — the analysis never enters them, D-M4-21). */
function units(chunk: Chunk): FunctionUnit[] {
  const out: FunctionUnit[] = [chunk];
  const goStat = (s: Stat): void => {
    switch (s.kind) {
      case 'Block': s.body.forEach(goStat); break;
      case 'If':
        goExpr(s.condition); s.thenbody.body.forEach(goStat);
        if (s.elsebody) s.elsebody.kind === 'If' ? goStat(s.elsebody) : s.elsebody.body.forEach(goStat);
        break;
      case 'While': goExpr(s.condition); s.body.body.forEach(goStat); break;
      case 'Repeat': s.body.body.forEach(goStat); goExpr(s.condition); break;
      case 'Return': s.list.forEach(goExpr); break;
      case 'ExprStat': goExpr(s.expr); break;
      case 'Local': s.values.forEach(goExpr); break;
      case 'For': goExpr(s.from); goExpr(s.to); if (s.step) goExpr(s.step); s.body.body.forEach(goStat); break;
      case 'ForIn': s.values.forEach(goExpr); s.body.body.forEach(goStat); break;
      case 'Assign': s.values.forEach(goExpr); s.vars.forEach(goExpr); break;
      case 'CompoundAssign': goExpr(s.value); goExpr(s.var); break;
      case 'FunctionStat': goExpr(s.name); goFn(s.func); break;
      case 'LocalFunction': goFn(s.func); break;
      case 'TypeAlias': case 'TypeFunction': case 'Break': case 'Continue': break;
    }
  };
  const goFn = (f: Extract<Expr, { kind: 'Function' }>): void => {
    out.push(f);
    f.body.body.forEach(goStat);
  };
  const goExpr = (e: Expr): void => {
    switch (e.kind) {
      case 'Function': goFn(e); break;
      case 'Call': goExpr(e.func); e.args.forEach(goExpr); break;
      case 'IndexName': goExpr(e.expr); break;
      case 'IndexExpr': goExpr(e.expr); goExpr(e.index); break;
      case 'Table': for (const it of e.items) { if (it.key) goExpr(it.key); goExpr(it.value); } break;
      case 'Unary': goExpr(e.expr); break;
      case 'Binary': goExpr(e.left); goExpr(e.right); break;
      case 'TypeAssertion': goExpr(e.expr); break;
      case 'IfElse': goExpr(e.condition); goExpr(e.trueExpr); goExpr(e.falseExpr); break;
      case 'Group': goExpr(e.expr); break;
      case 'Instantiate': goExpr(e.expr); break;
      case 'InterpString': e.expressions.forEach(goExpr); break;
      default: break;
    }
  };
  chunk.block.body.forEach(goStat);
  return out;
}

/** All function literals in `src`, outermost-first (chunk excluded). */
function fns(src: string): { chunk: Chunk; result: AnalysisResult; fs: Extract<Expr, { kind: 'Function' }>[] } {
  const { chunk, result } = run(src);
  const fs = units(chunk).filter((u): u is Extract<Expr, { kind: 'Function' }> => u !== chunk);
  expect(fs.length).toBeGreaterThan(0);
  return { chunk, result, fs };
}

function caps(result: AnalysisResult, unit: FunctionUnit): readonly CaptureInfo[] {
  return result.captures.get(unit) ?? [];
}

function plan(result: AnalysisResult, unit: FunctionUnit): readonly ConstEntry[] {
  return result.constPlan.get(unit) ?? [];
}

function planFor(src: string): readonly ConstEntry[] {
  const { chunk, result } = run(src);
  return plan(result, chunk);
}

/** A comparable, Local-identity-free projection (structural stability
 *  oracle: analysis(print(parse(src))) ≅ analysis(parse(src))). */
function shape(src: string): string {
  const { chunk, result } = run(src);
  return JSON.stringify(units(chunk).map((u) => ({
    c: caps(result, u).map((ci) => [ci.local.name, ci.mode, ci.proof]),
    p: plan(result, u).map((e) => [e.key, e.kind, e.value, e.protect, e.inlineOk, e.globalName]),
  })));
}

// IEEE-754 helpers (R1/R2 evidence) ----------------------------------------

const f64 = new Float64Array(1);
const u32 = new Uint32Array(f64.buffer);
function doubleFromBits(lo: number, hi: number): number {
  u32[0] = lo >>> 0; u32[1] = hi >>> 0;
  return f64[0];
}
/** M5's current key formula (compile.ts addNumber) — reproduced here as
 *  EVIDENCE for the R1 finding, not for use. */
function naiveNumberKey(n: number): number {
  f64[0] = n;
  return u32[0] * 0x100000000 + u32[1];
}

/** Hand-built AST for literal values the source grammar cannot express. */
function chunkReturning(...exprs: Expr[]): Chunk {
  const ret: Stat = { kind: 'Return', location: LOC, list: exprs };
  return { kind: 'Chunk', location: LOC, block: { kind: 'Block', location: LOC, body: [ret] } };
}

// ---------------------------------------------------------------------------
// Captures: immutability classification [L5.1 §2.6; IR.md §2.1; D-M5-5]
// ---------------------------------------------------------------------------

describe('analysis: capture classification', () => {
  test('never-assigned local captured by a closure → val/never-assigned [L5.1 §2.6; D-M5-5]', () => {
    const { result, fs } = fns('local x = 1\nreturn function() return x end\n');
    const c = caps(result, fs[0]);
    expect(c.length).toBe(1);
    expect(c[0]!.mode).toBe('val');
    expect(c[0]!.proof).toBe('never-assigned');
    expect(c[0]!.local.name).toBe('x');
  });

  test('local reassigned after binding → ref/none (whole-binding) [IR.md §2.1]', () => {
    const { result, fs } = fns('local x = 1\nx = 2\nreturn function() return x end\n');
    expect(caps(result, fs[0])[0]!.mode).toBe('ref');
    expect(caps(result, fs[0])[0]!.proof).toBe('none');
  });

  test('compound assignment disqualifies val [LuauSyntax compound assign]', () => {
    const { result, fs } = fns('local x = 1\nreturn function() x += 1 end\n');
    expect(caps(result, fs[0])[0]!.mode).toBe('ref');
  });

  test('assignment THROUGH the upvalue is itself a capture (write-capture) [L5.1 §2.6]', () => {
    const { result, fs } = fns('local x = 1\nreturn function() x = 5 end\n');
    const c = caps(result, fs[0]);
    expect(c.length).toBe(1);
    expect(c[0]!.local.name).toBe('x');
    expect(c[0]!.mode).toBe('ref');
  });

  test('whole-binding downgrade: a sibling writer downgrades the reader [IR.md §2.1]', () => {
    const { result, chunk } = run(
      'local x = 1\nlocal a = function() return x end\nlocal b = function() x = 2 end\nreturn a, b\n',
    );
    const fns = units(chunk).filter((u) => u !== chunk);
    for (const unit of fns) {
      const c = caps(result, unit);
      expect(c.length).toBe(1);
      expect(c[0]!.local.name).toBe('x');
      expect(c[0]!.mode).toBe('ref');
    }
  });

  test('parameter captured, never reassigned → val [L5.1 §2.6]', () => {
    const { result, fs } = fns('return function(a) return function() return a end end\n');
    const c = caps(result, fs[1]);
    expect(c.length).toBe(1);
    expect(c[0]!.mode).toBe('val');
    expect(c[0]!.local.name).toBe('a');
  });

  test('parameter reassigned in the body → ref', () => {
    const { result, fs } = fns('return function(a) a = a + 1 return function() return a end end\n');
    expect(caps(result, fs[1])[0]!.mode).toBe('ref');
  });

  test('method self is the method\'s own local — not a capture [Parser.cpp self rule]', () => {
    const { result, chunk } = run('local t = {}\nfunction t:m() return self end\nreturn t\n');
    const m = units(chunk).find((u) => u !== chunk)!;
    expect(caps(result, m)).toHaveLength(0);
  });

  test('numeric for control variable → ref (rebound per iteration) [L5.1 §2.4.3]', () => {
    const { result, fs } = fns('local fs = {}\nfor i = 1, 10 do fs[i] = function() return i end end\nreturn fs\n');
    const c = caps(result, fs[0]);
    expect(c.length).toBe(1);
    expect(c[0]!.local.name).toBe('i');
    expect(c[0]!.mode).toBe('ref');
  });

  test('generic for variables → ref [L5.1 §2.4.3]', () => {
    const { result, chunk } = run(
      'local out = {}\nfor k, v in pairs({ a = 1 }) do out[#out + 1] = function() return k, v end end\nreturn out\n',
    );
    const forS = chunk.block.body[1] as Extract<Stat, { kind: 'ForIn' }>;
    const innerFn = (forS.body.body[0] as Extract<Stat, { kind: 'Assign' }>)
      .values[0] as Extract<Expr, { kind: 'Function' }>;
    const c = caps(result, innerFn);
    expect(c.map((x) => x.local.name)).toEqual(['k', 'v']);
    for (const ci of c) expect(ci.mode).toBe('ref');
  });

  test('local function recursive name → val capture (binding is the only write)', () => {
    const { result, fs } = fns('local function rec(n) if n == 0 then return 0 end return rec(n - 1) end\nreturn rec\n');
    expect(caps(result, fs[0]).map((c) => c.local.name)).toEqual(['rec']);
    expect(caps(result, fs[0])[0]!.mode).toBe('val');
  });

  test('bind-after-RHS: the RHS closure sees the OUTER x, not the new one [Interface A]', () => {
    const { result, chunk } = run('local x = 1\nlocal x = function() return x end\nreturn x\n');
    const inner = units(chunk)[1]!;
    const c = caps(result, inner);
    expect(c.length).toBe(1);
    expect(c[0]!.local.name).toBe('x');
    // outer x is never assigned → val
    expect(c[0]!.mode).toBe('val');
  });

  test('if-else expression binding → val (binding precedes branches) [LuauSyntax; hand-built — the parser does not produce conditionLocal yet]', () => {
    // The AST field exists (printer + M5 compile.ts both consume it); the
    // grammar form `if local x = c then a else b` is not in the s3 parser.
    // Hand-build to pin the analysis contract for when it lands.
    const cond: Local = { kind: 'Local', location: LOC, name: 'c' };
    const ok: Local = { kind: 'Local', location: LOC, name: 'ok' };
    const chunk = chunkReturning({
      kind: 'IfElse',
      location: LOC,
      condition: { kind: 'LocalExpr', location: LOC, local: cond },
      conditionLocal: ok,
      trueExpr: {
        kind: 'Function', location: LOC, attributes: [], generics: [], genericPacks: [],
        self: null, args: [], vararg: false,
        body: { kind: 'Block', location: LOC, body: [{ kind: 'Return', location: LOC, list: [{ kind: 'LocalExpr', location: LOC, local: ok }] }] },
        debugname: null,
      },
      falseExpr: { kind: 'Nil', location: LOC },
    });
    const result = analyze(chunk);
    const fnUnit = [...result.captures.keys()].find((u) => u !== chunk)!;
    const c = caps(result, fnUnit);
    expect(c.map((x) => x.local.name)).toEqual(['ok']);
    expect(c[0]!.mode).toBe('val');
  });

  test('v1 proof values: never emits assigned-before-capture-only (open Q2) [IR.md §2.1 rule 2]', () => {
    const srcs = [
      'local x\nx = 1\nreturn function() return x end\n', // assigned BEFORE capture
      'local x = 1\nlocal f = function() return x end\nx = 2\nreturn f\n', // assigned AFTER capture
      'local x = 1\nfor i = 1, 3 do local f = function() return x end end\nx = 2\nreturn x\n',
    ];
    for (const src of srcs) {
      const { result, chunk } = run(src);
      for (const [, list] of result.captures) {
        for (const ci of list) {
          expect(['never-assigned', 'none']).toContain(ci.proof);
          if (ci.proof === 'assigned-before-capture-only') throw new Error('emitted in v1');
        }
      }
      expect(units(chunk).length).toBeGreaterThan(0);
    }
  });

  test('assignment before capture still → ref in v1 (conservative; Q2 deferred)', () => {
    const { result, fs } = fns('local x\nx = 5\nreturn function() return x end\n');
    expect(caps(result, fs[0])[0]!.mode).toBe('ref');
  });
});

// ---------------------------------------------------------------------------
// Captures: structure and order
// ---------------------------------------------------------------------------

describe('analysis: capture structure', () => {
  test('capture order = first-use source order [BYTECODE-M5 upval indexing]', () => {
    const { result, fs } = fns('local a, b = 1, 2\nreturn function() return b, a end\n');
    expect(caps(result, fs[0]).map((c) => c.local.name)).toEqual(['b', 'a']);
  });

  test('transitive capture: entry ONLY at the parent-local boundary (C1) [L5.1 §2.6; D-M5-19]', () => {
    const { result, chunk } = run(
      'local g = 1\nlocal function middle()\n  local inner = function() return g end\n  return inner\nend\nreturn middle\n',
    );
    const [root, middleFn, innerFn] = units(chunk);
    void root;
    // middle is the DIRECT CHILD of the owner (root) → the decision lives here.
    expect(caps(result, middleFn).map((c) => c.local.name)).toEqual(['g']);
    // inner's reference is transitive (through middle's upvalue): kind-2
    // descriptor, no val/ref decision, NO entry (C1).
    expect(caps(result, innerFn)).toHaveLength(0);
  });

  test('transitive order: descendant-triggered capture lands in source-trigger order', () => {
    const { result, chunk } = run(
      'local a, b = 1, 2\nlocal function middle()\n  local inner = function() return b end\n  return a, inner\nend\nreturn middle\n',
    );
    const [, middleFn] = units(chunk);
    // b is triggered by the inner closure (source position 1 inside middle);
    // a is read by middle's own return (source position 2). (Order is a
    // freebie — C1 pins consumption by identity, never order.)
    expect(caps(result, middleFn).map((c) => c.local.name)).toEqual(['b', 'a']);
  });

  test('no duplicate capture entries for repeated uses', () => {
    const { result, fs } = fns('local x = 1\nreturn function() return x, x, x end\n');
    expect(caps(result, fs[0]).length).toBe(1);
  });

  test('shadowing: the capture binds the INNER local by identity [Interface A]', () => {
    const { result, chunk } = run(
      'local x = 1\nlocal function g() local x = 2 return function() return x end end\nreturn g\n',
    );
    const [, , inner] = units(chunk);
    const c = caps(result, inner);
    expect(c.length).toBe(1);
    expect(c[0]!.local.name).toBe('x');
    expect(c[0]!.mode).toBe('val'); // the INNER x is never assigned
  });

  test('typeof(expr) annotation creates NO phantom capture (types erased) [D-M4-21; M5 compile.ts TypeAlias break]', () => {
    const { result, fs } = fns('local function f(x) local y: typeof(x) = 1 return function() return y end end\nreturn f\n');
    // y IS captured (runtime read); x is NOT (annotation-only use).
    expect(caps(result, fs[1]).map((c) => c.local.name)).toEqual(['y']);
    expect(caps(result, fs[0]).length).toBe(0);
  });

  test('TypeAlias/TypeFunction statements are skipped entirely [D-M4-21]', () => {
    const { result, chunk } = run(
      'type Point = { x: number }\ntype F = (x: number) -> number\nlocal a = 1\nreturn a\n',
    );
    expect(units(chunk)).toEqual([chunk]);
    expect(result.captures.size).toBe(1); // just the chunk entry
  });

  test('vararg and globals are never captures [L5.1 §2.5; M5 per-frame varargs]', () => {
    const { result, fs } = fns('local p = print\nreturn function(...) local t = p return function() return t end end\n');
    expect(caps(result, fs[1]).map((c) => c.local.name)).toEqual(['t']);
    expect(caps(result, fs[1])[0]!.mode).toBe('val');
    // The outer unit captures ONLY the local p — `...` and the global
    // `print` contribute nothing.
    expect(caps(result, fs[0]).map((c) => c.local.name)).toEqual(['p']);
  });

  test('every runtime function unit gets map entries (even capture-free) [R3]', () => {
    const { result, chunk } = run('local a = 1\nlocal f = function() return 1 end\nreturn a, f\n');
    expect(result.captures.size).toBe(units(chunk).length);
    expect(result.constPlan.size).toBe(units(chunk).length);
    expect(caps(result, units(chunk)[1]!)).toHaveLength(0);
  });

  test('function-stat base chain reads are walked (capture via the base)', () => {
    const { result, chunk } = run(
      'local ns = {}\nlocal helper = 5\nfunction ns.f() return helper end\nreturn ns\n',
    );
    const fStat = chunk.block.body[2] as Extract<Stat, { kind: 'FunctionStat' }>;
    const fUnit = units(chunk).find((u) => u === fStat.func)!;
    expect(caps(result, fUnit).map((c) => c.local.name)).toEqual(['helper']);
  });

  test('repeat/until: locals of the body are visible in until — same unit, no capture [L5.1 §2.4.4]', () => {
    const { result, chunk } = run(
      'local n = 0\nrepeat local done = n > 2 n += 1 until done\nreturn n\n',
    );
    expect(units(chunk)).toEqual([chunk]);
    expect(result.captures.get(chunk)).toHaveLength(0);
  });
});

// ---------------------------------------------------------------------------
// Const plan [IR.md §2.2; BYTECODE-M5 §4/§6.1-6.2]
// ---------------------------------------------------------------------------

describe('analysis: const plan', () => {
  test('plain strings: protect iff ≥ 8 bytes [IR.md §2.2]', () => {
    const p = planFor('return "seven!!", "0123456789"\n');
    expect(p.map((e) => [e.value, e.protect])).toEqual([['seven!!', false], ['0123456789', true]]);
  });

  test('member names are always protect (GETTABLEKS/SETTABLEKS/method) [IR.md §2.2; compile.ts addString(v.index)]', () => {
    const p = planFor('local t = t2.x\nlocal u = t:m()\nreturn u.y\n');
    const names = p.filter((e) => e.kind === 'string');
    expect(names.map((e) => e.value).sort()).toEqual(['m', 't2', 'x', 'y']);
    for (const e of names) expect(e.protect).toBe(true);
    // [Q5] t2 is the only global NAME in the unit — members are not.
    for (const e of names) expect(e.globalName).toBe(e.value === 't2');
  });

  test('literal + member name merge to one entry, protect=true [dedup rule]', () => {
    const p = planFor('return "count", t.count\n');
    const hit = p.filter((e) => e.value === 'count');
    expect(hit.length).toBe(1);
    expect(hit[0]!.protect).toBe(true);
  });

  test('dedup: same string twice → one entry, first position', () => {
    const p = planFor('return "dup", "dup", "dup"\n');
    expect(p.filter((e) => e.value === 'dup').length).toBe(1);
  });

  test('C4: same value, distinct raws stay DISTINCT entries (raw-keyed superset)', () => {
    const p = planFor('return 0x10, 16\n');
    expect(p.length).toBe(2);
    expect(p.map((e) => e.key)).toEqual(['n:0x10', 'n:16']);
    expect(p[0]!.value).toBe('0x10');
    expect(p[1]!.value).toBe('16');
    for (const e of p) expect(e.inlineOk).toBe(true); // value 16 fits LOADINT
  });

  test('inlineOk mirrors M5 LOADINT: 32767 yes, 32768 no [compile.ts Number case; D-M4-22]', () => {
    const p = planFor('return 32767, 32768, 0\n');
    expect(p.map((e) => [e.value, e.inlineOk])).toEqual([
      ['32767', true], ['32768', false], ['0', true],
    ]);
  });

  test('hex/exponent raws: protect=true even when inlineOk (precedence documented) [IR.md §2.2]', () => {
    const p = planFor('return 0x10, 1e2\n');
    for (const e of p) {
      expect(e.protect).toBe(true);
      expect(e.inlineOk).toBe(true); // 16 and 100 fit LOADINT
    }
  });

  test('plain floats pool without protect; dot-leading raw protects', () => {
    const p = planFor('return 0.5, .25\n');
    expect(p.map((e) => [e.value, e.protect, e.inlineOk])).toEqual([
      ['0.5', false, false], ['.25', true, false],
    ]);
  });

  test('1.5e3 = 1500 → inlineOk (integral, in range)', () => {
    const p = planFor('return 1.5e3\n');
    expect(p[0]!.inlineOk).toBe(true);
  });

  test('infinity raw (1e999) pools, not inlineOk [IEEE754]', () => {
    const p = planFor('return 1e999\n');
    expect(p.length).toBe(1);
    expect(p[0]!.inlineOk).toBe(false);
    expect(p[0]!.protect).toBe(true);
  });

  test('int64 literals: kind int, raw key (Q4 ANSWERED: classify)', () => {
    const p = planFor('return 42i\n');
    expect(p.length).toBe(1);
    expect(p[0]!.kind).toBe('int');
    expect(p[0]!.key).toBe('i:42i');
    expect(p[0]!.value).toBe('42i');
    expect(p[0]!.inlineOk).toBe(false);
  });

  test('interp-string literal parts are plain string constants [LuauSyntax interpolation; D-M5-8]', () => {
    const p = planFor('local n = 5\nreturn `count={n}-done`\n');
    const strs = p.filter((e) => e.kind === 'string').map((e) => e.value);
    expect(strs).toEqual(['count=', '-done']);
  });

  test('per-function isolation: nested literals are NOT in the parent plan [BYTECODE-M5 §4]', () => {
    const { result, chunk } = run('local a = "PARENT_STR_9"\nlocal f = function() return "NESTED_STR_9" end\nreturn a, f\n');
    const root = plan(result, chunk).map((e) => e.value);
    const nested = plan(result, units(chunk)[1]!).map((e) => e.value);
    expect(root).toContain('PARENT_STR_9');
    expect(root).not.toContain('NESTED_STR_9');
    expect(nested).toEqual(['NESTED_STR_9']);
  });

  test('the chunk itself is a plan key (main = proto 0) [R3]', () => {
    const { chunk, result } = run('return "MAIN"\n');
    expect(result.constPlan.has(chunk)).toBe(true);
    expect(plan(result, chunk).map((e) => e.value)).toEqual(['MAIN']);
  });

  test('annotation strings are NOT planned (types erased) [D-M4-21]', () => {
    const p = planFor('local x: "AAAAAAAA" = "b"\nreturn x\n');
    expect(p.map((e) => e.value)).toEqual(['b']);
  });

  test('bool/nil literals never enter the plan [IR.md §2.2 inline classes]', () => {
    const p = planFor('return true, nil, false\n');
    expect(p).toHaveLength(0);
  });

  test('table Record keys are plain string constants', () => {
    const p = planFor('return { tiny = 1, ["LONG_KEY_9"] = 2, [exprkey] = 3 }\n');
    // exprkey is a global read → planned + flagged [Q5]; keys "tiny"/
    // "LONG_KEY_9" are data/member strings, never globalName.
    expect(p.filter((e) => e.kind === 'string').map((e) => [e.value, e.protect, e.globalName])).toEqual([
      ['tiny', false, false], ['LONG_KEY_9', true, false], ['exprkey', true, true],
    ]);
  });

  test('string-call and table-call arguments are walked (Record keys are consts)', () => {
    const p = planFor('return f"ARG_STR_9", g{ k = "VAL_STR_9" }\n');
    expect(p.filter((e) => e.kind === 'string').map((e) => [e.value, e.globalName]).sort()).toEqual([
      ['ARG_STR_9', false], ['VAL_STR_9', false], ['f', true], ['g', true], ['k', false],
    ]);
  });
});

// ---------------------------------------------------------------------------
// Key exactness (R1) and -0 defense (R2) [IEEE754]
// ---------------------------------------------------------------------------

describe('analysis: exact const keys (R1 evidence for glm6)', () => {
  test('M5\'s naive n-key collides for > 53-bit patterns — reproduced', () => {
    const a = doubleFromBits(0x00200000, 0);
    const b = doubleFromBits(0x00200000, 1);
    expect(a).not.toBe(b); // distinct doubles (denormal-adjacent)
    // The formula u32[0] * 2^32 + u32[1] computes a REAL number:
    // 2^53 + 1 rounds back to 2^53 → both keys are 2^53.
    expect(naiveNumberKey(a)).toBe(naiveNumberKey(b));
  });

  test('plan keys are raw-keyed (C4): no number parsing in the key path [D-M4-23]', () => {
    const a = doubleFromBits(0x00200000, 0);
    const b = doubleFromBits(0x00200000, 1);
    const ra = analyze(chunkReturning({ kind: 'Number', location: LOC, value: a, raw: 'A' }));
    const rb = analyze(chunkReturning({ kind: 'Number', location: LOC, value: b, raw: 'B' }));
    const ka = [...ra.constPlan.values()][0]![0]!.key;
    const kb = [...rb.constPlan.values()][0]![0]!.key;
    expect(ka).toBe('n:A');
    expect(kb).toBe('n:B');
    expect(ka).not.toBe(kb);
  });

  test('-0 vs +0: distinct raws → distinct entries; -0 is never inlineOk (R2: LOADINT folds -0)', () => {
    const negZero = doubleFromBits(0, 0x80000000);
    const posZero = doubleFromBits(0, 0);
    expect(negZero).not.toBe(posZero); // distinguishable (1/negZero = -Inf)
    const r = analyze(chunkReturning(
      { kind: 'Number', location: LOC, value: negZero, raw: '-0.0' },
      { kind: 'Number', location: LOC, value: posZero, raw: '0.0' },
    ));
    const entries = [...r.constPlan.values()][0]!;
    expect(entries.length).toBe(2);
    expect(new Set(entries.map((e) => e.key)).size).toBe(2);
    const nz = entries.find((e) => e.value === '-0.0')!;
    expect(nz.inlineOk).toBe(false);
  });
});

// ---------------------------------------------------------------------------
// Q5: global-name classification [glm6-ruled 2026-10-11: classify — yes]
// ---------------------------------------------------------------------------

describe('analysis: Q5 global-name classification', () => {
  test('global read: planned, flagged, structural-protect (length-independent)', () => {
    const p = planFor('return game\n');
    expect(p).toHaveLength(1);
    expect(p[0]!.key).toBe('s:game');
    expect(p[0]!.kind).toBe('string');
    expect(p[0]!.value).toBe('game');
    expect(p[0]!.globalName).toBe(true);
    expect(p[0]!.protect).toBe(true); // 4 bytes < 8 — still protect (structural)
    expect(p[0]!.inlineOk).toBe(false);
  });

  test('SETGLOBAL target: `x = 1` plans s:x flagged (after the RHS value — Lua evaluates values first) [compile.ts addString on Global target]', () => {
    const p = planFor('x = 1\n');
    expect(p.map((e) => [e.key, e.globalName])).toEqual([['n:1', false], ['s:x', true]]);
  });

  test('compound-assign global target: `n += 1` plans s:n flagged (after the RHS)', () => {
    const p = planFor('n += 1\n');
    expect(p.map((e) => [e.key, e.globalName])).toEqual([['n:1', false], ['s:n', true]]);
  });

  test('plain `function foo() end`: FunctionStat.name Global → flagged [glm6 125-file class]', () => {
    const p = planFor('function foo() return 1 end\n');
    const hit = p.filter((e) => e.value === 'foo');
    expect(hit).toHaveLength(1);
    expect(hit[0]!.globalName).toBe(true);
    // `local function f` binds a Local — NOT a global name.
    const q = planFor('local function f() return 1 end\nreturn f\n');
    expect(q.filter((e) => e.globalName)).toHaveLength(0);
  });

  test('dotted function head: only the base Global is a name; members are member keys', () => {
    const p = planFor('function a.b:c() return 1 end\n');
    const strs = p.filter((e) => e.kind === 'string').map((e) => [e.value, e.globalName]);
    expect(strs).toEqual([['a', true], ['b', false], ['c', false]]);
  });

  test('literal + global-name merge: ONE entry, protect/globalName OR-merged [dedup rule]', () => {
    const p = planFor('local s = "print"\nprint(s)\n');
    const hit = p.filter((e) => e.value === 'print');
    expect(hit).toHaveLength(1);
    expect(hit[0]!.globalName).toBe(true);
    expect(hit[0]!.protect).toBe(true); // 5-byte literal alone would be false
  });

  test('_G.member access: _G is the global name; member key is NOT [GETTABLEKS, not GETGLOBAL]', () => {
    const p = planFor('return _G.print\n');
    const strs = p.filter((e) => e.kind === 'string').map((e) => [e.value, e.globalName]);
    expect(strs).toEqual([['_G', true], ['print', false]]);
  });

  test('member/record/interp strings are never globalName', () => {
    const p = planFor('local t = { k = 1 }\nlocal s = `x={t.k}`\nreturn s\n');
    for (const e of p) expect(e.globalName).toBe(false);
  });

  test('per-unit isolation: a global read inside a closure is only in THAT plan [BYTECODE-M5 §4]', () => {
    const { result, chunk } = run('local f = function() return workspace end\nreturn f, game\n');
    const root = plan(result, chunk);
    const inner = plan(result, units(chunk)[1]!);
    expect(root.filter((e) => e.globalName).map((e) => e.value)).toEqual(['game']);
    expect(inner.filter((e) => e.globalName).map((e) => e.value)).toEqual(['workspace']);
  });

  test('number/int entries are never globalName', () => {
    const p = planFor('return 0x10, 42i, game\n');
    for (const e of p.filter((e) => e.kind !== 'string')) {
      expect(e.globalName).toBe(false);
    }
    expect(p.filter((e) => e.globalName).map((e) => e.value)).toEqual(['game']);
  });
});

// ---------------------------------------------------------------------------
// Structural stability + fuzz soak [§10.3 oracle pattern]
// ---------------------------------------------------------------------------

describe('analysis: stability', () => {
  test('analysis is a pure function of the tree (same tree → equal tables)', () => {
    const chunk = parse('local x = 1\nreturn function() x = x + 1 return x end\n');
    const r1 = analyze(chunk);
    const r2 = analyze(chunk);
    expect(r1).toEqual(r2);
  });

  test('analysis(print(parse(src))) ≅ analysis(parse(src)) — Local-identity-free', () => {
    const srcs = [
      'local a, b = 1, "two"\nlocal function f(x) return function() return x + a, b end end\nreturn f\n',
      'for i = 1, 10 do local g = function() return i end print(g) end\n',
      'local t = { m = function(self) return self.n end, n = 5 }\nreturn t:m()\n',
      'local s = `x={1}y={2}`\nreturn s\n',
      'type T = { x: number }\nlocal v: T = { x = 0xFF }\nreturn v.x\n',
      'local n = 0\nrepeat local done = n > 2 n += 1 until done\nreturn n\n',
    ];
    for (const src of srcs) {
      const once = parse(src);
      const twice = parse(print(once));
      const r2 = analyze(twice);
      expect(shape(src)).toBe(JSON.stringify(units(twice).map((u) => ({
        c: (r2.captures.get(u) ?? []).map((ci) => [ci.local.name, ci.mode, ci.proof]),
        p: (r2.constPlan.get(u) ?? []).map((e) => [e.key, e.kind, e.value, e.protect, e.inlineOk, e.globalName]),
      }))));
    }
  });

  test('fuzz soak: 400 generated ASTs — total, invariant-holding [§10.3]', () => {
    let checkedCaptures = 0;
    let valCaptures = 0;
    for (let i = 0; i < 400; i++) {
      const chunk = new Generator(new Rng(0xA0A1A2 + i)).chunk();
      const r = analyze(chunk);
      // every runtime unit present in both maps
      for (const u of units(chunk)) {
        expect(r.captures.has(u)).toBe(true);
        expect(r.constPlan.has(u)).toBe(true);
      }
      for (const list of r.captures.values()) {
        const seen = new Set<unknown>();
        for (const ci of list) {
          expect(seen.has(ci.local)).toBe(false); // no duplicates
          seen.add(ci.local);
          expect(['ref', 'val']).toContain(ci.mode);
          expect(['never-assigned', 'none']).toContain(ci.proof);
          expect(ci.mode === 'val').toBe(ci.proof === 'never-assigned');
          checkedCaptures++;
          if (ci.mode === 'val') valCaptures++;
        }
      }
      for (const p of r.constPlan.values()) {
        const keys = new Set(p.map((e) => e.key));
        expect(keys.size).toBe(p.length); // deduped
        for (const e of p) {
          if (e.inlineOk) {
            expect(e.kind).toBe('number');
          }
          // [Q5] globalName is a string-only classification.
          if (e.globalName) {
            expect(e.kind).toBe('string');
            expect(e.inlineOk).toBe(false);
            expect(e.protect).toBe(true); // structural class, always
          }
        }
      }
    }
    // sanity: the generator produces captures, and both modes occur
    expect(checkedCaptures).toBeGreaterThan(50);
    expect(valCaptures).toBeGreaterThan(0);
    expect(valCaptures).toBeLessThan(checkedCaptures);
  });
});
