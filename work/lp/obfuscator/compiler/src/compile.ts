/**
 * M5 bytecode compiler: M4 AST -> canonical register bytecode.
 *
 * Input: the AST node set delivered by M4 (obfuscator/src/ast.ts,
 * Public 1ca1dbf). Output: flat Proto tree + per-function constant pools,
 * consumed by container.ts (§5.9 packing) and the reference interpreter.
 *
 * Semantics sources (RESEARCH-M5): Lua 5.1 manual + Luau additions (continue,
 * //, interp strings via string.format %*, generalized iteration). Clean-room:
 * opcode set/numbering/format are this project's own.
 *
 * Register model: locals occupy registers [0, locals.length) contiguously
 * (loop control slots are hidden locals — Lua 5.1 lparser precedent); temps
 * allocate above via reserve()/release(). `top` (runtime) extends an open
 * multret window; the consuming open instruction (CALL/RETURN/SETLIST with
 * the 0-count convention) closes it.
 */

import { Op } from './opcode';
import type {
  AssignStat, BinaryExpr, BinaryOp, Block, CallExpr, Chunk, CompoundAssignStat,
  Expr, ExprStat, ForInStat, ForStat, FunctionExpr, FunctionStat, IfElseExpr,
  IfStat, InterpStringExpr, Local, LocalFunctionStat, LocalStat, RepeatStat,
  ReturnStat, Stat, TableExpr, UnaryOp, WhileStat,
} from '../../src/ast';

/** Compile error (compiler-side only; containers carry no debug info,
 *  DECISIONS-M5 D-M5-11). */
export class CompileError extends Error {
  constructor(message: string, readonly line = 0, readonly column = 0) {
    super(`compile error at ${line}:${column}: ${message}`);
  }
}

/** Per-function constant pool entry. */
export type Const =
  | { readonly kind: 'bool'; readonly b: boolean }
  | { readonly kind: 'num'; readonly n: number; readonly bits: number }
  | { readonly kind: 'str'; readonly s: string };

/** Upvalue descriptor: where the child closure's upvalue comes from in the
 *  PARENT frame. VAL reserved (unused v1 — D-M5-5). */
export type UpvalDesc =
  | { readonly kind: 'val'; readonly reg: number }
  | { readonly kind: 'ref'; readonly reg: number }
  | { readonly kind: 'upval'; readonly idx: number };

/** Compiled function prototype (canonical opcodes; words assembled later). */
export interface Proto {
  readonly numParams: number;
  readonly isVararg: boolean;
  maxRegs: number;
  /** Instructions as [op, a, b, c, d, aux]; encode via opcode.ts. */
  readonly code: InsnOut[];
  readonly upvals: UpvalDesc[];
  readonly consts: Const[];
  /** Flat child proto indices in NEWCLOSURE emission order. */
  readonly children: number[];
}

export interface InsnOut {
  op: number;
  a: number;
  b: number;
  c: number;
  d: number;
  aux: number;
}

/** Compile limits (DECISIONS-M5 D-M5-15, Luau documented limits). */
export const LIMITS = {
  maxLocals: 200,
  maxUpvals: 200,
  maxRegs: 255, // registers 0..254
  maxConsts: 1 << 23,
  d16Max: 32767,
  kIndex8Max: 255,
} as const;

/** SETLIST flush granularity (D-M5-12). */
const FIELDS_PER_FLUSH = 50;

export interface CompileResult {
  /** Protos in creation (depth-first emission) order; index 0 = main chunk. */
  readonly protos: readonly Proto[];
}

// ---------------------------------------------------------------------------
// Scope bookkeeping
// ---------------------------------------------------------------------------

interface LocalSlot {
  /** null = hidden loop-control local (never name-resolvable). */
  readonly local: Local | null;
  readonly name: string | null;
  readonly reg: number;
}

interface Scope {
  readonly localBase: number;
  capturedHere: boolean;
}

interface LoopCtx {
  readonly breakJumps: number[];
  readonly continueJumps: number[];
  /** scopes.length at loop entry: scopes above this belong to the loop body. */
  readonly scopeAtEntry: number;
}

interface FnCtx {
  readonly parent: FnCtx | null;
  readonly proto: Proto;
  readonly protoIndex: number;
  readonly scopes: Scope[];
  readonly locals: LocalSlot[];
  /** This function's OWN upvalues: name -> descriptor (index = upval id). */
  readonly upvals: { name: string; desc: UpvalDesc }[];
  readonly loops: LoopCtx[];
  freeReg: number;
  readonly constMap: Map<string, number>;
}

type ResolvedName =
  | { kind: 'local'; reg: number }
  | { kind: 'upval'; idx: number }
  | { kind: 'global' };

// ---------------------------------------------------------------------------
// Compiler
// ---------------------------------------------------------------------------

export function compileProgram(chunk: Chunk): CompileResult {
  const c = new Compiler();
  c.compileFunction(null, chunk.block, { self: null, args: [], vararg: true });
  return { protos: c.protos };
}

class Compiler {
  readonly protos: Proto[] = [];

  /** Compile one function; pushes its proto; returns its context. */
  compileFunction(parent: FnCtx | null, body: Block, params: FnParams): FnCtx {
    const proto: Proto = {
      numParams: (params.self ? 1 : 0) + params.args.length,
      isVararg: params.vararg,
      maxRegs: 2,
      code: [],
      upvals: [],
      consts: [],
      children: [],
    };
    const ctx: FnCtx = {
      parent,
      proto,
      protoIndex: this.protos.length,
      scopes: [],
      locals: [],
      upvals: [],
      loops: [],
      freeReg: 0,
      constMap: new Map(),
    };
    this.protos.push(proto);
    this.openScope(ctx);
    if (params.self) this.bindLocal(ctx, params.self);
    for (const a of params.args) this.bindLocal(ctx, a);
    this.compileBlock(ctx, body);
    // Implicit `return` at end of body.
    this.emit(ctx, { op: Op.LOADNIL, a: ctx.freeReg, b: 0, c: 0, d: 0, aux: 0 });
    this.emit(ctx, { op: Op.RETURN, a: ctx.freeReg, b: 2, c: 0, d: 0, aux: 0 });
    // Root scope pops without a close: frame teardown closes open cells
    // (RETURN precedes any close emission; unreachable code is not emitted).
    ctx.scopes.pop();
    return ctx;
  }

  // --- emission ----------------------------------------------------------

  emit(ctx: FnCtx, insn: InsnOut): number {
    if (ctx.proto.code.length >= LIMITS.maxConsts) {
      throw new CompileError('function too large (instruction limit)');
    }
    ctx.proto.code.push(insn);
    return ctx.proto.code.length - 1;
  }

  reserve(ctx: FnCtx, n: number): number {
    const base = ctx.freeReg;
    if (ctx.freeReg + n > LIMITS.maxRegs) {
      throw new CompileError(`register overflow (limit ${LIMITS.maxRegs - 1})`);
    }
    ctx.freeReg += n;
    if (ctx.freeReg > ctx.proto.maxRegs) ctx.proto.maxRegs = ctx.freeReg;
    return base;
  }

  release(ctx: FnCtx, n: number): void {
    ctx.freeReg -= n;
    if (ctx.freeReg < ctx.locals.length) {
      throw new CompileError('internal: register underflow below locals');
    }
  }

  // --- scopes ------------------------------------------------------------

  openScope(ctx: FnCtx): void {
    ctx.scopes.push({ localBase: ctx.locals.length, capturedHere: false });
  }

  closeScope(ctx: FnCtx, emitClose: boolean): void {
    const scope = ctx.scopes.pop();
    if (!scope) throw new CompileError('internal: scope underflow');
    ctx.locals.length = scope.localBase;
    ctx.freeReg = scope.localBase;
    if (emitClose && scope.capturedHere) {
      this.emit(ctx, { op: Op.CLOSEUPVALS, a: scope.localBase, b: 0, c: 0, d: 0, aux: 0 });
    }
  }

