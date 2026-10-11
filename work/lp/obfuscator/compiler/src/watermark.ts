/**
 * CCP-M7 v1 implementation (ruled ACCEPT, D-M5-20; ruling doc:
 * CCP-M7-RULING.md). Per-session watermark carriers in the LPVB container:
 *
 *  - Carrier 1 — per-function const-pool ORDER permutation, derived from
 *    (watermark, buildSalt, functionIndex); all K references reindexed.
 *  - Carrier 2 — junk (unreferenced) const entries appended after the live
 *    entries; their VALUES encode the watermark XOR a W-independent
 *    keystream so the extractor never needs the watermark to decode it
 *    (no chicken-and-egg).
 *
 * Normative layout pin: BYTECODE-M5.md §6 (this file is the implementation).
 * Integrity per the ruling: the session build hash covers the FINAL session
 * bytes — a watermarked container is just a different valid container; the
 * canonical (pre-watermark) build hash stays in PackParts.canonicalManifest
 * and in the DB's script_versions.build_hash.
 *
 * Invariants this module enforces (junk-detection soundness, D-M5-22):
 *  - every live pool entry is referenced by >= 1 K-field of its function
 *    (the compiler guarantees this since the arithK peek fix);
 *  - the permutation is closed within encoding blocks [0,256) / [256,32768)
 *    / [32768,nLive) so no rewritten operand can outgrow its field width
 *    (8-bit C for arithK, 16-bit D for LOADK/GETGLOBAL/SETGLOBAL, 24-bit
 *    AUX elsewhere) — no opcode-kind rewriting is ever needed.
 */

import {
  pack, unpack, randomBytes, hkdfSha256Sync, type Manifest, type PackResult,
} from './container';
import { Op, toHex } from './opcode';
import { LIMITS, type Const, type InsnOut, type Proto, type UpvalDesc } from './compile';

/** HKDF info strings for the watermark layout streams (D-M5-21: internal
 *  to the container domain — NOT part of the §5.7 loader/API label set). */
export const WM_LAYOUT_INFO = utf8('wm-layout');
export const WM_JUNK_INFO = utf8('wm-junk');

/** sessions.watermark_id is 16 bytes (M1 randomId = toHex(randomBytes(16))). */
export const WATERMARK_LEN = 16;

/** Junk entries per function: 2 + (layout byte & 1) => 2 or 3 (D-M5-23).
 *  Every function independently carries BOTH 8-byte watermark halves. */
function junkCountFor(layoutByte: number): number {
  return 2 + (layoutByte & 1);
}

// ---------------------------------------------------------------------------
// K-field classification (which operand fields hold pool indices)
// ---------------------------------------------------------------------------

const K_C: ReadonlySet<number> = new Set([
  Op.ADDK, Op.SUBK, Op.MULK, Op.DIVK, Op.MODK, Op.POWK, Op.IDIVK,
]);
const K_D: ReadonlySet<number> = new Set([Op.LOADK, Op.GETGLOBAL, Op.SETGLOBAL]);
const K_AUX: ReadonlySet<number> = new Set([
  Op.LOADKX, Op.GETTABLEKS, Op.SETTABLEKS, Op.SELFKS,
]);
const K_AUX_NOT: ReadonlySet<number> = new Set([Op.JUMPIFEQKN, Op.JUMPIFEQKS]);

/** Per-function set of pool indices its instructions reference. Throws on
 *  operand widths that could not have been emitted by the compiler. */
export function referencedIndices(code: readonly InsnOut[]): Set<number> {
  const refs = new Set<number>();
  for (const i of code) {
    if (K_C.has(i.op)) {
      if (i.c < 0 || i.c > LIMITS.kIndex8Max) throw new Error(`K operand C out of 8-bit range (op ${i.op})`);
      refs.add(i.c);
    } else if (K_D.has(i.op)) {
      if (i.d < 0 || i.d > LIMITS.d16Max) throw new Error(`K operand D out of 16-bit range (op ${i.op})`);
      refs.add(i.d);
    } else if (K_AUX.has(i.op)) {
      if (i.aux < 0 || i.aux >= LIMITS.maxConsts) throw new Error(`K operand AUX out of range (op ${i.op})`);
      refs.add(i.aux);
    } else if (K_AUX_NOT.has(i.op)) {
      const k = i.aux & 0x7fffffff;
      if (k < 0 || k >= LIMITS.maxConsts) throw new Error(`K operand AUX|NOT out of range (op ${i.op})`);
      refs.add(k);
    }
  }
  return refs;
}

