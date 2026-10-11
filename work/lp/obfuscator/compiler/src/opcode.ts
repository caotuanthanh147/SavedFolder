/**
 * M5 canonical opcode set + instruction word encoding.
 *
 * Clean-room: opcode names, numbering, and semantics are this project's own
 * (see RESEARCH-M5 #10 contrast; nothing copied from Lua 5.1 / Luau / the
 * captured vendor service). The ENCODING SHAPE follows the byte-aligned
 * "word code" precedent (op8 | A8 B8 C8 | A8+D16(signed) | E24(signed) |
 * optional AUX32) per DECISIONS-M5 D-M5-2.
 *
 * Canonical numbering is internal: the compiler emits canonical opcodes and
 * the container maps them through the per-build opcode map (D-M5-3).
 */

/** Canonical opcode ids. 0 is a deliberate gap (NOP anchor / trap slot). */
export const enum Op {
  NOP = 0,
  LOADNIL,
  LOADBOOL,
  LOADINT,
  LOADK,
  LOADKX,
  MOVE,
  GETGLOBAL,
  SETGLOBAL,
  GETUPVAL,
  SETUPVAL,
  CLOSEUPVALS,
  GETTABLE,
  GETTABLEKS,
  SETTABLE,
  SETTABLEKS,
  NEWTABLE,
  SELF,
  SELFKS,
  ADD,
  SUB,
  MUL,
  DIV,
  MOD,
  POW,
  IDIV,
  ADDK,
  SUBK,
  MULK,
  DIVK,
  MODK,
  POWK,
  IDIVK,
  AND,
  OR,
  CONCAT,
  NOT,
  MINUS,
  LENGTH,
  JUMP,
  JUMPIF,
  JUMPIFNOT,
  JUMPIFEQ,
  JUMPIFLT,
  JUMPIFLE,
  JUMPIFEQKNIL,
  JUMPIFEQKB,
  JUMPIFEQKN,
  JUMPIFEQKS,
  CALL,
  RETURN,
  GETVARARGS,
  NEWCLOSURE,
  FORNPREP,
  FORNLOOP,
  FORGPREP,
  FORGLOOP,
  SETLIST,
}

/** Opcode universe size for per-build permutation (D-M5-3). */
export const OPCODE_UNIVERSE = 64;

/** Instruction operand shapes (static per opcode). */
export type Shape = 'ABC' | 'AD' | 'E' | 'AUX';

