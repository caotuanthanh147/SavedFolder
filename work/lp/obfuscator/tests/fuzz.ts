/**
 * §10.3 random-program fuzzer (deterministic, seeded).
 *
 * Two oracles:
 *  1. AST round-trip: generate a random AST (valid by construction) →
 *     print → re-parse → astEqual. Exercises every printer/parser
 *     agreement on shapes, including ones no corpus source produces.
 *  2. Source mutation: take real corpus sources, splice/truncate at token
 *     boundaries, re-lex+parse → must either succeed or throw
 *     LuauSyntaxError (never a non-syntax throw, never a hang — bounded
 *     by the parser's own recursion limit).
 *
 * Deterministic: same seed ⇒ same programs. Run modes:
 *   bun run fuzz.ts [iterations] [seed]     (default 200 / 0xC0FFEE)
 * The test suite runs a fixed small batch so CI stays fast; the standalone
 * mode is for longer soak runs.
 */
import { LuauSyntaxError } from '../src/errors';
import { Lexer } from '../src/lexer';
import { parse } from '../src/parser';
import { print } from '../src/printer';
import { astEqual } from './roundtrip';
import type {
  BinaryOp, Chunk, Expr, FunctionExpr, Local, Stat, TableItem, Type, TypePack,
} from '../src/ast';

// ---------------------------------------------------------------------------
// Seeded RNG (mulberry32 — small, deterministic, adequate for structure gen)
// ---------------------------------------------------------------------------

export class Rng {
  private s: number;
  constructor(seed: number) {
    this.s = seed >>> 0;
  }
  next(): number {
    this.s = (this.s + 0x6d2b79f5) >>> 0;
    let t = this.s;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  }
  int(lo: number, hi: number): number {
    return lo + Math.floor(this.next() * (hi - lo + 1));
  }
  pick<T>(xs: readonly T[]): T {
    return xs[this.int(0, xs.length - 1)]!;
  }
  chance(p: number): boolean {
    return this.next() < p;
  }
}

// ---------------------------------------------------------------------------
// Name pools (identifier-safe; includes hazardous names deliberately)
// ---------------------------------------------------------------------------

const NAMES = ['a', 'b', 'x', 'y', 'foo', 'bar_1', 'toString', 'constructor', 'type', 'continue', 'self', 'value', 'self_', 'q'];
const FIELDS = ['f', 'g', 'm', 'index', 'toString', 'valueOf', 'x', 'y'];
const GLOBALS = ['print', 'pairs', 'ipairs', 'tostring', 't', 'math', 'os', 'M', 'lib'];
const BIN_OPS: BinaryOp[] = ['Add', 'Sub', 'Mul', 'Div', 'FloorDiv', 'Mod', 'Pow', 'Concat', 'CompareEq', 'CompareNe', 'CompareLt', 'CompareLe', 'CompareGt', 'CompareGe', 'And', 'Or'];

/** [op] = {left, right} — mirrors parser.ts/printer.ts BINARY_PRIORITY. */
const BIN_PRI: Record<BinaryOp, readonly [number, number]> = {
  Add: [6, 6], Sub: [6, 6], Mul: [7, 7], Div: [7, 7], FloorDiv: [7, 7], Mod: [7, 7],
  Pow: [10, 9], Concat: [5, 4],
  CompareEq: [3, 3], CompareNe: [3, 3], CompareLt: [3, 3], CompareLe: [3, 3],
  CompareGt: [3, 3], CompareGe: [3, 3], And: [2, 2], Or: [1, 1],
};
const UNARY_PRI = 8;

/** Shape a generated child like the PARSER would: bare iff it binds at the
 *  operand limit (or is an equal-priority left-assoc chain in the left
 *  slot); otherwise wrap in a Group (= source parens). Without this the
 *  generator emits parser-impossible ASTs (e.g. Binary(Pow, Unary(x)))
 *  whose required parens inject Groups on re-parse. */
function tailHasIfElse(e: Expr): boolean {
  if (e.kind === 'IfElse') return true;
  if (e.kind === 'Binary') return tailHasIfElse(e.right);
  if (e.kind === 'Unary') return tailHasIfElse(e.expr);
  return false;
}