// ---------------------------------------------------------------------------
// PackParts — the CLI-boundary projection (option A of the ruling)
// ---------------------------------------------------------------------------

/** Compiler-output projection the api ingests once per version and uses to
 *  run packWatermarked() per session. SERVER-SECRET material (contains
 *  constKey): never leaves the server, never enters a delivery. */
export interface PackParts {
  readonly formatVersion: number;
  readonly opcodeSeed: Uint8Array;
  readonly constKey: Uint8Array;
  readonly buildSalt: Uint8Array;
  readonly canonicalNonces: readonly Uint8Array[];
  readonly canonicalManifest: Manifest;
  readonly protos: readonly Proto[];
}

/** Assemble + verify PackParts from a canonical pack run's inputs. */
export function makePackParts(
  protos: readonly Proto[],
  material: {
    opcodeSeed: Uint8Array;
    constKey: Uint8Array;
    poolNonces: readonly Uint8Array[];
    buildSalt: Uint8Array;
    canonicalManifest: Manifest;
  },
): PackParts {
  const parts: PackParts = {
    formatVersion: 1,
    opcodeSeed: material.opcodeSeed,
    constKey: material.constKey,
    buildSalt: material.buildSalt,
    canonicalNonces: material.poolNonces,
    canonicalManifest: material.canonicalManifest,
    protos,
  };
  verifyPackParts(parts);
  return parts;
}

/** Fail-loud STRUCTURAL check (O(insns)): shapes, lengths, and the
 *  referenced-live invariant. Cheap enough for every packWatermarked
 *  call (per-session, Workers-budget path — D-M5-26 note). */
export function verifyPackPartsStructure(parts: PackParts): void {
  if (parts.formatVersion !== 1) throw new Error(`unsupported PackParts version ${parts.formatVersion}`);
  if (parts.opcodeSeed.length !== 32) throw new Error('opcodeSeed must be 32 bytes');
  if (parts.constKey.length !== 32) throw new Error('constKey must be 32 bytes');
  if (parts.buildSalt.length !== 32) throw new Error('buildSalt must be 32 bytes');
  if (parts.canonicalNonces.length !== parts.protos.length) {
    throw new Error(`canonicalNonces must have one entry per proto (${parts.protos.length})`);
  }
  for (const n of parts.canonicalNonces) {
    if (n.length !== 12) throw new Error('each canonical nonce must be 12 bytes');
  }
  for (let f = 0; f < parts.protos.length; f++) {
    const p = parts.protos[f]!;
    const refs = referencedIndices(p.code);
    if (refs.size > p.consts.length) {
      throw new Error(`proto ${f}: instructions reference ${refs.size} distinct indices but the pool holds ${p.consts.length}`);
    }
    for (const r of refs) {
      if (r < 0 || r >= p.consts.length) {
        throw new Error(`proto ${f}: K reference ${r} out of pool range (0..${p.consts.length - 1})`);
      }
    }
    for (let k = 0; k < p.consts.length; k++) {
      if (!refs.has(k)) {
        throw new Error(`proto ${f}: pool entry ${k} unreferenced (junk-detection invariant broken)`);
      }
    }
  }
}

/** Fail-loud ingestion check: structure + canonical-hash reproduction
 *  (re-packs with the recorded nonces and compares the build hash).
 *  Runs ONCE per version upload (makePackParts / deserializePackParts) —
 *  not per session (D-M5-26). Returns the canonical build hash (hex). */
export function verifyPackParts(parts: PackParts): string {
  verifyPackPartsStructure(parts);
  const canon = pack(parts.protos, {
    opcodeSeed: parts.opcodeSeed,
    constKey: parts.constKey,
    poolNonces: parts.canonicalNonces,
  });
  if (canon.manifest.build_hash !== parts.canonicalManifest.build_hash) {
    throw new Error(`canonical build hash mismatch: re-packed ${canon.manifest.build_hash} vs manifest ${parts.canonicalManifest.build_hash}`);
  }
  return canon.manifest.build_hash;
}

// ---------------------------------------------------------------------------
// Carrier derivations (normative pin in BYTECODE-M5.md §6)
// ---------------------------------------------------------------------------

function utf8(s: string): Uint8Array {
  return new TextEncoder().encode(s);
}

function u32be(n: number): Uint8Array {
  return new Uint8Array([(n >>> 24) & 0xff, (n >>> 16) & 0xff, (n >>> 8) & 0xff, n & 0xff]);
}