  bindLocal(ctx: FnCtx, local: Local): number {
    return this.bindSlot(ctx, local, local.name);
  }

  bindHiddenLocal(ctx: FnCtx): number {
    return this.bindSlot(ctx, null, null);
  }

  private bindSlot(ctx: FnCtx, local: Local | null, name: string | null): number {
    if (ctx.locals.length >= LIMITS.maxLocals) {
      throw new CompileError('too many locals (limit 200)');
    }
    const reg = ctx.locals.length;
    ctx.locals.push({ local, name, reg });
    ctx.freeReg = ctx.locals.length;
    if (ctx.freeReg > ctx.proto.maxRegs) ctx.proto.maxRegs = ctx.freeReg;
    return reg;
  }

  findLocal(ctx: FnCtx, name: string): LocalSlot | undefined {
    for (let i = ctx.locals.length - 1; i >= 0; i--) {
      if (ctx.locals[i].name === name) return ctx.locals[i];
    }
    return undefined;
  }

  /** Resolve `name` from ctx's perspective (locals, own upvals, then
   *  recursive parent resolution which also CREATES upvalue descriptors —
   *  mirrored into proto.upvals for container serialization). */
  resolveName(ctx: FnCtx, name: string): ResolvedName {
    const slot = this.findLocal(ctx, name);
    if (slot) return { kind: 'local', reg: slot.reg };
    const own = ctx.upvals.findIndex((u) => u.name === name);
    if (own >= 0) return { kind: 'upval', idx: own };
    if (ctx.parent) {
      const fromParent = this.resolveNameForChild(ctx.parent, name);
      if (fromParent) {
        if (ctx.upvals.length >= LIMITS.maxUpvals) {
          throw new CompileError('too many upvalues (limit 200)');
        }
        ctx.upvals.push({ name, desc: fromParent });
        ctx.proto.upvals.push(fromParent);
        return { kind: 'upval', idx: ctx.upvals.length - 1 };
      }
    }
    return { kind: 'global' };
  }

  /** Resolve `name` as an upvalue source for a CHILD of `parent`:
   *  local in parent -> ref descriptor (marks captured);
   *  deeper -> parent first acquires its own upvalue, child references it. */
  private resolveNameForChild(parent: FnCtx, name: string): UpvalDesc | null {
    const slot = this.findLocal(parent, name);
    if (slot) {
      // Mark the slot's own scope as capturing.
      for (let s = parent.scopes.length - 1; s >= 0; s--) {
        if (slot.reg >= parent.scopes[s].localBase) {
          parent.scopes[s].capturedHere = true;
          break;
        }
      }
      return { kind: 'ref', reg: slot.reg };
    }
    const upIdx = parent.upvals.findIndex((u) => u.name === name);
    if (upIdx >= 0) return { kind: 'upval', idx: upIdx };
    if (parent.parent) {
      const up = this.resolveNameForChild(parent.parent, name);
      if (up) {
        // The parent must itself hold this as an upvalue; the child then
        // references the parent's (new) upvalue slot.
        if (parent.upvals.length >= LIMITS.maxUpvals) {
          throw new CompileError('too many upvalues (limit 200)');
        }
        parent.upvals.push({ name, desc: up });
        parent.proto.upvals.push(up);
        return { kind: 'upval', idx: parent.upvals.length - 1 };
      }
    }
    return null;
  }

  // --- constants ---------------------------------------------------------

  addConst(ctx: FnCtx, c: Const): number {
    let key: string;
    switch (c.kind) {
      case 'bool': key = `b:${c.b ? 1 : 0}`; break;
      case 'num': key = `n:${c.bits}`; break;
      case 'str': key = `s:${c.s.length}:${c.s}`; break;
    }
    const existing = ctx.constMap.get(key);
    if (existing !== undefined) return existing;
    const idx = ctx.proto.consts.length;
    if (idx >= LIMITS.maxConsts) throw new CompileError('too many constants (2^23 limit)');
    ctx.proto.consts.push(c);
    ctx.constMap.set(key, idx);
    return idx;
  }

  addString(ctx: FnCtx, s: string): number {
    return this.addConst(ctx, { kind: 'str', s });
  }

  addNumber(ctx: FnCtx, n: number): number {
    const f64 = new Float64Array(1);
    f64[0] = n;
    const u32 = new Uint32Array(f64.buffer);
    return this.addConst(ctx, {
      kind: 'num', n, bits: u32[0] * 0x100000000 + u32[1],
    });
  }

  loadK(ctx: FnCtx, target: number, kIdx: number): void {
    if (kIdx <= LIMITS.d16Max) {
      this.emit(ctx, { op: Op.LOADK, a: target, b: 0, c: 0, d: kIdx, aux: 0 });
    } else {
      this.emit(ctx, { op: Op.LOADKX, a: target, b: 0, c: 0, d: 0, aux: kIdx });
    }
  }

  // --- jumps -------------------------------------------------------------

  /** Jump offset convention (Luau-style): target = pc_of_next_instruction
   *  + D (D = 0 is the fall-through). All patched unconditional jumps are
   *  the E-encoded JUMP (24-bit, full range). */
  emitJumpPlaceholder(ctx: FnCtx): number {
    return this.emit(ctx, { op: Op.JUMP, a: 0, b: 0, c: 0, d: 0x400000, aux: 0 });
  }

  patchJump(ctx: FnCtx, pc: number, target: number): void {
    const insn = ctx.proto.code[pc];
    if (insn.op !== Op.JUMP) throw new CompileError('internal: patching non-JUMP');
    const off = target - (pc + 1);
    if (off < -(1 << 23) || off >= 1 << 23) throw new CompileError('jump offset out of 24-bit range');
    insn.d = off;
  }

  /** Patch an AD-shaped loop-prep offset (FORNPREP/FORGPREP, 16-bit). */
  patchPrep(ctx: FnCtx, pc: number, target: number): void {
    const insn = ctx.proto.code[pc];
    const off = target - (pc + 1);
    if (off < -LIMITS.d16Max || off > LIMITS.d16Max) {
      throw new CompileError('loop too large for 16-bit prep offset');
    }
    insn.d = off;
  }

  /** Conditional forward jump (trampoline, D-M5-2 note):
   *  [cond A, D=1][JUMP placeholder] — when NOT taken, execution falls into
   *  the JUMP; when taken (D=1), it skips exactly the 1-word JUMP.
   *  Returns the JUMP pc. */
  emitCondJumpForward(ctx: FnCtx, condOp: number, a: number, aux: number): number {
    this.emit(ctx, { op: condOp, a, b: 0, c: 0, d: 1, aux: aux >>> 0 });
    return this.emitJumpPlaceholder(ctx);
  }

  /** Backward conditional jump (loop back-edges). */
  emitCondJumpBackward(ctx: FnCtx, condOp: number, a: number, aux: number, target: number): void {
    const here = ctx.proto.code.length;
    const off = target - (here + 1);
    if (off < -LIMITS.d16Max || off > LIMITS.d16Max) {
      throw new CompileError('loop too large for 16-bit conditional back-edge');
    }
    this.emit(ctx, { op: condOp, a, b: 0, c: 0, d: off, aux: aux >>> 0 });
  }

  // --- statements --------------------------------------------------------

  compileBlock(ctx: FnCtx, block: Block): void {
    this.openScope(ctx);
    for (const stat of block.body) this.compileStat(ctx, stat);
    this.closeScope(ctx, true);
  }