/** Rightmost-printed path ends in a `::` assertion — the following `<`
 *  would be eaten as generic type parameters (parseSimpleType). */
function tailIsAssertion(e: Expr): boolean {
  if (e.kind === 'TypeAssertion') return true;
  if (e.kind === 'Binary') return tailIsAssertion(e.right);
  if (e.kind === 'Unary') return tailIsAssertion(e.expr);
  return false;
}

/** Mirror of the printer's operand rule: a child stays bare iff the
 *  parser would produce it bare from source — precedence-compatible AND,
 *  for IfElse tails, only in the un-followed rightmost position (a
 *  branch absorbs any following operator). */
function shaped(child: Expr, limit: number, isLeft: boolean, followed: boolean): Expr {
  if (child.kind === 'IfElse') {
    return isLeft || followed ? { kind: 'Group', location: LOC, expr: child } : child;
  }
  if (child.kind === 'Binary') {
    const [cl, cr] = BIN_PRI[child.op];
    const bare =
      (cl > limit || (cl === limit && isLeft && cl === cr)) &&
      !(followed && tailHasIfElse(child));
    return bare ? child : { kind: 'Group', location: LOC, expr: child };
  }
  if (child.kind === 'Unary') {
    const bare = UNARY_PRI > limit && !(followed && tailHasIfElse(child));
    return bare ? child : { kind: 'Group', location: LOC, expr: child };
  }
  return child;
}

// ---------------------------------------------------------------------------
// Generator (ASTs valid by construction)
// ---------------------------------------------------------------------------

export class Generator {
  private locals: Local[] = [];
  private loopDepth = 0;
  private vararg = false;

  constructor(private readonly rng: Rng) {}

  /** Pick a local then RESOLVE to the innermost same-named binding (name
   *  resolution semantics): picking a shadowed outer local would print a
   *  name that re-parses to the inner binding and break the round-trip. */
  private pickLocal(): Local {
    const picked = this.rng.pick(this.locals);
    for (let i = this.locals.length - 1; i >= 0; i--) {
      if (this.locals[i]!.name === picked.name) return this.locals[i]!;
    }
    return picked;
  }

  chunk(): Chunk {
    const body = this.block(0);
    return { kind: 'Chunk', location: LOC, block: { kind: 'Block', location: LOC, body } };
  }

  private block(depth: number): Stat[] {
    const n = this.rng.int(1, 4);
    const stats: Stat[] = [];
    for (let i = 0; i < n; i++) {
      const s = this.stat(depth);
      if (s) stats.push(s);
      if (s && (s.kind === 'Return' || s.kind === 'Break' || s.kind === 'Continue')) break;
    }
    return stats;
  }

  private bindLocal(annotation?: Type): Local {
    const local: Local = { kind: 'Local', location: LOC, name: this.rng.pick(NAMES), annotation };
    this.locals.push(local);
    return local;
  }