function concatBytes(...parts: Uint8Array[]): Uint8Array {
  let len = 0;
  for (const p of parts) len += p.length;
  const out = new Uint8Array(len);
  let off = 0;
  for (const p of parts) {
    out.set(p, off);
    off += p.length;
  }
  return out;
}

/** Deterministic xorshift32 PRNG (permutation carrier only — not a secret;
 *  watermark recovery rides carrier 2, carrier 1 is the consistency check). */
function xorshift32(seed: number): () => number {
  let s = seed >>> 0;
  if (s === 0) s = 0x9e3779b9; // documented non-zero guard
  return () => {
    s ^= s << 13; s >>>= 0;
    s ^= s >>> 17;
    s ^= s << 5; s >>>= 0;
    return s;
  };
}

/** Encoding-width blocks: [0,256) for 8-bit C users, [256,32768) for 16-bit
 *  D users, [32768,nLive) free (24-bit AUX). Closed under the permutation. */
function blocks(nLive: number): [number, number][] {
  const out: [number, number][] = [];
  let lo = 0;
  for (const cut of [Math.min(256, nLive), Math.min(32768, nLive)]) {
    if (cut > lo) {
      out.push([lo, cut]);
      lo = cut;
    }
  }
  if (nLive > lo) out.push([lo, nLive]);
  return out;
}

/** Carrier-1 layout for one function: permutation (old -> new index) and
 *  junk count, both derived from (watermark, buildSalt, functionIndex).
 *  Exported for trusted-side verification (corpus runner asserts loaded
 *  instructions reindex exactly through this permutation). */
export function carrierLayout(watermark: Uint8Array, buildSalt: Uint8Array, f: number, nLive: number): {
  perm: number[];
  junk: number;
} {
  const t = hkdfSha256Sync(watermark, concatBytes(buildSalt, u32be(f)), WM_LAYOUT_INFO, 32);
  const junk = junkCountFor(t[0]!);
  const next = xorshift32((t[1]! << 24) | (t[2]! << 16) | (t[3]! << 8) | t[4]!);
  const perm = Array.from({ length: nLive }, (_, i) => i);
  for (const [lo, hi] of blocks(nLive)) {
    for (let i = hi - 1; i > lo; i--) {
      const j = lo + (next() % (i - lo + 1));
      const tmp = perm[i]!;
      perm[i] = perm[j]!;
      perm[j] = tmp;
    }
  }
  return { perm, junk };
}

/** Carrier-2 keystream for junk position p of function f — derived from
 *  (buildSalt, f, p) ONLY, so the extractor decodes without the watermark. */
function junkKeystream(buildSalt: Uint8Array, f: number, p: number): Uint8Array {
  return hkdfSha256Sync(buildSalt, concatBytes(u32be(f), u32be(p)), WM_JUNK_INFO, 8);
}

/** Junk entry value (str const bytes): W_half(p) XOR keystream. Even p
 *  carries W[0..8), odd p carries W[8..16) (D-M5-23). */
function junkValue(watermark: Uint8Array, buildSalt: Uint8Array, f: number, p: number): string {
  const half = p % 2 === 0 ? watermark.subarray(0, 8) : watermark.subarray(8, 16);
  const ks = junkKeystream(buildSalt, f, p);
  let s = '';
  for (let i = 0; i < 8; i++) s += String.fromCharCode(half[i]! ^ ks[i]!);
  return s;
}

// ---------------------------------------------------------------------------
// packWatermarked
// ---------------------------------------------------------------------------

export interface WatermarkPackOptions {
  /** Deterministic per-session pool nonces (tests). Fresh random when
   *  absent — every session container must differ (per-payload uniqueness,
   *  doc §12). */
  readonly sessionNonces?: readonly Uint8Array[];
  /** Per-session constKey override (D-M5-27, glm1's CCP-M7 co-sign note):
   *  re-seals the pools under a FRESH 32-byte key instead of the per-version
   *  PackParts key. Anti-dump posture — a leaked decrypted bundle decrypts
   *  ONE session's pools, not the version's. TRADE-OFF (documented in
   *  BYTECODE-M5.md §6.5): the watermark lives inside the encrypted pools,
   *  so extraction then requires the session's key (session-key trial over
   *  the version's sessions — fine for an admin leak investigation, not a
   *  hot path). The runtime receives the key via the payload (RUNTIME-M6
   *  §2 entry c — M1's const_key wire field). Default: per-version key
   *  (direct extraction per the CCP-M7 ruling). */
  readonly sessionConstKey?: Uint8Array;
}