  compileStat(ctx: FnCtx, stat: Stat): void {
    switch (stat.kind) {
      case 'Block': this.compileBlock(ctx, stat); break;
      case 'If': this.compileIf(ctx, stat); break;
      case 'While': this.compileWhile(ctx, stat); break;
      case 'Repeat': this.compileRepeat(ctx, stat); break;
      case 'Break': this.compileBreak(ctx); break;
      case 'Continue': this.compileContinue(ctx); break;
      case 'Return': this.compileReturn(ctx, stat); break;
      case 'ExprStat': this.compileExprStat(ctx, stat); break;
      case 'Local': this.compileLocalStat(ctx, stat); break;
      case 'For': this.compileForStat(ctx, stat); break;
      case 'ForIn': this.compileForInStat(ctx, stat); break;
      case 'Assign': this.compileAssignStat(ctx, stat); break;
      case 'CompoundAssign': this.compileCompoundAssign(ctx, stat); break;
      case 'FunctionStat': this.compileFunctionStat(ctx, stat); break;
      case 'LocalFunction': this.compileLocalFunction(ctx, stat); break;
      case 'TypeAlias': break; // type-level, erased
      case 'TypeFunction': break; // type-level, erased
      default: {
        const never: never = stat;
        void never;
        throw new CompileError(`unsupported statement kind ${(stat as Stat).kind}`);
      }
    }
  }

  compileIf(ctx: FnCtx, stat: IfStat): void {
    const endJumps: number[] = [];
    let node: IfStat | null = stat;
    while (node) {
      const r = this.reserve(ctx, 1);
      this.compileExpr(ctx, node.condition, r, 'single');
      // Trampoline: [JUMPIF r, D=1][JUMP -> else]: truthy falls into the
      // then-body; falsy takes the JUMP to the else position.
      const skip = this.emitCondJumpForward(ctx, Op.JUMPIF, r, 0);
      this.release(ctx, 1);
      this.compileBlock(ctx, node.thenbody);
      endJumps.push(this.emitJumpPlaceholder(ctx));
      this.patchJump(ctx, skip, ctx.proto.code.length);
      const elseNode: Block | IfStat | null = node.elsebody;
      if (elseNode && elseNode.kind === 'If') {
        node = elseNode;
      } else if (elseNode) {
        this.compileBlock(ctx, elseNode);
        node = null;
      } else {
        node = null;
      }
    }
    const endTarget = ctx.proto.code.length;
    for (const pc of endJumps) this.patchJump(ctx, pc, endTarget);
  }

  compileWhile(ctx: FnCtx, stat: WhileStat): void {
    this.openScope(ctx);
    const headPc = ctx.proto.code.length;
    const r = this.reserve(ctx, 1);
    this.compileExpr(ctx, stat.condition, r, 'single');
    // Trampoline: [JUMPIF r, D=1][JUMP -> end]: truthy falls into the body;
    // falsy takes the JUMP out of the loop.
    const exitJump = this.emitCondJumpForward(ctx, Op.JUMPIF, r, 0);
    this.release(ctx, 1);
    const loop: LoopCtx = {
      breakJumps: [], continueJumps: [],
      scopeAtEntry: ctx.scopes.length,
    };
    ctx.loops.push(loop);
    this.compileBlock(ctx, stat.body);
    ctx.loops.pop();
    const backJump = this.emitJumpPlaceholder(ctx);
    this.patchJump(ctx, backJump, headPc);
    for (const pc of loop.continueJumps) this.patchJump(ctx, pc, ctx.proto.code.length - 1);
    const endTarget = ctx.proto.code.length;
    this.patchJump(ctx, exitJump, endTarget);
    for (const pc of loop.breakJumps) this.patchJump(ctx, pc, endTarget);
    this.closeScope(ctx, true);
  }

  compileRepeat(ctx: FnCtx, stat: RepeatStat): void {
    this.openScope(ctx);
    const loop: LoopCtx = {
      breakJumps: [], continueJumps: [],
      scopeAtEntry: ctx.scopes.length,
    };
    ctx.loops.push(loop);
    // Body scope stays open while the condition compiles: `until` sees the
    // body's locals (Lua 5.1 manual §2.4.4; M4 ast.ts note).
    this.openScope(ctx);
    const bodyScope = ctx.scopes[ctx.scopes.length - 1];
    const bodyBase = bodyScope.localBase;
    const bodyStart = ctx.proto.code.length;
    for (const s of stat.body.body) this.compileStat(ctx, s);
    const condPc = ctx.proto.code.length;
    for (const pc of loop.continueJumps) this.patchJump(ctx, pc, condPc);
    const r = this.reserve(ctx, 1);
    this.compileExpr(ctx, stat.condition, r, 'single');
    if (bodyScope.capturedHere) {
      // Lua 5.1 lparser.c repeatstat L1022-1031 (source-verified): with
      // captures, the continuing path closes upvalues EVERY iteration and
      // the exit path closes via the body scope's natural close.
      // [JUMPIFNOT r, D=1][JUMP -> exitClose] : falsy (condition unmet)
      // skips the JUMP to the CLOSE + back-edge; truthy takes the JUMP to
      // the EXIT close. The exit target is the CLOSEUPVALS the body
      // scope's close emits NEXT — jumping to endTarget instead would
      // skip the close and leak the last iteration's open cells into
      // register reuse (differential harness: stale captured values).
      const exitJump = this.emitCondJumpForward(ctx, Op.JUMPIFNOT, r, 0);
      this.release(ctx, 1);
      this.emit(ctx, { op: Op.CLOSEUPVALS, a: bodyBase, b: 0, c: 0, d: 0, aux: 0 });
      const back = this.emitJumpPlaceholder(ctx);
      this.patchJump(ctx, back, bodyStart);
      const exitClosePc = ctx.proto.code.length; // closeScope emits CLOSEUPVALS here
      this.closeScope(ctx, true); // exit path: captured body locals close here
      ctx.loops.pop();
      const endTarget = ctx.proto.code.length;
      this.patchJump(ctx, exitJump, exitClosePc);
      for (const pc of loop.breakJumps) this.patchJump(ctx, pc, endTarget);
    } else {
      this.emitCondJumpBackward(ctx, Op.JUMPIFNOT, r, 0, bodyStart);
      this.release(ctx, 1);
      this.closeScope(ctx, true);
      ctx.loops.pop();
      const endTarget = ctx.proto.code.length;
      for (const pc of loop.breakJumps) this.patchJump(ctx, pc, endTarget);
    }
    this.closeScope(ctx, true);
  }

  /** Register floors needing CLOSEUPVALS before break/continue (innermost
   *  first): scopes opened inside the loop with captures. */
  private loopCloseFloors(ctx: FnCtx, loop: LoopCtx): number[] {
    const floors: number[] = [];
    for (let s = ctx.scopes.length - 1; s >= loop.scopeAtEntry; s--) {
      if (ctx.scopes[s].capturedHere) floors.push(ctx.scopes[s].localBase);
    }
    return floors;
  }

  compileBreak(ctx: FnCtx): void {
    const loop = ctx.loops[ctx.loops.length - 1];
    if (!loop) throw new CompileError('break outside a loop');
    for (const floor of this.loopCloseFloors(ctx, loop)) {
      this.emit(ctx, { op: Op.CLOSEUPVALS, a: floor, b: 0, c: 0, d: 0, aux: 0 });
    }
    loop.breakJumps.push(this.emitJumpPlaceholder(ctx));
  }

  compileContinue(ctx: FnCtx): void {
    const loop = ctx.loops[ctx.loops.length - 1];
    if (!loop) throw new CompileError('continue outside a loop');
    for (const floor of this.loopCloseFloors(ctx, loop)) {
      this.emit(ctx, { op: Op.CLOSEUPVALS, a: floor, b: 0, c: 0, d: 0, aux: 0 });
    }
    loop.continueJumps.push(this.emitJumpPlaceholder(ctx));
  }

  compileReturn(ctx: FnCtx, stat: ReturnStat): void {
    const base = ctx.freeReg;
    const n = this.compileExprList(ctx, stat.list, base, true);
    if (n < 0) {
      this.emit(ctx, { op: Op.RETURN, a: base, b: 0, c: 0, d: 0, aux: 0 });
    } else {
      this.emit(ctx, { op: Op.RETURN, a: base, b: n + 1, c: 0, d: 0, aux: 0 });
      this.release(ctx, n);
    }
  }