  private stat(depth: number): Stat | null {
    if (depth >= 3) return this.simpleStat();
    const roll = this.rng.int(0, 13);
    switch (roll) {
      case 0: { // local — RHS generated BEFORE binding [L5.1 §2.4:
        //          locals bind after the explist]
        const count = this.rng.int(1, 2);
        const values = this.rng.chance(0.85)
          ? Array.from({ length: count }, () => this.expr(depth + 1, 3))
          : [];
        const vars: Local[] = [];
        for (let i = 0; i < count; i++) vars.push(this.bindLocal(this.rng.chance(0.2) ? this.type(1) : undefined));
        return { kind: 'Local', location: LOC, vars, values };
      }
      case 1: { // local function (binds before body; parser sets
        //          debugname from the statement name)
        const local = this.bindLocal();
        const saved = this.locals.slice();
        const func = this.functionExpr(depth, false);
        this.locals = saved;
        return { kind: 'LocalFunction', location: LOC, name: local, func: { ...func, debugname: local.name } };
      }
      case 2: { // assignment
        const targets = this.rng.int(1, 2);
        const vars: Expr[] = [];
        for (let i = 0; i < targets; i++) {
          vars.push(this.rng.chance(0.5)
            ? { kind: 'Global', location: LOC, name: this.rng.pick(GLOBALS) }
            : { kind: 'IndexName', location: LOC, expr: this.prefixBase(depth), index: this.rng.pick(FIELDS), op: '.' });
        }
        const values = vars.map(() => this.expr(depth + 1, 3));
        return { kind: 'Assign', location: LOC, vars, values };
      }
      case 3: { // compound assign — arith/concat ops only [LuauSyntax]
        return { kind: 'CompoundAssign', location: LOC, op: this.rng.pick(['Add', 'Sub', 'Mul', 'Div', 'FloorDiv', 'Mod', 'Pow', 'Concat'] as const), var: { kind: 'Global', location: LOC, name: this.rng.pick(GLOBALS) }, value: this.expr(depth + 1, 3) };
      }
      case 4: { // call statement
        return { kind: 'ExprStat', location: LOC, expr: this.call(depth) };
      }
      case 5: { // if (each branch is its own scope)
        const scopedBlock = (d: number) => {
          const saved = this.locals.slice();
          const body = this.block(d);
          this.locals = saved;
          return { kind: 'Block' as const, location: LOC, body };
        };
        const elsebody = this.rng.chance(0.5) ? scopedBlock(depth + 1) : null;
        let result: Stat = { kind: 'Block', location: LOC, body: [] };
        result = { kind: 'If', location: LOC, condition: this.expr(depth + 1, 2), thenbody: scopedBlock(depth + 1), elsebody };
        if (this.rng.chance(0.3)) {
          result = { kind: 'If', location: LOC, condition: this.expr(depth + 1, 2), thenbody: scopedBlock(depth + 1), elsebody: result };
        }
        return result;
      }
      case 6: { // while (body locals do not escape)
        this.loopDepth++;
        const saved = this.locals.slice();
        const body = { kind: 'Block' as const, location: LOC, body: this.block(depth + 1) };
        this.locals = saved;
        this.loopDepth--;
        return { kind: 'While', location: LOC, condition: this.expr(depth + 1, 2), body };
      }
      case 7: { // repeat (until sees body locals)
        this.loopDepth++;
        const saved = this.locals.slice();
        const body = { kind: 'Block' as const, location: LOC, body: this.block(depth + 1) };
        const condition = this.expr(depth + 1, 2);
        this.locals = saved;
        this.loopDepth--;
        return { kind: 'Repeat', location: LOC, condition, body };
      }
      case 8: { // numeric for — bounds BEFORE the var binds [L5.1 §2.4.4]
        const saved = this.locals.slice();
        const from = this.expr(depth + 1, 2);
        const to = this.expr(depth + 1, 2);
        const step = this.rng.chance(0.5) ? this.expr(depth + 1, 2) : null;
        const v = this.bindLocal(this.rng.chance(0.15) ? this.type(1) : undefined);
        this.loopDepth++;
        const body = { kind: 'Block' as const, location: LOC, body: this.block(depth + 1) };
        this.loopDepth--;
        this.locals = saved;
        return { kind: 'For', location: LOC, var: v, from, to, step, body };
      }
      case 9: { // generic for — values BEFORE the vars bind [L5.1 §2.4.4]
        const saved = this.locals.slice();
        const values = [this.expr(depth + 1, 2)];
        const vars = [this.bindLocal(), this.bindLocal()];
        this.loopDepth++;
        const body = { kind: 'Block' as const, location: LOC, body: this.block(depth + 1) };
        this.loopDepth--;
        this.locals = saved;
        return { kind: 'ForIn', location: LOC, vars, values, body };
      }
      case 10: // break / continue (loop-guarded)
        if (this.loopDepth === 0) return this.simpleStat();
        return this.rng.chance(0.5)
          ? { kind: 'Break', location: LOC }
          : { kind: 'Continue', location: LOC };
      case 11: // return
        if (this.rng.chance(0.5)) return { kind: 'Return', location: LOC, list: [] };
        return { kind: 'Return', location: LOC, list: [this.expr(depth + 1, 3), this.expr(depth + 1, 3)] };
      case 12: { // do block (scopes)
        const saved = this.locals.slice();
        const body = this.block(depth + 1);
        this.locals = saved;
        return { kind: 'Block', location: LOC, body };
      }
      default:
        return this.simpleStat();
    }
  }