/** [opcode, shape, hasAUX] table; index = canonical opcode. */
export const OP_INFO: ReadonlyArray<readonly [Op, Shape, boolean]> = [
  [Op.NOP, 'E', false],
  [Op.LOADNIL, 'AD', false], // A target
  [Op.LOADBOOL, 'ABC', false], // A target, B value(0/1)
  [Op.LOADINT, 'AD', false], // A target, D = signed 16-bit integer
  [Op.LOADK, 'AD', false], // A target, D = constant index (<= 32767)
  [Op.LOADKX, 'AD', true], // A target, AUX = constant index (24-bit)
  [Op.MOVE, 'ABC', false], // A target, B source
  [Op.GETGLOBAL, 'AD', false], // A target, D = constant index (name)
  [Op.SETGLOBAL, 'AD', false], // A source, D = constant index (name)
  [Op.GETUPVAL, 'ABC', false], // A target, B upvalue index
  [Op.SETUPVAL, 'ABC', false], // A source, B upvalue index
  [Op.CLOSEUPVALS, 'AD', false], // A register floor
  [Op.GETTABLE, 'ABC', false], // R(A) := R(B)[R(C)]
  [Op.GETTABLEKS, 'ABC', true], // R(A) := R(B)[K(AUX)]
  [Op.SETTABLE, 'ABC', false], // R(B)[R(C)] := R(A)
  [Op.SETTABLEKS, 'ABC', true], // R(B)[K(AUX)] := R(A)
  [Op.NEWTABLE, 'ABC', false], // A target, B array hint, C hash hint
  [Op.SELF, 'ABC', false], // R(A+1) := R(B); R(A) := R(B)[R(C)]
  [Op.SELFKS, 'ABC', true], // R(A+1) := R(B); R(A) := R(B)[K(AUX)]
  [Op.ADD, 'ABC', false], // R(A) := R(B) + R(C)
  [Op.SUB, 'ABC', false],
  [Op.MUL, 'ABC', false],
  [Op.DIV, 'ABC', false],
  [Op.MOD, 'ABC', false],
  [Op.POW, 'ABC', false],
  [Op.IDIV, 'ABC', false], // floor division, Luau //
  [Op.ADDK, 'ABC', false], // R(A) := R(B) op K(C)   (C = const index 0..255)
  [Op.SUBK, 'ABC', false],
  [Op.MULK, 'ABC', false],
  [Op.DIVK, 'ABC', false],
  [Op.MODK, 'ABC', false],
  [Op.POWK, 'ABC', false],
  [Op.IDIVK, 'ABC', false],
  [Op.AND, 'ABC', false], // R(A) := truthy(R(B)) ? R(C) : R(B)
  [Op.OR, 'ABC', false], // R(A) := truthy(R(B)) ? R(B) : R(C)
  [Op.CONCAT, 'ABC', false], // R(A) := R(B) .. ... .. R(C)
  [Op.NOT, 'ABC', false], // A target, B source
  [Op.MINUS, 'ABC', false],
  [Op.LENGTH, 'ABC', false],
  [Op.JUMP, 'E', false], // E = signed word offset (0 = next)
  [Op.JUMPIF, 'AD', false], // A cond register, D = signed word offset
  [Op.JUMPIFNOT, 'AD', false],
  [Op.JUMPIFEQ, 'AD', true], // A reg1, AUX = reg2 | NOT<<31, D offset
  [Op.JUMPIFLT, 'AD', true], // A reg1, AUX = reg2, D offset (jump if A < AUX)
  [Op.JUMPIFLE, 'AD', true], // A reg1, AUX = reg2, D offset (jump if A <= AUX)
  [Op.JUMPIFEQKNIL, 'AD', true], // A reg, AUX = NOT<<31, D offset
  [Op.JUMPIFEQKB, 'AD', true], // A reg, AUX = b | NOT<<31, D offset
  [Op.JUMPIFEQKN, 'AD', true], // A reg, AUX = const24 | NOT<<31, D offset
  [Op.JUMPIFEQKS, 'AD', true], // A reg, AUX = const24 | NOT<<31, D offset
  [Op.CALL, 'ABC', false], // B = nargs+1 (0 = multret), C = nres+1 (0 = multret)
  [Op.RETURN, 'ABC', false], // B = n+1 (0 = all up to top)
  [Op.GETVARARGS, 'ABC', false], // B = n+1 (0 = all, adjusts top)
  [Op.NEWCLOSURE, 'AD', false], // A target, D = child proto index
  [Op.FORNPREP, 'AD', false], // A base of [limit, step, index, var], D offset over body
  [Op.FORNLOOP, 'AD', false], // A base, D offset back to body start
  [Op.FORGPREP, 'AD', false], // A base of [gen, state, index, vars...], D offset to FORGLOOP
  [Op.FORGLOOP, 'AD', true], // A base, AUX = variable count, D offset back to body start
  [Op.SETLIST, 'ABC', true], // A table, B count (0 = to top), AUX = array start index
];

/** Number of defined canonical opcodes (max id + 1). */
export const OPCODE_COUNT = OP_INFO.length;

/** Canonical opcode names in id order (const enum cannot be key-iterated). */
export const OP_NAMES: readonly string[] = [
  'NOP', 'LOADNIL', 'LOADBOOL', 'LOADINT', 'LOADK', 'LOADKX', 'MOVE',
  'GETGLOBAL', 'SETGLOBAL', 'GETUPVAL', 'SETUPVAL', 'CLOSEUPVALS',
  'GETTABLE', 'GETTABLEKS', 'SETTABLE', 'SETTABLEKS', 'NEWTABLE',
  'SELF', 'SELFKS',
  'ADD', 'SUB', 'MUL', 'DIV', 'MOD', 'POW', 'IDIV',
  'ADDK', 'SUBK', 'MULK', 'DIVK', 'MODK', 'POWK', 'IDIVK',
  'AND', 'OR', 'CONCAT', 'NOT', 'MINUS', 'LENGTH',
  'JUMP', 'JUMPIF', 'JUMPIFNOT',
  'JUMPIFEQ', 'JUMPIFLT', 'JUMPIFLE',
  'JUMPIFEQKNIL', 'JUMPIFEQKB', 'JUMPIFEQKN', 'JUMPIFEQKS',
  'CALL', 'RETURN', 'GETVARARGS', 'NEWCLOSURE',
  'FORNPREP', 'FORNLOOP', 'FORGPREP', 'FORGLOOP', 'SETLIST',
];

/** A decoded instruction in structured form. */
export interface Insn {
  readonly op: Op;
  readonly a: number;
  readonly b: number;
  readonly c: number;
  readonly d: number;
  readonly aux: number;
}