  compileExprStat(ctx: FnCtx, stat: ExprStat): void {
    if (stat.expr.kind !== 'Call') {
      // M4's grammar enforces call-only expression statements.
      throw new CompileError('expression statement must be a call');
    }
    const base = this.reserve(ctx, 1);
    this.compileCall(ctx, stat.expr, base, -1); // -1 = zero fixed results
    this.release(ctx, 1);
  }

  compileLocalStat(ctx: FnCtx, stat: LocalStat): void {
    const nVars = stat.vars.length;
    const nVals = stat.values.length;
    if (nVals === 0) {
      for (const v of stat.vars) this.bindLocal(ctx, v);
      return;
    }
    const base = ctx.freeReg;
    const lastIsMultret = isMultretExpr(stat.values[nVals - 1]);
    if (lastIsMultret && nVals <= nVars) {
      // Adjust the multret producer to exactly nVars results.
      this.compileExprListMultretAdjusted(ctx, stat.values, base, nVars);
      for (const v of stat.vars) this.bindLocal(ctx, v);
      return;
    }
    if (nVals > nVars) {
      // Truncate: compile only the first nVars values (all single).
      this.compileExprList(ctx, stat.values.slice(0, nVars), base, false);
      for (const v of stat.vars) this.bindLocal(ctx, v);
      return;
    }
    const n = this.compileExprList(ctx, stat.values, base, false);
    if (n < nVars) {
      this.emit(ctx, { op: Op.LOADNIL, a: base + n, b: 0, c: 0, d: 0, aux: 0 });
    }
    for (const v of stat.vars) this.bindLocal(ctx, v);
  }

  compileForStat(ctx: FnCtx, stat: ForStat): void {
    this.openScope(ctx); // hidden control scope: [limit, step, index]
    const a = ctx.freeReg;
    // Init window (5.1 exp1/exp2nextreg frontier discipline): expressions
    // evaluate in SOURCE order (from, to, step — side effects preserved)
    // and land on the Luau control layout [limit, step, index, var]
    // (D-M5-6); hidden locals bind AFTER init.
    this.compileExprWindow(ctx, stat.from, a + 2); // index
    this.compileExprWindow(ctx, stat.to, a); // limit
    if (stat.step) {
      this.compileExprWindow(ctx, stat.step, a + 1); // step
    } else {
      this.emit(ctx, { op: Op.LOADINT, a: a + 1, b: 0, c: 0, d: 1, aux: 0 });
    }
    ctx.freeReg = a;
    this.bindHiddenLocal(ctx); // limit
    this.bindHiddenLocal(ctx); // step
    this.bindHiddenLocal(ctx); // index
    ctx.freeReg = a + 3;
    if (ctx.freeReg > ctx.proto.maxRegs) ctx.proto.maxRegs = ctx.freeReg;
    const loop: LoopCtx = { breakJumps: [], continueJumps: [], scopeAtEntry: ctx.scopes.length };
    ctx.loops.push(loop);
    const prepPc = this.emit(ctx, { op: Op.FORNPREP, a, b: 0, c: 0, d: 0x400000, aux: 0 });
    // Body scope: visible loop variable at R(a+3).
    this.openScope(ctx);
    this.bindLocal(ctx, stat.var);
    for (const s of stat.body.body) this.compileStat(ctx, s);
    this.closeScope(ctx, true); // captured loop var closes per iteration
    const loopPc = ctx.proto.code.length;
    this.emit(ctx, { op: Op.FORNLOOP, a, b: 0, c: 0, d: prepPc - loopPc, aux: 0 });
    for (const pc of loop.continueJumps) this.patchJump(ctx, pc, loopPc);
    ctx.loops.pop();
    const endTarget = ctx.proto.code.length;
    this.patchPrep(ctx, prepPc, endTarget);
    for (const pc of loop.breakJumps) this.patchJump(ctx, pc, endTarget);
    this.closeScope(ctx, true);
  }

  /** Compile an expression into register `target` with the allocation
   *  frontier AT the target (5.1 exp2nextreg style): the expression may
   *  use target..above as its window; the frontier advances past target. */
  compileExprWindow(ctx: FnCtx, e: Expr, target: number): void {
    ctx.freeReg = target;
    this.compileExpr(ctx, e, target, 'single');
    ctx.freeReg = target + 1;
    if (ctx.freeReg > ctx.proto.maxRegs) ctx.proto.maxRegs = ctx.freeReg;
  }

  compileForInStat(ctx: FnCtx, stat: ForInStat): void {
    const nVars = stat.vars.length;
    this.openScope(ctx); // hidden control scope: [generator, state, index]
    const a = ctx.freeReg;
    // Init window (5.1 frontier discipline; multret tail adjusted to 3).
    ctx.freeReg = a;
    const vals = stat.values;
    const lastIsMultret = vals.length > 0 && isMultretExpr(vals[vals.length - 1]);
    if (lastIsMultret && vals.length <= 3) {
      let cursor = a;
      for (let i = 0; i < vals.length - 1; i++) {
        this.compileExprWindow(ctx, vals[i], cursor);
        cursor++;
      }
      const last = vals[vals.length - 1];
      const nTake = Math.max(1, 3 - (vals.length - 1));
      if (last.kind === 'Call') {
        this.compileCall(ctx, last, cursor, nTake);
      } else {
        this.emit(ctx, { op: Op.GETVARARGS, a: cursor, b: nTake + 1, c: 0, d: 0, aux: 0 });
      }
    } else {
      const nFixed = Math.min(vals.length, 3);
      for (let i = 0; i < nFixed; i++) {
        this.compileExprWindow(ctx, vals[i], a + i);
      }
      for (let i = vals.length; i < 3; i++) {
        this.emit(ctx, { op: Op.LOADNIL, a: a + i, b: 0, c: 0, d: 0, aux: 0 });
      }
    }
    ctx.freeReg = a;
    this.bindHiddenLocal(ctx);
    this.bindHiddenLocal(ctx);
    this.bindHiddenLocal(ctx);
    ctx.freeReg = a + 3;
    if (ctx.freeReg > ctx.proto.maxRegs) ctx.proto.maxRegs = ctx.freeReg;
    const loop: LoopCtx = { breakJumps: [], continueJumps: [], scopeAtEntry: ctx.scopes.length };
    ctx.loops.push(loop);
    const prepPc = this.emit(ctx, { op: Op.FORGPREP, a, b: 0, c: 0, d: 0x400000, aux: 0 });
    this.openScope(ctx); // body scope: visible variables at R(a+3)..
    for (const v of stat.vars) this.bindLocal(ctx, v);
    for (const s of stat.body.body) this.compileStat(ctx, s);
    this.closeScope(ctx, true);
    const loopPc = ctx.proto.code.length;
    this.emit(ctx, { op: Op.FORGLOOP, a, b: 0, c: 0, d: prepPc - loopPc, aux: nVars });
    for (const pc of loop.continueJumps) this.patchJump(ctx, pc, loopPc);
    ctx.loops.pop();
    // FORGPREP jumps TO the FORGLOOP back-edge (first generator call);
    // loop exit happens inside FORGLOOP when the first variable is nil.
    this.patchPrep(ctx, prepPc, loopPc);
    for (const pc of loop.breakJumps) this.patchJump(ctx, pc, ctx.proto.code.length);
    this.closeScope(ctx, true);
  }

  // --- assignment ---------------------------------------------------------

