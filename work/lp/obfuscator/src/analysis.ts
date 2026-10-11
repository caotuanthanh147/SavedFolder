/**
 * Semantic analysis (doc.md §10.1-10.2 item 2) + constant-extraction plan
 * (item 6) — the M4 side of IR.md Interface B.
 *
 * Status: **v1, implemented against the REVIEWED contract** (IR.md v1
 * REVIEWED, glm6 2026-10-11, D-M5-19 — the review landed mid-session and
 * this code was re-fitted to its amendments before delivery):
 *
 *   C1  captures are consumed by Local-identity lookup, NEVER by array
 *       order — so entries exist ONLY at the parent-local boundary (the
 *       direct child of the owning unit). Transitive captures (grandchild
 *       reaching an ancestor local through an intermediate upvalue) carry
 *       NO decision: M5 emits kind-2 `upval` descriptors mechanically and
 *       the val/ref classification was made at the origin boundary.
 *   C4  the plan is a RAW-keyed SUPERSET: 's:'+bytes | 'n:'+raw |
 *       'i:'+raw. Distinct raws denoting the same pool value ('0x10' vs
 *       '16') stay DISTINCT entries; M5's compile-time (tag,value) dedup
 *       is the authority. No number parsing in the plan's key path.
 *   C3  `protect` is a NO-OP in v1 (BYTECODE-M5 §6.1: the pool is always
 *       AEAD; there is no plaintext pool). Reported per §2.2 classes for
 *       the day a split format lands; `inlineOk` is the operative flag.
 *   §2.1 (reviewed, tightened) `val` ⇔ the binding has EXACTLY ONE write
 *       in the entire program — its initializer — counted anywhere the
 *       name resolves to that binding, INCLUDING inside capturing
 *       closures (SETUPVAL is a write; glm6's verified counterexample).
 *       Loop control vars are written by the loop protocol — excluded.
 *       'assigned-before-capture-only' is RESERVED and never emitted in
 *       v1 (loop back-edge counterexample; needs CFG reachability).
 *   R3  (beyond the reviewed shape, flagged for glm6's ack) both maps are
 *       keyed by `FunctionUnit = FunctionExpr | Chunk` — a superset of
 *       the reviewed `Map<FunctionExpr, ...>`: every FunctionExpr-keyed
 *       lookup behaves identically, and the main chunk (M5's proto 0)
 *       gets its plan entry.
 *   R1  (finding for glm6, NOT an M4 change): compile.ts addNumber's key
 *       `u32[0] * 2^32 + u32[1]` computes a REAL number and collides for
 *       patterns needing > 53 significant bits (double rounding).
 *       Reproducible pair + evidence in tests/analysis.test.ts. With C4
 *       raw keys the plan itself never parses numbers, so the exactness
 *       concern lives entirely in M5's pool dedup.
 *   R2  (minor, same family): M5's LOADINT path folds -0 to +0 —
 *       unreachable from source text (`-` lexes as unary) but reachable
 *       from hand-built ASTs / future transforms. Guarded here with
 *       !Object.is(value, -0).
 *
 * Erasure model: type-level subtrees never execute (annotations,
 * TypeAliasStat, TypeFunctionStat — M5's compiler erases exactly these,
 * compile.ts 'TypeAlias'/'TypeFunction' → break). The analysis therefore
 * never walks into Type/TypePack nodes: a `typeof(expr)` annotation
 * cannot create a phantom capture or a pooled constant (D-M4-21).
 */

import type {
  AssignStat, Chunk, CompoundAssignStat, Expr, ForInStat, ForStat,
  FunctionExpr, IfElseExpr, IfStat, InterpStringExpr, Local, LocalStat,
  Stat, TableExpr,
} from './ast';

// ---------------------------------------------------------------------------
// Public interface (IR.md Interface B, v1)
// ---------------------------------------------------------------------------