/** Encode one instruction word (+aux word when the shape demands it). */
export function encodeInsn(insn: Insn): { word: number; aux: number | null } {
  const [, shape, hasAux] = OP_INFO[insn.op];
  const a = insn.a & 0xff;
  let word: number;
  let aux: number | null = null;
  if (shape === 'ABC') {
    word = insn.op | (a << 8) | ((insn.b & 0xff) << 16) | ((insn.c & 0xff) << 24);
  } else if (shape === 'AD') {
    word = insn.op | (a << 8) | ((insn.d & 0xffff) << 16);
  } else {
    // E: signed 24-bit in bits 8..31
    word = insn.op | ((insn.d & 0xffffff) << 8);
  }
  if (hasAux) aux = insn.aux >>> 0;
  return { word: word >>> 0, aux };
}

/** Decode instruction words at index `pc`; returns [insn, nextPc]. */
export function decodeInsn(words: ReadonlyArray<number>, pc: number): [Insn, number] {
  const word = words[pc] >>> 0;
  const op = word & 0xff;
  if (op >= OPCODE_COUNT) throw new Error(`invalid opcode ${op} at pc=${pc}`);
  const [, shape, hasAux] = OP_INFO[op];
  let insn: Insn;
  if (shape === 'ABC') {
    insn = {
      op,
      a: (word >>> 8) & 0xff,
      b: (word >>> 16) & 0xff,
      c: (word >>> 24) & 0xff,
      d: 0,
      aux: 0,
    };
  } else if (shape === 'AD') {
    // D is signed 16-bit (two's complement in bits 16..31)
    const raw = (word >>> 16) & 0xffff;
    const d = raw >= 0x8000 ? raw - 0x10000 : raw;
    insn = { op, a: (word >>> 8) & 0xff, b: 0, c: 0, d, aux: 0 };
  } else {
    // E: signed 24-bit
    const raw = (word >>> 8) & 0xffffff;
    const d = raw >= 0x800000 ? raw - 0x1000000 : raw;
    insn = { op, a: 0, b: 0, c: 0, d, aux: 0 };
  }
  const next = hasAux ? pc + 2 : pc + 1;
  if (hasAux) insn = { ...insn, aux: words[pc + 1] >>> 0 };
  return [insn, next];
}

/** Instruction width in words (1 or 2). */
export function insnWidth(op: Op): number {
  return OP_INFO[op][2] ? 2 : 1;
}

/**
 * Per-build opcode permutation (D-M5-3): deterministic Fisher-Yates over
 * OPCODE_UNIVERSE slots, driven by SHA-256(seed || counter) bytes.
 * Canonical opcode k maps to emitted slot map[k]. Unused slots are traps.
 * The derivation is intentionally simple and Luau-reimplementable (M6).
 */
export function opcodeMapFromSeed(seed: Uint8Array): ReadonlyArray<number> {
  if (seed.length !== 32) throw new Error('opcode_seed must be 32 bytes');
  const slots = Array.from({ length: OPCODE_UNIVERSE }, (_, i) => i);
  // Deterministic byte stream: SHA-256(seed || u32le(i)) blocks.
  const blocks: number[] = [];
  for (let i = 0; i * 8 < OPCODE_UNIVERSE * 4; i++) {
    const block = sha256Raw(concat(seed, u32le(i)));
    for (const byte of block) blocks.push(byte);
  }
  // Fisher-Yates using 32-bit draws from the byte stream (mod shrinking range).
  let draw = 0;
  for (let i = slots.length - 1; i > 0; i--) {
    let v = 0;
    for (let k = 0; k < 4; k++) {
      v = (v * 256 + (blocks[draw++ % blocks.length] ?? 0)) >>> 0;
    }
    const j = v % (i + 1);
    const t = slots[i];
    slots[i] = slots[j];
    slots[j] = t;
  }
  const map = new Array<number>(OPCODE_COUNT).fill(-1);
  for (let k = 0; k < OPCODE_COUNT; k++) map[k] = slots[k];
  return map;
}

/** Inverse map: emitted slot -> canonical opcode (decoder side). */
export function inverseMap(map: ReadonlyArray<number>): ReadonlyArray<number> {
  const inv = new Array<number>(OPCODE_UNIVERSE).fill(-1);
  for (let canon = 0; canon < map.length; canon++) {
    const emitted = map[canon];
    if (emitted >= 0 && emitted < OPCODE_UNIVERSE) inv[emitted] = canon;
  }
  return inv;
}

// --- small internal helpers (no external deps) ---------------------------

function concat(a: Uint8Array, b: Uint8Array): Uint8Array {
  const out = new Uint8Array(a.length + b.length);
  out.set(a);
  out.set(b, a.length);
  return out;
}

function u32le(v: number): Uint8Array {
  return new Uint8Array([v & 0xff, (v >>> 8) & 0xff, (v >>> 16) & 0xff, (v >>> 24) & 0xff]);
}