  private simpleStat(): Stat {
    return { kind: 'ExprStat', location: LOC, expr: this.call(2) };
  }

  private functionExpr(depth: number, forceVararg: boolean): FunctionExpr {
    const savedLocals = this.locals.slice();
    const savedVararg = this.vararg;
    const savedLoop = this.loopDepth;
    const vararg = forceVararg || this.rng.chance(0.3);
    const nargs = this.rng.int(0, 2);
    const args: Local[] = [];
    for (let i = 0; i < nargs; i++) {
      args.push({ kind: 'Local', location: LOC, name: this.rng.pick(NAMES), annotation: this.rng.chance(0.2) ? this.type(1) : undefined });
    }
    this.locals.push(...args);
    this.vararg = vararg;
    this.loopDepth = 0;
    const body = this.block(depth + 1);
    this.locals = savedLocals;
    this.vararg = savedVararg;
    this.loopDepth = savedLoop;
    return {
      kind: 'Function', location: LOC, attributes: [], generics: [], genericPacks: [],
      self: null, args, vararg,
      varargAnnotation: vararg && this.rng.chance(0.3) ? { kind: 'TypePackVariadic', location: LOC, type: this.type(1) } : undefined,
      returnAnnotation: this.rng.chance(0.2) ? this.typePack() : undefined,
      body: { kind: 'Block', location: LOC, body }, debugname: null,
    };
  }

  private prefixBase(depth: number): Expr {
    const roll = this.rng.int(0, 3);
    if (roll === 0) return { kind: 'Global', location: LOC, name: this.rng.pick(GLOBALS) };
    if (roll === 1 && this.locals.length > 0) return { kind: 'LocalExpr', location: LOC, local: this.pickLocal() };
    return { kind: 'IndexName', location: LOC, expr: { kind: 'Global', location: LOC, name: this.rng.pick(GLOBALS) }, index: this.rng.pick(FIELDS), op: '.' };
  }

  private call(depth: number): Expr {
    const base = this.rng.chance(0.3) && this.locals.length > 0
      ? { kind: 'LocalExpr' as const, location: LOC, local: this.pickLocal() }
      : { kind: 'Global' as const, location: LOC, name: this.rng.pick(GLOBALS) };
    const method = this.rng.chance(0.4);
    // parser-produced shape: op ':' ⇒ Call.self true (self never in args)
    const func: Expr = method
      ? { kind: 'IndexName', location: LOC, expr: base, index: this.rng.pick(FIELDS), op: ':' }
      : base;
    const nargs = this.rng.int(0, 2);
    const args = Array.from({ length: nargs }, () => this.expr(depth + 1, 2));
    let result: Expr = { kind: 'Call', location: LOC, func, args, self: method, tableCall: false };
    if (this.rng.chance(0.15)) {
      result = { kind: 'Call', location: LOC, func: result, args: [this.expr(depth + 1, 2)], self: false, tableCall: false };
    }
    return result;
  }