/** A compilable function unit: a FunctionExpr, or the chunk root (M5's
 *  proto 0 — the main "function"). Local identity and capture semantics
 *  are identical for both. */
export type FunctionUnit = FunctionExpr | Chunk;

export interface CaptureInfo {
  /** The captured binding (identity! — Interface A pointer-compare). */
  readonly local: Local;
  /** `val` ONLY when provably immutable (never-assigned after binding). */
  readonly mode: 'ref' | 'val';
  /** v1 emits 'never-assigned' (⇒ val) or 'none' (⇒ ref).
   *  'assigned-before-capture-only' is reserved (open Q2). */
  readonly proof: 'never-assigned' | 'assigned-before-capture-only' | 'none';
}

export interface ConstEntry {
  /** Dedup key within the unit's pool (C4 pin: RAW-keyed superset —
   *    string → `s:` + bytes   (byte-string model)
   *    number → `n:` + raw      (raw source text; NO number parsing here)
   *    int    → `i:` + raw
   *  Distinct raws for the same pool value stay distinct entries; M5's
   *  compile-time (tag,value) dedup is the authority.) */
  readonly key: string;
  readonly kind: 'string' | 'number' | 'int';
  /** Byte-string for strings; raw source text for numbers/ints. */
  readonly value: string;
  /** SECURITY: route through the AEAD pool (IR.md §2.2 classes).
   *  C3: NO-OP in v1 — the pool is always AEAD; inlineOk is operative. */
  readonly protect: boolean;
  /** Stay out of the pool entirely (M5 LOADINT range; see R2).
  *  Precedence: inlineOk overrides protect. */
  readonly inlineOk: boolean;
}

export interface AnalysisResult {
  /** Per unit (every FunctionExpr + the Chunk): capture classification
   *  for every PARENT-LOCAL capture (C1: the val/ref decision boundary —
   *  the direct child of the owning unit). Transitive captures carry no
   *  decision and get no entries. Consumed by Local-identity lookup;
   *  array order is unspecified (first-use order is provided, free). */
  readonly captures: ReadonlyMap<FunctionUnit, readonly CaptureInfo[]>;
  /** Per unit: constant-pool plan for the unit's OWN body (nested function
   *  bodies excluded — they have their own entries), first-encounter
   *  order, raw-keyed (C4: distinct raws stay distinct entries; protect
   *  merges with OR when the same raw recurs in different classes). */
  readonly constPlan: ReadonlyMap<FunctionUnit, readonly ConstEntry[]>;
}

/** Run the analysis. Pure function of the AST: same tree in, same tables
 *  out; the tree is never mutated. Throws never (analysis is total over
 *  parser-produced ASTs; hand-built trees violating the Interface A
 *  binding contract may yield missing owners, which are skipped). */
export function analyze(chunk: Chunk): AnalysisResult {
  const analyzer = new Analyzer();
  analyzer.walkChunk(chunk);
  return analyzer.finish();
}

// ---------------------------------------------------------------------------
// Implementation
// ---------------------------------------------------------------------------

/** Strings shorter than this stay in the plain pool (IR.md §2.2). */
const PROTECT_MIN_BYTES = 8;
/** M5's LOADINT immediate range (compile.ts 'Number' case; D22). */
const LOADINT_MIN = -32768;
const LOADINT_MAX = 32767;

/** A number raw is "trivial" (reveals nothing about intent) iff it is a
 *  plain decimal integer/fraction. Hex/binary/exponent/underscore forms
 *  and dot-leading fractions are non-trivial → protect. */
const PLAIN_DECIMAL = /^\d+(\.\d+)?$/;

function numberInlineOk(value: number): boolean {
  return Number.isInteger(value)
    && value >= LOADINT_MIN && value <= LOADINT_MAX
    && !Object.is(value, -0); // R2: LOADINT folds -0 to +0
}