/** Build the watermarked protos for one function: permuted live consts +
 *  junk tail + reindexed K operands. Pure (no input mutation). */
function watermarkedProto(p: Proto, watermark: Uint8Array, buildSalt: Uint8Array, f: number): Proto {
  const nLive = p.consts.length;
  const { perm, junk } = carrierLayout(watermark, buildSalt, f, nLive);
  const consts: Const[] = new Array(nLive + junk);
  for (let old = 0; old < nLive; old++) consts[perm[old]!] = p.consts[old]!;
  for (let j = 0; j < junk; j++) consts[nLive + j] = { kind: 'str', s: junkValue(watermark, buildSalt, f, j) };
  const code: InsnOut[] = p.code.map((i): InsnOut => {
    if (K_C.has(i.op)) return { ...i, c: perm[i.c]! };
    if (K_D.has(i.op)) return { ...i, d: perm[i.d]! };
    if (K_AUX.has(i.op)) return { ...i, aux: perm[i.aux]! };
    if (K_AUX_NOT.has(i.op)) return { ...i, aux: ((i.aux & 0x80000000) | perm[i.aux & 0x7fffffff]!) >>> 0 };
    return i;
  });
  return {
    numParams: p.numParams,
    isVararg: p.isVararg,
    maxRegs: p.maxRegs,
    code,
    upvals: p.upvals,
    consts,
    children: p.children,
  };
}

/** Per-session pack under carriers 1+2 (CCP-M7 v1). Verifies the parts
 *  first (canonical reproduction + junk invariant), then packs a permuted,
 *  junk-extended copy with fresh nonces. The returned manifest's
 *  build_hash IS the session hash (hash over the final session bytes). */
export function packWatermarked(parts: PackParts, watermark: Uint8Array, options?: WatermarkPackOptions): PackResult {
  if (watermark.length !== WATERMARK_LEN) {
    throw new Error(`watermark must be ${WATERMARK_LEN} bytes (sessions.watermark_id), got ${watermark.length}`);
  }
  if (options?.sessionConstKey && options.sessionConstKey.length !== 32) {
    throw new Error('sessionConstKey must be 32 bytes');
  }
  // Structural check only per session — the canonical re-pack runs once at
  // ingestion (deserializePackParts / makePackParts), not on the Workers
  // per-delivery path (D-M5-26: the CCP-M7 cost model has ONE pack per
  // session, not two).
  verifyPackPartsStructure(parts);
  const protos = parts.protos.map((p, f) => watermarkedProto(p, watermark, parts.buildSalt, f));
  return pack(protos, {
    opcodeSeed: parts.opcodeSeed,
    constKey: options?.sessionConstKey ?? parts.constKey,
    poolNonces: options?.sessionNonces,
  });
}

// ---------------------------------------------------------------------------
// Extractor (leak workflow step 2 — reference implementation for M7)
// ---------------------------------------------------------------------------

export interface ExtractResult {
  readonly watermark: Uint8Array;
  /** Carrier-1 consistency: every function's pool order + junk layout
   *  re-derives exactly from the recovered watermark. */
  readonly carrier1Ok: boolean;
}

export interface ExtractOptions {
  /** constKey override for containers packed with a session-random key
   *  (D-M5-27): the leak workflow trials the candidate session's key —
   *  a successful AEAD open IS the session identification. Default:
   *  the per-version PackParts key (direct extraction). */
  readonly constKey?: Uint8Array;
}

/** Recover the watermark from delivered container bytes. Returns null for
 *  a CANONICAL container (no junk entries — nothing was watermarked).
 *  Throws on junk disagreement across functions (tampered/foreign). */