  private expr(depth: number, budget: number): Expr {
    if (budget <= 0 || depth >= 4) return this.atom();
    const roll = this.rng.int(0, 9);
    switch (roll) {
      case 0: {
        const op = this.rng.pick(BIN_OPS);
        const [l, r] = BIN_PRI[op];
        // the LEFT child is always followed (by this op); the RIGHT child
        // inherits this expression's own followed-ness (false at roots).
        // `x :: T < y` is UNPARSEABLE bare (parseSimpleType treats the
        // `<` after a type as generic parameters) — Group the Lt's left
        // when its tail is a type assertion, exactly like source parens.
        let left = this.expr(depth + 1, budget - 1);
        if (op === 'CompareLt' && tailIsAssertion(left)) {
          left = { kind: 'Group', location: LOC, expr: left };
        } else {
          left = shaped(left, l, true, true);
        }
        return { kind: 'Binary', location: LOC, op, left, right: shaped(this.expr(depth + 1, budget - 1), r, false, false) };
      }
      case 1:
        return { kind: 'Unary', location: LOC, op: this.rng.pick(['Not', 'Minus', 'Len'] as const), expr: shaped(this.expr(depth + 1, budget - 1), UNARY_PRI, true, false) };
      case 2:
        return { kind: 'Group', location: LOC, expr: this.expr(depth + 1, budget - 1) };
      case 3:
        return this.call(depth);
      case 4:
        return this.functionExpr(depth, false);
      case 5: { // table
        const items = Array.from({ length: this.rng.int(0, 3) }, () => {
          const r = this.rng.int(0, 2);
          if (r === 0) return { kind: 'List' as const, key: null, value: this.expr(depth + 1, budget - 1) };
          if (r === 1) {
            const key = this.rng.pick(FIELDS);
            const value = this.expr(depth + 1, budget - 1);
            // parser propagates the field name as the function's debugname
            const patched = value.kind === 'Function' && value.debugname === null
              ? { ...value, debugname: key }
              : value;
            return { kind: 'Record' as const, key: { kind: 'String', location: LOC, value: key }, value: patched };
          }
          return { kind: 'General' as const, key: this.expr(depth + 1, budget - 1), value: this.expr(depth + 1, budget - 1) };
        });
        return { kind: 'Table', location: LOC, items: items as TableItem[] };
      }
      case 6:
        if (!this.vararg) return this.atom();
        return { kind: 'Vararg', location: LOC };
      case 7:
        return { kind: 'IfElse', location: LOC, condition: this.expr(depth + 1, budget - 1), trueExpr: this.expr(depth + 1, budget - 1), falseExpr: this.expr(depth + 1, budget - 1) };
      case 8:
        return { kind: 'TypeAssertion', location: LOC, expr: this.prefixBase(depth), annotation: this.type(1) };
      default:
        return { kind: 'IndexExpr', location: LOC, expr: this.prefixBase(depth), index: this.expr(depth + 1, budget - 1) };
    }
  }

  private atom(): Expr {
    switch (this.rng.int(0, 5)) {
      case 0:
        return { kind: 'Nil', location: LOC };
      case 1:
        return { kind: 'Bool', location: LOC, value: this.rng.chance(0.5) };
      case 2: {
        // one roll for BOTH value and raw — the printer emits `raw`, so a
        // second roll desynchronizes value vs raw and every reparse of a
        // number atom mismatches
        const n = this.rng.int(0, 100);
        return { kind: 'Number', location: LOC, value: n, raw: String(n) };
      }
      case 3:
        return { kind: 'String', location: LOC, value: this.rng.pick(['hello', 'a\nb', 'x\0y', 'with "quote"', 'tab\there', '\xff', '']) };
      case 4:
        return { kind: 'Global', location: LOC, name: this.rng.pick(GLOBALS) };
      default:
        if (this.locals.length > 0) return { kind: 'LocalExpr', location: LOC, local: this.pickLocal() };
        return { kind: 'Global', location: LOC, name: this.rng.pick(GLOBALS) };
    }
  }

  private type(depth: number): Type {
    if (depth >= 2) return { kind: 'TypeReference', location: LOC, prefix: null, name: this.rng.pick(['number', 'string', 'boolean', 'any']), parameters: null };
    switch (this.rng.int(0, 6)) {
      case 0:
        return { kind: 'TypeReference', location: LOC, prefix: null, name: this.rng.pick(['number', 'string', 'boolean', 'any', 'Vec']), parameters: null };
      case 1:
        return { kind: 'TypeOptional', location: LOC, type: this.type(depth + 1) };
      case 2:
        return { kind: 'TypeUnion', location: LOC, types: [this.type(depth + 1), this.type(depth + 1)] };
      case 3:
        return { kind: 'TypeIntersection', location: LOC, types: [this.type(depth + 1), this.type(depth + 1)] };
      case 4:
        return { kind: 'TypeSingletonString', location: LOC, value: this.rng.pick(['lit', 'a b', 'x\x01y']) };
      case 5:
        return { kind: 'TypeofType', location: LOC, expr: { kind: 'Global', location: LOC, name: 'print' } };
      default:
        return { kind: 'TypeTable', location: LOC, props: [{ name: this.rng.pick(FIELDS), location: LOC, type: this.type(depth + 1) }], indexer: { indexType: { kind: 'TypeReference', location: LOC, prefix: null, name: 'string', parameters: null }, resultType: this.type(depth + 1), location: LOC }, isExact: false };
    }
  }