  compileAssignStat(ctx: FnCtx, stat: AssignStat): void {
    const nVars = stat.vars.length;
    const nVals = stat.values.length;
    // 1. Target prefixes first (Lua 5.1 manual §2.4.3: `i, a[i] = i+1, 20`
    //    stores into a[3]).
    const prefixes: { tableReg: number; keyReg: number; keyConstIdx: number }[] = [];
    let prefixTemps = 0;
    for (const v of stat.vars) {
      if (v.kind === 'IndexExpr') {
        const t = this.reserve(ctx, 1);
        this.compileExpr(ctx, v.expr, t, 'single');
        const k = this.reserve(ctx, 1);
        this.compileExpr(ctx, v.index, k, 'single');
        prefixes.push({ tableReg: t, keyReg: k, keyConstIdx: -1 });
        prefixTemps += 2;
      } else if (v.kind === 'IndexName') {
        const t = this.reserve(ctx, 1);
        this.compileExpr(ctx, v.expr, t, 'single');
        prefixes.push({ tableReg: t, keyReg: -1, keyConstIdx: this.addString(ctx, v.index) });
        prefixTemps += 1;
      } else if (v.kind !== 'Global' && v.kind !== 'LocalExpr') {
        throw new CompileError('cannot assign to this expression');
      } else {
        prefixes.push({ tableReg: -1, keyReg: -1, keyConstIdx: -1 });
      }
    }
    // 2. Values (adjusted to nVars; multret when tail allows).
    const valueBase = ctx.freeReg;
    const lastIsMultret = nVals > 0 && isMultretExpr(stat.values[nVals - 1]);
    let nValues: number;
    if (nVals === 0) {
      nValues = 0;
    } else if (lastIsMultret && nVals <= nVars) {
      nValues = this.compileExprListMultretAdjusted(ctx, stat.values, valueBase, nVars);
    } else if (nVals > nVars) {
      nValues = this.compileExprList(ctx, stat.values.slice(0, nVars), valueBase, false);
    } else {
      nValues = this.compileExprList(ctx, stat.values, valueBase, false);
    }
    // Pad missing values with nil.
    for (let i = nValues; i < nVars; i++) {
      this.emit(ctx, { op: Op.LOADNIL, a: valueBase + i, b: 0, c: 0, d: 0, aux: 0 });
    }
    // 3. Stores, left-to-right.
    for (let i = 0; i < nVars; i++) {
      const v = stat.vars[i];
      const src = valueBase + i;
      if (v.kind === 'Global') {
        this.emit(ctx, { op: Op.SETGLOBAL, a: src, b: 0, c: 0, d: this.addString(ctx, v.name), aux: 0 });
      } else if (v.kind === 'LocalExpr') {
        const res = this.resolveName(ctx, v.local.name);
        if (res.kind === 'local') {
          if (res.reg !== src) {
            this.emit(ctx, { op: Op.MOVE, a: res.reg, b: src, c: 0, d: 0, aux: 0 });
          }
        } else if (res.kind === 'upval') {
          this.emit(ctx, { op: Op.SETUPVAL, a: src, b: res.idx, c: 0, d: 0, aux: 0 });
        } else {
          this.emit(ctx, { op: Op.SETGLOBAL, a: src, b: 0, c: 0, d: this.addString(ctx, v.local.name), aux: 0 });
        }
      } else if (v.kind === 'IndexExpr') {
        const p = prefixes[i];
        this.emit(ctx, { op: Op.SETTABLE, a: src, b: p.tableReg, c: p.keyReg, d: 0, aux: 0 });
      } else if (v.kind === 'IndexName') {
        const p = prefixes[i];
        this.emit(ctx, { op: Op.SETTABLEKS, a: src, b: p.tableReg, c: 0, d: 0, aux: p.keyConstIdx });
      }
    }
    this.release(ctx, nVals === 0 ? 0 : nVars);
    this.release(ctx, prefixTemps);
  }

  compileCompoundAssign(ctx: FnCtx, stat: CompoundAssignStat): void {
    const v = stat.var;
    const binOp = stat.op;
    if (binOp === 'And' || binOp === 'Or') {
      throw new CompileError('logical compound assignment is not supported');
    }
    if (v.kind === 'Global') {
      const nameK = this.addString(ctx, v.name);
      const t = this.reserve(ctx, 1);
      this.emit(ctx, { op: Op.GETGLOBAL, a: t, b: 0, c: 0, d: nameK, aux: 0 });
      this.compileBinOpAssign(ctx, t, stat.value, binOp);
      this.emit(ctx, { op: Op.SETGLOBAL, a: t, b: 0, c: 0, d: nameK, aux: 0 });
      this.release(ctx, 1);
    } else if (v.kind === 'LocalExpr') {
      const res = this.resolveName(ctx, v.local.name);
      if (res.kind === 'local') {
        this.compileBinOpAssign(ctx, res.reg, stat.value, binOp);
      } else if (res.kind === 'upval') {
        const t = this.reserve(ctx, 1);
        this.emit(ctx, { op: Op.GETUPVAL, a: t, b: res.idx, c: 0, d: 0, aux: 0 });
        this.compileBinOpAssign(ctx, t, stat.value, binOp);
        this.emit(ctx, { op: Op.SETUPVAL, a: t, b: res.idx, c: 0, d: 0, aux: 0 });
        this.release(ctx, 1);
      } else {
        const nameK = this.addString(ctx, v.local.name);
        const t = this.reserve(ctx, 1);
        this.emit(ctx, { op: Op.GETGLOBAL, a: t, b: 0, c: 0, d: nameK, aux: 0 });
        this.compileBinOpAssign(ctx, t, stat.value, binOp);
        this.emit(ctx, { op: Op.SETGLOBAL, a: t, b: 0, c: 0, d: nameK, aux: 0 });
        this.release(ctx, 1);
      }
    } else if (v.kind === 'IndexExpr' || v.kind === 'IndexName') {
      // Prefix subexpressions evaluate exactly once (Luau compound semantics).
      const t = this.reserve(ctx, 1);
      this.compileExpr(ctx, v.expr, t, 'single');
      let keyReg = -1;
      let keyConstIdx = -1;
      if (v.kind === 'IndexExpr') {
        keyReg = this.reserve(ctx, 1);
        this.compileExpr(ctx, v.index, keyReg, 'single');
      } else {
        keyConstIdx = this.addString(ctx, v.index);
      }
      const val = this.reserve(ctx, 1);
      if (keyReg >= 0) {
        this.emit(ctx, { op: Op.GETTABLE, a: val, b: t, c: keyReg, d: 0, aux: 0 });
      } else {
        this.emit(ctx, { op: Op.GETTABLEKS, a: val, b: t, c: 0, d: 0, aux: keyConstIdx });
      }
      this.compileBinOpAssign(ctx, val, stat.value, binOp);
      if (keyReg >= 0) {
        this.emit(ctx, { op: Op.SETTABLE, a: val, b: t, c: keyReg, d: 0, aux: 0 });
      } else {
        this.emit(ctx, { op: Op.SETTABLEKS, a: val, b: t, c: 0, d: 0, aux: keyConstIdx });
      }
      this.release(ctx, keyReg >= 0 ? 3 : 2);
    } else {
      throw new CompileError('cannot compound-assign to this expression');
    }
  }

  /** R(target) := R(target) op <value>. */
  compileBinOpAssign(ctx: FnCtx, target: number, value: Expr, binOp: BinaryOp): void {
    if (value.kind === 'Number') {
      const kIdx = this.addNumber(ctx, value.value);
      if (kIdx <= LIMITS.kIndex8Max) {
        this.emit(ctx, { op: arithKOp(binOp), a: target, b: target, c: kIdx, d: 0, aux: 0 });
        return;
      }
    }
    const r = this.reserve(ctx, 1);
    this.compileExpr(ctx, value, r, 'single');
    this.emit(ctx, { op: arithOp(binOp), a: target, b: target, c: r, d: 0, aux: 0 });
    this.release(ctx, 1);
  }

  // --- function statements -----------------------------------------------

  compileFunctionStat(ctx: FnCtx, stat: FunctionStat): void {
    const name = stat.name;
    if (name.kind !== 'IndexName') {
      throw new CompileError('function statement target must be a name index');
    }
    const t = this.reserve(ctx, 1);
    this.compileExpr(ctx, name.expr, t, 'single');
    const kIdx = this.addString(ctx, name.index);
    const val = this.reserve(ctx, 1);
    this.compileClosure(ctx, stat.func, val);
    this.emit(ctx, { op: Op.SETTABLEKS, a: val, b: t, c: 0, d: 0, aux: kIdx });
    this.release(ctx, 2);
  }