export function extractWatermark(container: Uint8Array, parts: PackParts, options?: ExtractOptions): ExtractResult | null {
  const constKey = options?.constKey ?? parts.constKey;
  const loaded = unpack(container, { constKey, opcodeSeed: parts.opcodeSeed });
  let recovered: Uint8Array | null = null;
  for (let f = 0; f < loaded.protos.length; f++) {
    const p = loaded.protos[f]!;
    const refs = referencedIndices(p.insns as unknown as readonly InsnOut[]);
    const junkIdx: number[] = [];
    for (let k = 0; k < p.consts.length; k++) if (!refs.has(k)) junkIdx.push(k);
    if (junkIdx.length === 0) continue; // function without junk (all referenced)
    const halves: [Uint8Array, Uint8Array] = [new Uint8Array(8), new Uint8Array(8)];
    const have = [false, false];
    let pos = 0;
    for (const k of junkIdx) {
      const c = p.consts[k]!;
      if (c.kind !== 'str' || c.s.length !== 8) {
        throw new Error(`function ${f}: junk entry ${k} is not an 8-byte string (foreign container?)`);
      }
      const ks = junkKeystream(parts.buildSalt, f, pos);
      const halfIdx = pos % 2;
      const half = new Uint8Array(8);
      for (let i = 0; i < 8; i++) half[i] = (c.s.charCodeAt(i) & 0xff) ^ ks[i]!;
      if (have[halfIdx]) {
        for (let i = 0; i < 8; i++) {
          if (halves[halfIdx]![i] !== half[i]) {
            throw new Error(`function ${f}: watermark half ${halfIdx} disagrees between junk entries (tampered?)`);
          }
        }
      } else {
        halves[halfIdx] = half;
        have[halfIdx] = true;
      }
      pos++;
    }
    if (!have[0] || !have[1]) {
      throw new Error(`function ${f}: junk carries only one watermark half (foreign container?)`);
    }
    const w = concatBytes(halves[0]!, halves[1]!);
    if (recovered === null) {
      recovered = w;
    } else if (toHex(recovered) !== toHex(w)) {
      throw new Error(`watermark disagreement across functions (tampered?)`);
    }
  }
  if (recovered === null) return null;
  // Carrier-1 consistency: rebuild the expected watermarked protos from the
  // recovered watermark and compare pool contents function by function.
  let carrier1Ok = true;
  for (let f = 0; f < parts.protos.length && f < loaded.protos.length; f++) {
    const expected = watermarkedProto(parts.protos[f]!, recovered, parts.buildSalt, f);
    const actual = loaded.protos[f]!;
    if (actual.consts.length !== expected.consts.length) {
      carrier1Ok = false;
      continue;
    }
    for (let k = 0; k < expected.consts.length; k++) {
      const a = expected.consts[k]!;
      const b = actual.consts[k]!;
      const same = a.kind === b.kind
        && (a.kind === 'bool' && b.kind === 'bool' ? a.b === b.b
          : a.kind === 'num' && b.kind === 'num' ? a.hi === b.hi && a.lo === b.lo
            : a.kind === 'str' && b.kind === 'str' ? a.s === b.s : false);
      if (!same) {
        carrier1Ok = false;
        break;
      }
    }
  }
  return { watermark: recovered, carrier1Ok };
}

// ---------------------------------------------------------------------------
// PackParts serialization (CLI boundary — JSON, bit-exact)
// ---------------------------------------------------------------------------

interface ConstJSON {
  kind: 'bool' | 'num' | 'str';
  b?: boolean;
  /** f64 bit pattern as 16 hex chars (JSON numbers cannot carry NaN/-0/bits). */
  bits?: string;
  s?: string;
}

interface UpvalJSON {
  kind: 'val' | 'ref' | 'upval';
  src: number;
}

interface InsnJSON {
  op: number; a: number; b: number; c: number; d: number; aux: number;
}

interface ProtoJSON {
  numParams: number;
  maxRegs: number;
  isVararg: boolean;
  code: InsnJSON[];
  upvals: UpvalJSON[];
  consts: ConstJSON[];
}

interface PackPartsJSON {
  formatVersion: number;
  opcodeSeed: string;
  constKey: string;
  buildSalt: string;
  canonicalNonces: string[];
  canonicalManifest: Manifest;
  protos: ProtoJSON[];
}

function bytesToHex(b: Uint8Array): string {
  return toHex(b);
}

function hexToBytes(h: string): Uint8Array {
  if (h.length % 2 !== 0) throw new Error('odd-length hex string');
  const out = new Uint8Array(h.length / 2);
  for (let i = 0; i < out.length; i++) out[i] = parseInt(h.slice(i * 2, i * 2 + 2), 16);
  return out;
}

function doubleToHexBits(n: number): string {
  const f64 = new Float64Array(1);
  f64[0] = n;
  const u32 = new Uint32Array(f64.buffer);
  return (u32[0] >>> 0).toString(16).padStart(8, '0') + (u32[1] >>> 0).toString(16).padStart(8, '0');
}

function hexBitsToDouble(h: string): { n: number; hi: number; lo: number } {
  if (h.length !== 16) throw new Error('num const bits must be 16 hex chars');
  const hi = parseInt(h.slice(0, 8), 16);
  const lo = parseInt(h.slice(8, 16), 16);
  const f64 = new Float64Array(1);
  const u32 = new Uint32Array(f64.buffer);
  u32[0] = hi;
  u32[1] = lo;
  return { n: f64[0], hi: hi >>> 0, lo: lo >>> 0 };
}