interface MutableConstEntry {
  key: string;
  kind: 'string' | 'number' | 'int';
  value: string;
  protect: boolean;
  inlineOk: boolean;
}

class Analyzer {
  /** Binding site → owning unit. */
  private readonly owner = new Map<Local, FunctionUnit>();
  /** Locals with ANY post-binding write (assign/compound/loop rebind). */
  private readonly assigned = new Set<Local>();
  /** Capture lists per unit, first-use order (locals, pre-classification). */
  private readonly rawCaptures = new Map<FunctionUnit, Local[]>();
  /** Pool plans per unit (key → entry, insertion = first encounter). */
  private readonly plans = new Map<FunctionUnit, Map<string, MutableConstEntry>>();
  /** Unit stack during the walk (stack[0] = the Chunk). */
  private readonly stack: FunctionUnit[] = [];

  private unit(): FunctionUnit {
    return this.stack[this.stack.length - 1]!;
  }

  private touch(unit: FunctionUnit): { captures: Local[]; plan: Map<string, MutableConstEntry> } {
    let captures = this.rawCaptures.get(unit);
    if (!captures) {
      captures = [];
      this.rawCaptures.set(unit, captures);
    }
    let plan = this.plans.get(unit);
    if (!plan) {
      plan = new Map();
      this.plans.set(unit, plan);
    }
    return { captures, plan };
  }

  /** Record a USE (read or write) of `local` from the current unit. Per
   *  C1, an entry is created ONLY at the parent-local boundary: in the
   *  unit that is the DIRECT CHILD of the owning unit (that is where M5's
   *  ref/val descriptor decision lives). The current unit gets the entry
   *  iff it is that direct child; deeper references are transitive (the
   *  chain carries them as kind-2 upval descriptors with no decision). */
  private use(local: Local): void {
    const o = this.owner.get(local);
    if (o === undefined) return; // binding in erased/type-level code — skip
    const i = this.stack.lastIndexOf(o);
    if (i < 0) return; // not an ancestor: Interface A contract violation
    // (hand-built tree) — skip defensively. i === stack.length - 1 means
    // the current unit OWNS the local — not a capture.
    if (i === this.stack.length - 1) return;
    const list = this.touch(this.stack[i + 1]!).captures;
    if (!list.includes(local)) list.push(local);
  }

  // -- constants -----------------------------------------------------------

  private addStringConst(value: string, indexPosition: boolean): void {
    const key = `s:${value}`;
    this.addEntry(key, 'string', value, value.length >= PROTECT_MIN_BYTES || indexPosition, false);
  }

  private addNumberConst(value: number, raw: string): void {
    // C4: raw key — no number parsing in the key path. `value` is only
    // consulted for the inlineOk classification (the lexer already
    // parsed it; hand-built ASTs carry it).
    this.addEntry(`n:${raw}`, 'number', raw, !PLAIN_DECIMAL.test(raw), numberInlineOk(value));
  }

  private addIntConst(value: bigint, raw: string): void {
    // Classified for the D-M5-10 unblock (Q4 ANSWERED: yes, classify):
    // ints do not compile in v1, so neither flag is load-bearing yet.
    void value;
    this.addEntry(`i:${raw}`, 'int', raw, false, false);
  }

  private addEntry(
    key: string, kind: 'string' | 'number' | 'int', value: string,
    protect: boolean, inlineOk: boolean,
  ): void {
    const plan = this.touch(this.unit()).plan;
    const existing = plan.get(key);
    if (existing) {
      // Same key ⇒ same value; protect merges with OR (a string that is
      // BOTH a plain literal and an index position is index-protected).
      existing.protect = existing.protect || protect;
      return;
    }
    plan.set(key, { key, kind, value, protect, inlineOk });
  }

  // -- walk ----------------------------------------------------------------

  walkChunk(chunk: Chunk): void {
    this.stack.push(chunk);
    this.touch(chunk); // uniform entries (main = proto 0)
    this.walkBlock(chunk.block);
    this.stack.pop();
  }