  compileLocalFunction(ctx: FnCtx, stat: LocalFunctionStat): void {
    // Bind the name BEFORE compiling the body (recursion visibility).
    this.bindLocal(ctx, stat.name);
    const r = ctx.locals.length - 1;
    this.compileClosure(ctx, stat.func, r);
  }

  /** Compile a function expression into a child proto and emit NEWCLOSURE.
   *  Nested compilation: the child resolves its free names against THIS
   *  scope immediately (upvalue descriptors created while visible). */
  compileClosure(ctx: FnCtx, fn: FunctionExpr, target: number): void {
    const childCtx = this.compileFunction(ctx, fn.body, fn);
    this.emit(ctx, { op: Op.NEWCLOSURE, a: target, b: 0, c: 0, d: childCtx.protoIndex, aux: 0 });
    ctx.proto.children.push(childCtx.protoIndex);
  }

  // --- expressions ---------------------------------------------------------

  isMultretExpr(e: Expr): boolean {
    return e.kind === 'Call' || e.kind === 'Vararg';
  }

  /** Compile an expression list into consecutive registers at `base`.
   *  Returns the number of values produced, or -1 when the tail is an open
   *  multret window (values run base..top; the consumer closes it). */
  compileExprList(ctx: FnCtx, list: readonly Expr[], base: number, wantMultret: boolean): number {
    if (list.length === 0) return 0;
    let cursor = base;
    for (let i = 0; i < list.length - 1; i++) {
      const r = this.reserve(ctx, 1);
      void r;
      this.compileExpr(ctx, list[i], cursor, 'single');
      cursor++;
    }
    const last = list[list.length - 1];
    if (wantMultret && isMultretExpr(last)) {
      if (last.kind === 'Call') {
        this.compileCall(ctx, last, cursor, 0); // C=0: results to top
      } else {
        const r = this.reserve(ctx, 1);
        void r;
        this.emit(ctx, { op: Op.GETVARARGS, a: cursor, b: 0, c: 0, d: 0, aux: 0 });
      }
      return -1;
    }
    const r = this.reserve(ctx, 1);
    void r;
    this.compileExpr(ctx, last, cursor, 'single');
    return list.length;
  }

  /** Multret tail adjusted to exactly `want` results (local/assign/forin). */
  compileExprListMultretAdjusted(ctx: FnCtx, list: readonly Expr[], base: number, want: number): number {
    const last = list[list.length - 1];
    let cursor = base;
    for (let i = 0; i < list.length - 1; i++) {
      const r = this.reserve(ctx, 1);
      void r;
      this.compileExpr(ctx, list[i], cursor, 'single');
      cursor++;
    }
    const nPre = list.length - 1;
    const nTake = Math.max(0, want - nPre);
    if (last.kind === 'Call') {
      this.compileCall(ctx, last, cursor, nTake);
    } else if (nTake === 1) {
      const r = this.reserve(ctx, 1);
      void r;
      this.compileExpr(ctx, last, cursor, 'single');
    } else {
      const r = this.reserve(ctx, 1);
      void r;
      this.emit(ctx, { op: Op.GETVARARGS, a: cursor, b: nTake + 1, c: 0, d: 0, aux: 0 });
    }
    return want;
  }

  /**
   * Compile a call. `base` = function register (caller-reserved window
   * start). want: -1 = zero fixed results (C=1); 0 = multret to top (C=0);
   * n>0 = exactly n results (C=n+1).
   */
  compileCall(ctx: FnCtx, call: CallExpr, base: number, want: number): void {
    // `base` (function register) is OWNED by this method: the allocation
    // frontier must sit at least at base+1 before arguments reserve above
    // it. Callers that pre-reserved `base` keep their frontier; callers
    // that compile the call at the raw frontier (compileExprList /
    // compileExprListMultretAdjusted tails, return lists, for-in windows)
    // are aligned here. Without this, argument registers clobber the
    // callee slot (differential harness: "attempt to call a number value").
    if (ctx.freeReg < base + 1) ctx.freeReg = base + 1;
    // Argument window is reserved above the callee slot.
    let argStart: number;
    if (call.self && call.func.kind === 'IndexName') {
      const t = this.reserve(ctx, 1);
      this.compileExpr(ctx, call.func.expr, t, 'single');
      const kIdx = this.addString(ctx, call.func.index);
      this.emit(ctx, { op: Op.SELFKS, a: base, b: t, c: 0, d: 0, aux: kIdx });
      this.release(ctx, 1);
      this.reserve(ctx, 1); // self slot at base+1
      argStart = base + 2;
    } else {
      this.compileExpr(ctx, call.func, base, 'single');
      argStart = base + 1;
    }
    const args = call.args;
    const lastIsMultret = args.length > 0 && isMultretExpr(args[args.length - 1]);
    let b: number;
    if (lastIsMultret) {
      // All but last as fixed args; the last opens the window (B=0).
      for (let i = 0; i < args.length - 1; i++) {
        const r = this.reserve(ctx, 1);
        this.compileExpr(ctx, args[i], r, 'single');
      }
      const last = args[args.length - 1];
      if (last.kind === 'Call') {
        const r = this.reserve(ctx, 1);
        this.compileCall(ctx, last, r, 0);
      } else {
        const r = this.reserve(ctx, 1);
        this.emit(ctx, { op: Op.GETVARARGS, a: r, b: 0, c: 0, d: 0, aux: 0 });
      }
      b = 0;
    } else {
      for (let i = 0; i < args.length; i++) {
        const r = this.reserve(ctx, 1);
        this.compileExpr(ctx, args[i], r, 'single');
      }
      b = args.length + (argStart - base - 1) + 1;
    }
    const c = want === 0 ? 0 : want === -1 ? 1 : want + 1;
    this.emit(ctx, { op: Op.CALL, a: base, b, c, d: 0, aux: 0 });
    // Post-call register state: fixed wants keep live results at
    // base..base+want-1; want=-1 keeps the caller's 1-slot window (results
    // discarded); multret leaves an open window at base+1.
    ctx.freeReg = base + (want === 0 ? 1 : Math.max(want, 1));
    if (ctx.freeReg > ctx.proto.maxRegs) ctx.proto.maxRegs = ctx.freeReg;
  }