function constToJSON(c: Const): ConstJSON {
  switch (c.kind) {
    case 'bool': return { kind: 'bool', b: c.b };
    case 'num': return { kind: 'num', bits: doubleToHexBits(c.n) };
    case 'str': return { kind: 'str', s: c.s };
  }
}

function constFromJSON(j: ConstJSON): Const {
  switch (j.kind) {
    case 'bool': return { kind: 'bool', b: j.b! };
    case 'num': {
      const { n, hi, lo } = hexBitsToDouble(j.bits!);
      return { kind: 'num', n, hi, lo };
    }
    case 'str': return { kind: 'str', s: j.s! };
  }
}

function upvalToJSON(u: UpvalDesc): UpvalJSON {
  return { kind: u.kind, src: u.kind === 'upval' ? u.idx : u.reg };
}

function upvalFromJSON(j: UpvalJSON): UpvalDesc {
  if (j.kind === 'val') return { kind: 'val', reg: j.src };
  if (j.kind === 'ref') return { kind: 'ref', reg: j.src };
  return { kind: 'upval', idx: j.src };
}

function protoToJSON(p: Proto): ProtoJSON {
  return {
    numParams: p.numParams,
    maxRegs: p.maxRegs,
    isVararg: p.isVararg,
    code: p.code.map((i) => ({ op: i.op, a: i.a, b: i.b, c: i.c, d: i.d, aux: i.aux })),
    upvals: p.upvals.map(upvalToJSON),
    consts: p.consts.map(constToJSON),
  };
}

function protoFromJSON(j: ProtoJSON): Proto {
  return {
    numParams: j.numParams,
    isVararg: j.isVararg,
    maxRegs: j.maxRegs,
    code: j.code.map((i) => ({ op: i.op, a: i.a, b: i.b, c: i.c, d: i.d, aux: i.aux })),
    upvals: j.upvals.map(upvalFromJSON),
    consts: j.consts.map(constFromJSON),
    children: [],
  };
}

/** Serialize PackParts to JSON (bit-exact across processes). The JSON form
 *  is the CLI-boundary artifact; parse it back with deserializePackParts. */
export function serializePackParts(parts: PackParts): string {
  const j: PackPartsJSON = {
    formatVersion: parts.formatVersion,
    opcodeSeed: bytesToHex(parts.opcodeSeed),
    constKey: bytesToHex(parts.constKey),
    buildSalt: bytesToHex(parts.buildSalt),
    canonicalNonces: parts.canonicalNonces.map(bytesToHex),
    canonicalManifest: parts.canonicalManifest,
    protos: parts.protos.map(protoToJSON),
  };
  return JSON.stringify(j);
}

/** Parse + verify PackParts JSON (verification includes the canonical-hash
 *  reproduction, so corrupted ingestion fails closed). */
export function deserializePackParts(json: string): PackParts {
  const j = JSON.parse(json) as PackPartsJSON;
  if (j.formatVersion !== 1) throw new Error(`unsupported PackParts version ${j.formatVersion}`);
  const parts: PackParts = {
    formatVersion: j.formatVersion,
    opcodeSeed: hexToBytes(j.opcodeSeed),
    constKey: hexToBytes(j.constKey),
    buildSalt: hexToBytes(j.buildSalt),
    canonicalNonces: j.canonicalNonces.map(hexToBytes),
    canonicalManifest: j.canonicalManifest,
    protos: j.protos.map(protoFromJSON),
  };
  verifyPackParts(parts);
  return parts;
}

/** Convenience material generator for build pipelines / tests: random
 *  seeds, keys, salt and per-function nonces + the canonical pack run. */
export function generatePackMaterial(protos: readonly Proto[]): {
  parts: PackParts;
  canonicalContainer: Uint8Array;
} {
  const opcodeSeed = randomBytes(32);
  const constKey = randomBytes(32);
  const buildSalt = randomBytes(32);
  const poolNonces = protos.map(() => randomBytes(12));
  const canonical = pack(protos, { opcodeSeed, constKey, poolNonces });
  const parts = makePackParts(protos, {
    opcodeSeed,
    constKey,
    poolNonces,
    buildSalt,
    canonicalManifest: canonical.manifest,
  });
  return { parts, canonicalContainer: canonical.container };
}