  private typePack(): TypePack {
    if (this.rng.chance(0.5)) return { kind: 'TypePackVariadic', location: LOC, type: this.type(1) };
    return { kind: 'TypePackExplicit', location: LOC, typeList: { types: [this.type(1), this.type(1)], tail: null } };
  }
}

const LOC = { start: { line: 1, column: 0, offset: 0 }, end: { line: 1, column: 0, offset: 0 } };

// ---------------------------------------------------------------------------
// Oracles
// ---------------------------------------------------------------------------

export interface FuzzResult {
  iterations: number;
  roundtripFailures: Array<{ seed: number; printed: string; error?: string }>;
  mutationFailures: Array<{ file: string; mutation: number; error: string }>;
}

/** AST round-trip oracle: gen → print → parse → astEqual. */
export function fuzzRoundtrip(iterations: number, seedBase: number): FuzzResult['roundtripFailures'] {
  const failures: FuzzResult['roundtripFailures'] = [];
  for (let i = 0; i < iterations; i++) {
    const seed = (seedBase + i) >>> 0;
    let chunk: Chunk;
    try {
      chunk = new Generator(new Rng(seed)).chunk();
    } catch {
      continue; // generator itself must not throw; skip defensively
    }
    try {
      const printed = print(chunk);
      const reparsed = parse(printed);
      if (!astEqual(chunk, reparsed)) {
        failures.push({ seed, printed });
      }
    } catch (e) {
      failures.push({ seed, printed: '', error: e instanceof Error ? e.message : String(e) });
    }
  }
  return failures;
}

/** Source-mutation oracle: splice corpus bytes at token boundaries; parse
 *  must throw LuauSyntaxError (or succeed) — never anything else. */
export function fuzzMutations(sources: Array<{ file: string; src: string }>, perFile: number, seedBase: number): FuzzResult['mutationFailures'] {
  const failures: FuzzResult['mutationFailures'] = [];
  for (const { file, src } of sources) {
    for (let i = 0; i < perFile; i++) {
      const rng = new Rng((seedBase + i * 7919 + file.length) >>> 0);
      try {
        const tokens = new Lexer(src).tokenize();
        if (tokens.length < 4) continue;
        const cutA = rng.int(0, tokens.length - 1);
        const cutB = rng.int(0, tokens.length - 1);
        const [lo, hi] = cutA < cutB ? [cutA, cutB] : [cutB, cutA];
        // splice: keep [0, lo) ++ (hi, end) — byte ranges from token loci
        const start = tokens[lo]!.location.start.offset;
        const end = hi + 1 < tokens.length ? tokens[hi + 1]!.location.start.offset : src.length;
        const mutated = src.slice(0, start) + src.slice(end);
        try {
          parse(mutated);
          // accepted mutants are fine (grammar-valid subsets)
        } catch (e) {
          if (!(e instanceof LuauSyntaxError)) {
            failures.push({ file, mutation: i, error: `non-syntax throw: ${e instanceof Error ? e.message : String(e)}` });
          }
        }
      } catch {
        // base lex failure: skip this source
        continue;
      }
    }
  }
  return failures;
}

// ---------------------------------------------------------------------------
// Standalone run mode: bun run tests/fuzz.ts [iterations] [seed]
// ---------------------------------------------------------------------------

if (import.meta.main) {
  const iterations = Number(process.argv[2] ?? 200);
  const seed = Number(process.argv[3] ?? 0xc0ffee);
  const t0 = Date.now();
  const failures = fuzzRoundtrip(iterations, seed);
  console.log(`fuzz roundtrip: ${iterations} iters, ${failures.length} failures, ${Date.now() - t0}ms`);
  for (const f of failures.slice(0, 10)) {
    console.log(`--- seed ${f.seed}: ${f.error ?? 'MISMATCH'}`);
    if (f.printed) console.log(f.printed.slice(0, 400));
  }
  if (failures.length > 0) process.exit(1);
}