  private walkFunction(fn: FunctionExpr): void {
    this.stack.push(fn);
    this.touch(fn);
    if (fn.self) this.owner.set(fn.self, fn);
    for (const arg of fn.args) this.owner.set(arg, fn);
    // varargAnnotation / returnAnnotation: Type trees — erased (D-M4-21).
    this.walkBlock(fn.body);
    this.stack.pop();
  }

  private walkBlock(block: { readonly body: readonly Stat[] }): void {
    for (const stat of block.body) this.walkStat(stat);
  }

  private walkStat(stat: Stat): void {
    switch (stat.kind) {
      case 'Block':
        this.walkBlock(stat);
        break;
      case 'If':
        this.walkIf(stat);
        break;
      case 'While':
        this.walkExpr(stat.condition);
        this.walkBlock(stat.body);
        break;
      case 'Repeat':
        // Source order: body, then until (which sees body locals).
        this.walkBlock(stat.body);
        this.walkExpr(stat.condition);
        break;
      case 'Return':
        for (const e of stat.list) this.walkExpr(e);
        break;
      case 'ExprStat':
        this.walkExpr(stat.expr);
        break;
      case 'Local':
        this.walkLocalStat(stat);
        break;
      case 'For':
        this.walkForStat(stat);
        break;
      case 'ForIn':
        this.walkForInStat(stat);
        break;
      case 'Assign':
        this.walkAssignStat(stat);
        break;
      case 'CompoundAssign':
        this.walkCompoundAssign(stat);
        break;
      case 'FunctionStat':
        // `function a.b:c()` reads the base chain before the body runs.
        this.walkExpr(stat.name);
        this.walkFunction(stat.func);
        break;
      case 'LocalFunction':
        // Binds BEFORE its body (recursion — Interface A).
        this.owner.set(stat.name, this.unit());
        this.walkFunction(stat.func);
        break;
      case 'TypeAlias':
      case 'TypeFunction':
        break; // type-level, erased — matches M5 compile.ts
      case 'Break':
      case 'Continue':
        break;
    }
  }

  private walkIf(stat: IfStat): void {
    this.walkExpr(stat.condition);
    this.walkBlock(stat.thenbody);
    if (stat.elsebody) {
      if (stat.elsebody.kind === 'If') this.walkIf(stat.elsebody);
      else this.walkBlock(stat.elsebody);
    }
  }

  private walkLocalStat(stat: LocalStat): void {
    // Values first (bind-after-RHS — Interface A; reads may capture).
    for (const e of stat.values) this.walkExpr(e);
    for (const v of stat.vars) {
      this.owner.set(v, this.unit());
      // var.annotation: Type tree — erased.
    }
  }

  private walkForStat(stat: ForStat): void {
    this.walkExpr(stat.from);
    this.walkExpr(stat.to);
    if (stat.step) this.walkExpr(stat.step);
    // Control variable is rebound by the loop each iteration → assigned.
    this.owner.set(stat.var, this.unit());
    this.assigned.add(stat.var);
    this.walkBlock(stat.body);
  }

  private walkForInStat(stat: ForInStat): void {
    for (const e of stat.values) this.walkExpr(e);
    for (const v of stat.vars) {
      this.owner.set(v, this.unit());
      this.assigned.add(v);
    }
    this.walkBlock(stat.body);
  }

  private walkAssignStat(stat: AssignStat): void {
    // Lua multiple assignment: values evaluated first, then targets.
    for (const e of stat.values) this.walkExpr(e);
    for (const target of stat.vars) {
      if (target.kind === 'LocalExpr') {
        // A write through an outer local is still a capture (the closure
        // must hold the cell to assign it) — and it disqualifies `val`.
        this.assigned.add(target.local);
        this.use(target.local);
      } else {
        this.walkExpr(target); // table/global targets: reads of the base
      }
    }
  }