/** SHA-256 of bytes -> bytes (pure TS, used for the seed DRBG only). */
export function sha256Raw(data: Uint8Array): Uint8Array {
  // Node-less pure implementation (FIPS 180-4); container uses the same
  // primitive for build_hash via hex digest (see container.ts).
  const K = [
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
    0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
    0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
    0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
    0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
    0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
  ];
  const H = [
    0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19,
  ];
  const bitLen = data.length * 8;
  const padded = new Uint8Array((((data.length + 8) >> 6) + 1) << 6);
  padded.set(data);
  padded[data.length] = 0x80;
  const dv = new DataView(padded.buffer);
  dv.setUint32(padded.length - 4, bitLen >>> 0, false);
  dv.setUint32(padded.length - 8, Math.floor(bitLen / 0x100000000), false);
  const w = new Uint32Array(64);
  const rotr = (x: number, n: number) => ((x >>> n) | (x << (32 - n))) >>> 0;
  for (let off = 0; off < padded.length; off += 64) {
    for (let i = 0; i < 16; i++) w[i] = dv.getUint32(off + i * 4, false);
    for (let i = 16; i < 64; i++) {
      const s0 = rotr(w[i - 15], 7) ^ rotr(w[i - 15], 18) ^ (w[i - 15] >>> 3);
      const s1 = rotr(w[i - 2], 17) ^ rotr(w[i - 2], 19) ^ (w[i - 2] >>> 10);
      w[i] = (w[i - 16] + s0 + w[i - 7] + s1) >>> 0;
    }
    let [a, b, c, d, e, f, g, h] = H;
    for (let i = 0; i < 64; i++) {
      const S1 = rotr(e, 6) ^ rotr(e, 11) ^ rotr(e, 25);
      const ch = (e & f) ^ (~e & g);
      const t1 = (h + S1 + ch + K[i] + w[i]) >>> 0;
      const S0 = rotr(a, 2) ^ rotr(a, 13) ^ rotr(a, 22);
      const maj = (a & b) ^ (a & c) ^ (b & c);
      const t2 = (S0 + maj) >>> 0;
      h = g; g = f; f = e; e = (d + t1) >>> 0;
      d = c; c = b; b = a; a = (t1 + t2) >>> 0;
    }
    H[0] = (H[0] + a) >>> 0; H[1] = (H[1] + b) >>> 0; H[2] = (H[2] + c) >>> 0; H[3] = (H[3] + d) >>> 0;
    H[4] = (H[4] + e) >>> 0; H[5] = (H[5] + f) >>> 0; H[6] = (H[6] + g) >>> 0; H[7] = (H[7] + h) >>> 0;
  }
  const out = new Uint8Array(32);
  const odv = new DataView(out.buffer);
  for (let i = 0; i < 8; i++) odv.setUint32(i * 4, H[i], false);
  return out;
}

export function toHex(bytes: Uint8Array): string {
  return Array.from(bytes, (b) => b.toString(16).padStart(2, '0')).join('');
}

/** Decode a flat canonical word stream (aux words inline) into a
 *  pre-decoded instruction array. Jump offsets count INSTRUCTIONS (the
 *  container format's unit — see BYTECODE-M5.md), so the interpreter
 *  indexes this array directly. */
export function decodeAll(words: ReadonlyArray<number>): Insn[] {
  const out: Insn[] = [];
  let pc = 0;
  while (pc < words.length) {
    const word = words[pc] >>> 0;
    const op = word & 0xff;
    if (op >= OPCODE_COUNT) throw new Error(`invalid opcode ${op} at word ${pc}`);
    const [, shape, hasAux] = OP_INFO[op];
    let insn: Insn;
    if (shape === 'ABC') {
      insn = { op, a: (word >>> 8) & 0xff, b: (word >>> 16) & 0xff, c: (word >>> 24) & 0xff, d: 0, aux: 0 };
    } else if (shape === 'AD') {
      const raw = (word >>> 16) & 0xffff;
      const d = raw >= 0x8000 ? raw - 0x10000 : raw;
      insn = { op, a: (word >>> 8) & 0xff, b: 0, c: 0, d, aux: 0 };
    } else {
      const raw = (word >>> 8) & 0xffffff;
      const d = raw >= 0x800000 ? raw - 0x1000000 : raw;
      insn = { op, a: 0, b: 0, c: 0, d, aux: 0 };
    }
    pc += 1;
    if (hasAux) {
      insn = { ...insn, aux: words[pc] >>> 0 };
      pc += 1;
    }
    out.push(insn);
  }
  return out;
}