  /** Compile any expression to register `target` (single value). The target
   *  register must be reserved by the caller at the allocation frontier. */
  compileExpr(ctx: FnCtx, e: Expr, target: number, _mode: 'single' | 'multret'): void {
    switch (e.kind) {
      case 'Nil':
        this.emit(ctx, { op: Op.LOADNIL, a: target, b: 0, c: 0, d: 0, aux: 0 });
        break;
      case 'Bool':
        this.emit(ctx, { op: Op.LOADBOOL, a: target, b: e.value ? 1 : 0, c: 0, d: 0, aux: 0 });
        break;
      case 'Number': {
        if (Number.isInteger(e.value) && e.value >= -32768 && e.value <= 32767) {
          this.emit(ctx, { op: Op.LOADINT, a: target, b: 0, c: 0, d: e.value, aux: 0 });
        } else {
          this.loadK(ctx, target, this.addNumber(ctx, e.value));
        }
        break;
      }
      case 'Int':
        throw new CompileError('int64 literals (42i) are not supported in v1 (D-M5-10)');
      case 'String':
        this.loadK(ctx, target, this.addString(ctx, e.value));
        break;
      case 'InterpString':
        this.compileInterpString(ctx, e, target);
        break;
      case 'LocalExpr': {
        const slot = this.findLocal(ctx, e.local.name);
        if (slot && slot.local === e.local) {
          if (slot.reg !== target) {
            this.emit(ctx, { op: Op.MOVE, a: target, b: slot.reg, c: 0, d: 0, aux: 0 });
          }
        } else {
          const res = this.resolveName(ctx, e.local.name);
          if (res.kind === 'upval') {
            this.emit(ctx, { op: Op.GETUPVAL, a: target, b: res.idx, c: 0, d: 0, aux: 0 });
          } else {
            // Not bound anywhere as a local/upvalue: global by name.
            this.emit(ctx, { op: Op.GETGLOBAL, a: target, b: 0, c: 0, d: this.addString(ctx, e.local.name), aux: 0 });
          }
        }
        break;
      }
      case 'Global': {
        this.emit(ctx, { op: Op.GETGLOBAL, a: target, b: 0, c: 0, d: this.addString(ctx, e.name), aux: 0 });
        break;
      }
      case 'Vararg':
        // Single-value context (multret handled by compileExprList).
        this.emit(ctx, { op: Op.GETVARARGS, a: target, b: 2, c: 0, d: 0, aux: 0 });
        break;
      case 'Call':
        this.compileCall(ctx, e, target, 1);
        break;
      case 'IndexName': {
        const t = this.reserve(ctx, 1);
        this.compileExpr(ctx, e.expr, t, 'single');
        const kIdx = this.addString(ctx, e.index);
        this.emit(ctx, { op: Op.GETTABLEKS, a: target, b: t, c: 0, d: 0, aux: kIdx });
        this.release(ctx, 1);
        break;
      }
      case 'IndexExpr': {
        const t = this.reserve(ctx, 1);
        this.compileExpr(ctx, e.expr, t, 'single');
        const k = this.reserve(ctx, 1);
        this.compileExpr(ctx, e.index, k, 'single');
        this.emit(ctx, { op: Op.GETTABLE, a: target, b: t, c: k, d: 0, aux: 0 });
        this.release(ctx, 2);
        break;
      }
      case 'Function':
        this.compileClosure(ctx, e, target);
        break;
      case 'Table':
        this.compileTable(ctx, e, target);
        break;
      case 'Unary': {
        const r = this.reserve(ctx, 1);
        this.compileExpr(ctx, e.expr, r, 'single');
        const op = unaryOp(e.op);
        this.emit(ctx, { op, a: target, b: r, c: 0, d: 0, aux: 0 });
        this.release(ctx, 1);
        break;
      }
      case 'Binary':
        this.compileBinary(ctx, e, target);
        break;
      case 'TypeAssertion':
        this.compileExpr(ctx, e.expr, target, 'single');
        break;
      case 'IfElse':
        this.compileIfElseExpr(ctx, e, target);
        break;
      case 'Instantiate':
        this.compileExpr(ctx, e.expr, target, 'single');
        break;
      case 'Group':
        this.compileExpr(ctx, e.expr, target, 'single');
        break;
      default: {
        const never: never = e;
        void never;
        throw new CompileError(`unsupported expression kind ${(e as Expr).kind}`);
      }
    }
  }

  compileInterpString(ctx: FnCtx, e: InterpStringExpr, target: number): void {
    // Luau lowering (RESEARCH-M5 #3/#4): string.format with % escaping and
    // %* per expression (tostring-style conversion).
    let fmt = '';
    for (let i = 0; i < e.strings.length; i++) {
      fmt += e.strings[i].replace(/%/g, '%%');
      if (i < e.expressions.length) fmt += '%*';
    }
    const nargs = e.expressions.length;
    const base = this.reserve(ctx, 2 + nargs);
    this.loadK(ctx, base + 1, this.addString(ctx, fmt));
    for (let i = 0; i < nargs; i++) {
      this.compileExpr(ctx, e.expressions[i], base + 2 + i, 'single');
    }
    this.emit(ctx, { op: Op.GETGLOBAL, a: base, b: 0, c: 0, d: this.addString(ctx, 'string'), aux: 0 });
    this.emit(ctx, { op: Op.GETTABLEKS, a: base, b: base, c: 0, d: 0, aux: this.addString(ctx, 'format') });
    this.emit(ctx, { op: Op.CALL, a: base, b: nargs + 2, c: 2, d: 0, aux: 0 });
    this.emit(ctx, { op: Op.MOVE, a: target, b: base, c: 0, d: 0, aux: 0 });
    this.release(ctx, 2 + nargs);
  }

  compileIfElseExpr(ctx: FnCtx, e: IfElseExpr, target: number): void {
    this.openScope(ctx);
    if (e.conditionLocal) this.bindLocal(ctx, e.conditionLocal);
    const r = this.reserve(ctx, 1);
    this.compileExpr(ctx, e.condition, r, 'single');
    // Trampoline: [JUMPIF r, D=1][JUMP -> falseExpr]: truthy falls into the
    // true expression; falsy takes the JUMP.
    const skip = this.emitCondJumpForward(ctx, Op.JUMPIF, r, 0);
    this.release(ctx, 1);
    this.compileExpr(ctx, e.trueExpr, target, 'single');
    const endJump = this.emitJumpPlaceholder(ctx);
    this.patchJump(ctx, skip, ctx.proto.code.length);
    this.compileExpr(ctx, e.falseExpr, target, 'single');
    this.patchJump(ctx, endJump, ctx.proto.code.length);
    this.closeScope(ctx, true);
  }

  compileBinary(ctx: FnCtx, e: BinaryExpr, target: number): void {
    switch (e.op) {
      case 'And': case 'Or': {
        // Lua: a and b == truthy(a) ? b : a; a or b == truthy(a) ? a : b.
        this.compileExpr(ctx, e.left, target, 'single');
        const r = this.reserve(ctx, 1);
        this.compileExpr(ctx, e.right, r, 'single');
        const op = e.op === 'And' ? Op.AND : Op.OR;
        this.emit(ctx, { op, a: target, b: target, c: r, d: 0, aux: 0 });
        this.release(ctx, 1);
        break;
      }
      case 'Concat': {
        const chain: Expr[] = [];
        flattenConcat(e, chain);
        const start = this.reserve(ctx, chain.length);
        for (let i = 0; i < chain.length; i++) {
          this.compileExpr(ctx, chain[i], start + i, 'single');
        }
        this.emit(ctx, { op: Op.CONCAT, a: target, b: start, c: start + chain.length - 1, d: 0, aux: 0 });
        this.release(ctx, chain.length);
        break;
      }
      case 'CompareEq': case 'CompareNe': case 'CompareLt': case 'CompareLe':
      case 'CompareGt': case 'CompareGe':
        this.compileComparison(ctx, e, target);
        break;
      default: {
        if (e.right.kind === 'Number') {
          const kIdx = this.addNumber(ctx, e.right.value);
          if (kIdx <= LIMITS.kIndex8Max) {
            const l = this.reserve(ctx, 1);
            this.compileExpr(ctx, e.left, l, 'single');
            this.emit(ctx, { op: arithKOp(e.op), a: target, b: l, c: kIdx, d: 0, aux: 0 });
            this.release(ctx, 1);
            break;
          }
        }
        const l = this.reserve(ctx, 1);
        this.compileExpr(ctx, e.left, l, 'single');
        const r = this.reserve(ctx, 1);
        this.compileExpr(ctx, e.right, r, 'single');
        this.emit(ctx, { op: arithOp(e.op), a: target, b: l, c: r, d: 0, aux: 0 });
        this.release(ctx, 2);
        break;
      }
    }
  }