  private walkCompoundAssign(stat: CompoundAssignStat): void {
    // Read-modify-write: value first, then the target as a read+write.
    this.walkExpr(stat.value);
    if (stat.var.kind === 'LocalExpr') {
      this.assigned.add(stat.var.local);
      this.use(stat.var.local);
    } else {
      this.walkExpr(stat.var);
    }
  }

  private walkExpr(expr: Expr): void {
    switch (expr.kind) {
      case 'LocalExpr':
        this.use(expr.local);
        break;
      case 'Global':
      case 'Nil':
      case 'Bool':
      case 'Vararg': // function-local (M5 lowers per-frame); never a capture
        break;
      case 'Number':
        this.addNumberConst(expr.value, expr.raw);
        break;
      case 'Int':
        this.addIntConst(expr.value, expr.raw);
        break;
      case 'String':
        this.addStringConst(expr.value, false);
        break;
      case 'InterpString':
        this.walkInterpString(expr);
        break;
      case 'IndexName':
        this.walkExpr(expr.expr);
        // Member names route through the pool in M5 (GETTABLEKS/SETTABLEKS
        // and the method-call name — compile.ts addString on v.index):
        // always protect, regardless of length (IR.md §2.2).
        this.addStringConst(expr.index, true);
        break;
      case 'IndexExpr':
        this.walkExpr(expr.expr);
        this.walkExpr(expr.index);
        break;
      case 'Call':
        this.walkExpr(expr.func);
        for (const a of expr.args) this.walkExpr(a);
        break;
      case 'Function':
        this.walkFunction(expr);
        break;
      case 'Table':
        this.walkTable(expr);
        break;
      case 'Unary':
        this.walkExpr(expr.expr);
        break;
      case 'Binary':
        this.walkExpr(expr.left);
        this.walkExpr(expr.right);
        break;
      case 'TypeAssertion':
        // annotation: Type tree — erased.
        this.walkExpr(expr.expr);
        break;
      case 'IfElse':
        this.walkIfElse(expr);
        break;
      case 'Group':
        this.walkExpr(expr.expr);
        break;
      case 'Instantiate':
        // typeArguments: Type trees — erased.
        this.walkExpr(expr.expr);
        break;
    }
  }

  private walkInterpString(expr: InterpStringExpr): void {
    // Literal parts are runtime constants (M5 derives its format string
    // from them — D-M5-8; the derived string is M5's to pool).
    for (const part of expr.strings) this.addStringConst(part, false);
    for (const e of expr.expressions) this.walkExpr(e);
  }

  private walkTable(expr: TableExpr): void {
    for (const item of expr.items) {
      if (item.key) this.walkExpr(item.key); // Record keys are StringExprs
      this.walkExpr(item.value);
    }
  }

  private walkIfElse(expr: IfElseExpr): void {
    // The binding executes at condition evaluation, before the branches —
    // a single write, so a capture of it can be `val`.
    this.walkExpr(expr.condition);
    if (expr.conditionLocal) this.owner.set(expr.conditionLocal, this.unit());
    this.walkExpr(expr.trueExpr);
    this.walkExpr(expr.falseExpr);
  }

  // -- classification --------------------------------------------------------

  finish(): AnalysisResult {
    const captures = new Map<FunctionUnit, readonly CaptureInfo[]>();
    for (const [unit, locals] of this.rawCaptures) {
      captures.set(unit, locals.map((local) => this.classify(local)));
    }
    const constPlan = new Map<FunctionUnit, readonly ConstEntry[]>();
    for (const [unit, plan] of this.plans) {
      constPlan.set(unit, [...plan.values()]);
    }
    return { captures, constPlan };
  }

  private classify(local: Local): CaptureInfo {
    if (this.assigned.has(local)) {
      return { local, mode: 'ref', proof: 'none' };
    }
    return { local, mode: 'val', proof: 'never-assigned' };
  }
}