  /** Comparison -> boolean in `target` (jump-family + LOADBOOL). */
  compileComparison(ctx: FnCtx, e: BinaryExpr, target: number): void {
    const l = this.reserve(ctx, 1);
    this.compileExpr(ctx, e.left, l, 'single');
    const right = e.right;
    // The K-form comparison instructions are EQUALITY-only (JUMPIFEQK*);
    // ordered comparisons with a constant right side load it into a temp
    // and use the register form below.
    const kFormOk = e.op === 'CompareEq' || e.op === 'CompareNe';
    if (kFormOk && (right.kind === 'Nil' || right.kind === 'Bool' || right.kind === 'Number' || right.kind === 'String')) {
      const not = e.op === 'CompareNe' ? 0x80000000 : 0;
      let condOp: number;
      let aux = not;
      if (right.kind === 'Nil') condOp = Op.JUMPIFEQKNIL;
      else if (right.kind === 'Bool') { condOp = Op.JUMPIFEQKB; aux = (right.value ? 1 : 0) | not; }
      else if (right.kind === 'Number') { condOp = Op.JUMPIFEQKN; aux = this.addNumber(ctx, right.value) | not; }
      else { condOp = Op.JUMPIFEQKS; aux = this.addString(ctx, right.value) | not; }
      const jpc = this.emitCondJumpForward(ctx, condOp, l, aux >>> 0);
      // Condition TRUE falls past the trampoline JUMP: TRUE block first.
      this.emit(ctx, { op: Op.LOADBOOL, a: target, b: 1, c: 0, d: 0, aux: 0 });
      const endJump = this.emitJumpPlaceholder(ctx);
      this.patchJump(ctx, jpc, ctx.proto.code.length);
      this.emit(ctx, { op: Op.LOADBOOL, a: target, b: 0, c: 0, d: 0, aux: 0 });
      this.patchJump(ctx, endJump, ctx.proto.code.length);
      this.release(ctx, 1);
      return;
    }
    const r = this.reserve(ctx, 1);
    this.compileExpr(ctx, right, r, 'single');
    // Lower > and >= by swapping operands (a>b == b<a).
    let condOp: number;
    let a1 = l;
    let a2 = r;
    switch (e.op) {
      case 'CompareEq': condOp = Op.JUMPIFEQ; break;
      case 'CompareNe': condOp = Op.JUMPIFEQ; break;
      case 'CompareLt': condOp = Op.JUMPIFLT; break;
      case 'CompareLe': condOp = Op.JUMPIFLE; break;
      case 'CompareGt': condOp = Op.JUMPIFLT; a1 = r; a2 = l; break;
      case 'CompareGe': condOp = Op.JUMPIFLE; a1 = r; a2 = l; break;
      default: throw new CompileError('bad comparison');
    }
    const not = e.op === 'CompareNe' ? 0x80000000 : 0;
    const aux = (a2 | not) >>> 0;
    const jpc = this.emitCondJumpForward(ctx, condOp, a1, aux);
    // Condition TRUE falls past the trampoline JUMP: TRUE block first.
    this.emit(ctx, { op: Op.LOADBOOL, a: target, b: 1, c: 0, d: 0, aux: 0 });
    const endJump = this.emitJumpPlaceholder(ctx);
    this.patchJump(ctx, jpc, ctx.proto.code.length);
    this.emit(ctx, { op: Op.LOADBOOL, a: target, b: 0, c: 0, d: 0, aux: 0 });
    this.patchJump(ctx, endJump, ctx.proto.code.length);
    this.release(ctx, 2);
  }

  // --- table constructor ---------------------------------------------------

  compileTable(ctx: FnCtx, e: TableExpr, target: number): void {
    let arrayHint = 0;
    let hashHint = 0;
    for (const item of e.items) {
      if (item.kind === 'List') arrayHint++;
      else hashHint++;
    }
    this.emit(ctx, {
      op: Op.NEWTABLE, a: target,
      b: Math.min(255, arrayHint), c: Math.min(255, hashHint),
      d: 0, aux: 0,
    });
    let arrayCount = 0;
    let stored = 0; // array items already committed by earlier flushes
    let stagedBase = -1;
    const releaseStaged = (): void => {
      if (stagedBase >= 0) {
        this.release(ctx, ctx.freeReg - stagedBase);
        stagedBase = -1;
      }
    };
    const flush = (multret: boolean): void => {
      if (arrayCount === 0 && !multret) return;
      // AUX = number of array items ALREADY stored (0-based chunk offset);
      // the interpreter writes T[A][aux+1 .. aux+B] (1-based Lua indices)
      // from R[A+1..A+B]. Multret tails are last-by-grammar, so `stored`
      // stays compile-time exact.
      this.emit(ctx, {
        op: Op.SETLIST, a: target,
        b: multret ? 0 : arrayCount,
        c: 0, d: 0, aux: stored,
      });
      stored += arrayCount;
      arrayCount = 0;
      releaseStaged();
    };
    const ensureStaged = (): number => {
      if (stagedBase < 0) {
        stagedBase = this.reserve(ctx, 1);
      } else {
        this.reserve(ctx, 1);
      }
      return stagedBase + arrayCount;
    };
    for (let i = 0; i < e.items.length; i++) {
      const item = e.items[i];
      const isLast = i === e.items.length - 1;
      if (item.kind === 'List') {
        if (isLast && isMultretExpr(item.value)) {
          const r = ensureStaged();
          if (item.value.kind === 'Call') {
            this.compileCall(ctx, item.value, r, 0);
          } else {
            this.emit(ctx, { op: Op.GETVARARGS, a: r, b: 0, c: 0, d: 0, aux: 0 });
          }
          flush(true);
          continue;
        }
        const r = ensureStaged();
        this.compileExpr(ctx, item.value, r, 'single');
        arrayCount++;
        if (arrayCount >= FIELDS_PER_FLUSH) flush(false);
      } else if (item.kind === 'Record') {
        flush(false);
        if (!item.key || item.key.kind !== 'String') {
          throw new CompileError('internal: record item key must be a string');
        }
        const kIdx = this.addString(ctx, item.key.value);
        const v = this.reserve(ctx, 1);
        this.compileExpr(ctx, item.value, v, 'single');
        this.emit(ctx, { op: Op.SETTABLEKS, a: v, b: target, c: 0, d: 0, aux: kIdx });
        this.release(ctx, 1);
      } else {
        flush(false);
        const k = this.reserve(ctx, 1);
        this.compileExpr(ctx, item.key as Expr, k, 'single');
        const v = this.reserve(ctx, 1);
        this.compileExpr(ctx, item.value, v, 'single');
        this.emit(ctx, { op: Op.SETTABLE, a: v, b: target, c: k, d: 0, aux: 0 });
        this.release(ctx, 2);
      }
    }
    flush(false);
  }
}

// --- module-level helpers --------------------------------------------------

interface FnParams {
  readonly self: Local | null;
  readonly args: readonly Local[];
  readonly vararg: boolean;
}

function isMultretExpr(e: Expr): boolean {
  return e.kind === 'Call' || e.kind === 'Vararg';
}

function arithOp(op: BinaryOp): number {
  switch (op) {
    case 'Add': return Op.ADD;
    case 'Sub': return Op.SUB;
    case 'Mul': return Op.MUL;
    case 'Div': return Op.DIV;
    case 'Mod': return Op.MOD;
    case 'Pow': return Op.POW;
    case 'FloorDiv': return Op.IDIV;
    default: throw new CompileError(`operator ${op} has no register form`);
  }
}

function arithKOp(op: BinaryOp): number {
  switch (op) {
    case 'Add': return Op.ADDK;
    case 'Sub': return Op.SUBK;
    case 'Mul': return Op.MULK;
    case 'Div': return Op.DIVK;
    case 'Mod': return Op.MODK;
    case 'Pow': return Op.POWK;
    case 'FloorDiv': return Op.IDIVK;
    default: throw new CompileError(`operator ${op} has no K form`);
  }
}

function unaryOp(op: UnaryOp): number {
  switch (op) {
    case 'Not': return Op.NOT;
    case 'Minus': return Op.MINUS;
    case 'Len': return Op.LENGTH;
  }
}

function flattenConcat(e: BinaryExpr, out: Expr[]): void {
  if (e.left.kind === 'Binary' && (e.left as BinaryExpr).op === 'Concat') {
    flattenConcat(e.left as BinaryExpr, out);
  } else {
    out.push(e.left);
  }
  out.push(e.right);
}

// Re-exported for tests and consumers.
export { type FnParams };
