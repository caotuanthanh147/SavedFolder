/**
 * M5 §5.9 bytecode container: pack/unpack + build manifest.
 *
 * Layout (BYTECODE-M5.md is the normative pin; this is the implementation):
 *   magic "LPVB" (4) | version (1) | build hash (32) | fcount (varint)
 *   | functions[] | encrypted constant pool | trailer CRC-32 (4, LE)
 *
 * - functions serialize depth-first (compiler emission order); NEWCLOSURE
 *   D operands are flat indices into that order.
 * - instructions store EMITTED opcode numbering: the per-build map
 *   (opcode_seed -> Fisher-Yates permutation) is applied at pack time.
 * - the constant pool section is a CONCATENATION of per-function AEAD
 *   blobs (doc §10.2 item 6 "per-function constant keys derived from a
 *   chain"): blob_n = [varint ctLen][nonce 12][ct ctLen][tag 16],
 *   ChaCha20-Poly1305 (M1's pure-TS RFC 8439 implementation — bun
 *   node:crypto lacks the cipher, verified in RESEARCH-M5 #14) under
 *   chained keys (see constKeyChain below). AAD = magic|version|fcount|
 *   functions for every blob (binds each pool to this code; per-blob
 *   uniqueness comes from the chained key + fresh nonce).
 * - build_hash = SHA-256(magic|version|fcount|functions|poolSection).
 * - trailer CRC-32 (RFC 1952 / ISO 3309) covers all preceding bytes.
 */

import { aeadSeal, aeadOpen } from '../../../api/src/chacha';
import {
  OPCODE_COUNT, Op, OP_INFO, decodeAll, opcodeMapFromSeed, inverseMap, sha256Raw, toHex,
} from './opcode';
import type { Insn } from './opcode';
import type { Const, Proto, UpvalDesc } from './compile';

export const MAGIC = Uint8Array.from([0x4c, 0x50, 0x56, 0x42]); // "LPVB"
export const FORMAT_VERSION = 1;

/** HKDF info string, contract-fixed by doc §5.7 ("const-key"). */
export const CONST_KEY_INFO = ascii('const-key');

// ---------------------------------------------------------------------------
// HMAC-SHA256 + HKDF-SHA256 (RFC 2104 / RFC 5869) — synchronous, built on
// opcode.ts's pure-TS sha256Raw; validated against the RFC 5869 TC1-3
// vectors in contracts/test_vectors.json (outside source, §22.1).
// Byte-compatible with M3's Luau loader crypto (same RFC constructions).
// ---------------------------------------------------------------------------

const HASH_LEN = 32;
const HMAC_BLOCK = 64;

export function hmacSha256Raw(key: Uint8Array, data: Uint8Array): Uint8Array {
  let k = key;
  if (k.length > HMAC_BLOCK) k = sha256Raw(k);
  const padded = new Uint8Array(HMAC_BLOCK);
  padded.set(k);
  const inner = new Uint8Array(HMAC_BLOCK + data.length);
  for (let i = 0; i < HMAC_BLOCK; i++) inner[i] = padded[i] ^ 0x36;
  inner.set(data, HMAC_BLOCK);
  const outer = new Uint8Array(HMAC_BLOCK + HASH_LEN);
  for (let i = 0; i < HMAC_BLOCK; i++) outer[i] = padded[i] ^ 0x5c;
  outer.set(sha256Raw(inner), HMAC_BLOCK);
  return sha256Raw(outer);
}

/** RFC 5869 extract+expand. Empty salt = HashLen zero bytes (RFC 5869 §2.2). */
export function hkdfSha256Sync(ikm: Uint8Array, salt: Uint8Array, info: Uint8Array, length: number): Uint8Array {
  if (length < 1 || length > 255 * HASH_LEN) throw new Error('hkdf: invalid length');
  const saltKey = salt.length === 0 ? new Uint8Array(HASH_LEN) : salt;
  const prk = hmacSha256Raw(saltKey, ikm);
  const okm = new Uint8Array(length);
  let t: Uint8Array = new Uint8Array(0);
  let produced = 0;
  for (let i = 1; produced < length; i++) {
    const block = new Uint8Array(t.length + info.length + 1);
    block.set(t, 0);
    block.set(info, t.length);
    block[block.length - 1] = i;
    t = hmacSha256Raw(prk, block);
    const take = Math.min(HASH_LEN, length - produced);
    okm.set(t.subarray(0, take), produced);
    produced += take;
  }
  return okm;
}

/**
 * Per-function constant-pool key chain (doc §10.2 item 6, §5.7 "const-key"):
 *   K_0 = HKDF-SHA256(ikm = constKey, salt = empty, info = "const-key", 32)
 *   K_n = HKDF-SHA256(ikm = K_{n-1}, salt = u32be(n), info = "const-key", 32)
 * Flat indices follow the container's depth-first function order; n is
 * 1-based so every derived key has a non-empty, index-distinct salt.
 * One-way (HKDF): a decrypted function's key derives only SUBSEQUENT
 * keys, each at full HKDF cost — no free unlock of the rest (§10.2.6).
 */
export function constKeyChainStep(prev: Uint8Array, n: number): Uint8Array {
  return hkdfSha256Sync(prev, u32be(n), CONST_KEY_INFO, HASH_LEN);
}

export function constKeyChainRoot(constKey: Uint8Array): Uint8Array {
  return hkdfSha256Sync(constKey, new Uint8Array(0), CONST_KEY_INFO, HASH_LEN);
}

/** Build manifest per doc §5.9 / §10.3. */
export interface Manifest {
  readonly build_hash: string; // hex, 32 bytes
  readonly format_version: number;
  readonly opcode_seed: string; // hex, 32 bytes
  readonly created_at: number; // unix seconds
}

export interface PackOptions {
  /** 32-byte per-build opcode permutation seed; generated when absent. */
  readonly opcodeSeed?: Uint8Array;
  /** 32-byte constant-pool AEAD key. The build pipeline owns derivation
   *  (§5.7 const-key chain, M4 item 6); tests generate their own. */
  readonly constKey: Uint8Array;
}

export interface PackResult {
  readonly container: Uint8Array;
  readonly manifest: Manifest;
}

// ---------------------------------------------------------------------------
// varint (base-128, protobuf spec — RESEARCH-M5 #12)
// ---------------------------------------------------------------------------

export function encodeVarint(out: number[], value: number): void {
  let v = Math.floor(value);
  if (v < 0 || !Number.isSafeInteger(v)) throw new Error('varint out of range');
  while (v >= 0x80) {
    out.push((v & 0x7f) | 0x80);
    v = Math.floor(v / 128);
  }
  out.push(v);
}

export function decodeVarint(bytes: Uint8Array, pos: number): [number, number] {
  let shift = 0;
  let result = 0;
  for (;;) {
    if (pos >= bytes.length) throw new Error('truncated varint');
    const b = bytes[pos++];
    result += (b & 0x7f) * Math.pow(2, shift);
    if ((b & 0x80) === 0) return [result, pos];
    shift += 7;
    if (shift > 63) throw new Error('varint too long');
  }
}

// ---------------------------------------------------------------------------
// CRC-32 (RFC 1952 §2.3.1 / ISO 3309 — reflected poly 0xEDB88320)
// ---------------------------------------------------------------------------

const CRC_TABLE = (() => {
  const t = new Uint32Array(256);
  for (let n = 0; n < 256; n++) {
    let c = n;
    for (let k = 0; k < 8; k++) {
      c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
    }
    t[n] = c >>> 0;
  }
  return t;
})();

export function crc32(bytes: Uint8Array): number {
  let c = 0xffffffff;
  for (let i = 0; i < bytes.length; i++) {
    c = CRC_TABLE[(c ^ bytes[i]) & 0xff] ^ (c >>> 8);
  }
  return (c ^ 0xffffffff) >>> 0;
}

// ---------------------------------------------------------------------------
// pack
// ---------------------------------------------------------------------------

export function pack(protos: readonly Proto[], options: PackOptions): PackResult {
  const seed = options.opcodeSeed ?? randomBytes(32);
  if (seed.length !== 32) throw new Error('opcodeSeed must be 32 bytes');
  if (options.constKey.length !== 32) throw new Error('constKey must be 32 bytes');
  const map = opcodeMapFromSeed(seed);
  if (map.length !== OPCODE_COUNT) throw new Error('internal: opcode map size');

  // --- serialize functions section ---
  const fn: number[] = [];
  for (const p of protos) {
    encodeVarint(fn, p.numParams);
    encodeVarint(fn, p.maxRegs);
    fn.push(p.isVararg ? 1 : 0);
    encodeVarint(fn, p.code.length);
    for (const insn of p.code) {
      const canon = insn.op & 0xff;
      if (canon >= OPCODE_COUNT) throw new Error(`invalid canonical opcode ${canon}`);
      const w = assembleWord(insn, map);
      fn.push(w & 0xff, (w >>> 8) & 0xff, (w >>> 16) & 0xff, (w >>> 24) & 0xff);
      if (OP_INFO[canon][2]) {
        const aux = insn.aux >>> 0;
        fn.push(aux & 0xff, (aux >>> 8) & 0xff, (aux >>> 16) & 0xff, (aux >>> 24) & 0xff);
      }
    }
    encodeVarint(fn, p.upvals.length);
    for (const u of p.upvals) {
      fn.push(u.kind === 'val' ? 0 : u.kind === 'ref' ? 1 : 2);
      encodeVarint(fn, u.kind === 'upval' ? u.idx : u.reg);
    }
  }
  const fnsBytes = Uint8Array.from(fn);

  // --- header prefix (build hash is NOT included — it hashes the rest) ---
  const head: number[] = [];
  for (const b of MAGIC) head.push(b);
  head.push(FORMAT_VERSION);
  encodeVarint(head, protos.length);
  const headBytes = Uint8Array.from(head);

  // --- per-function constant pools, each its own AEAD blob (§10.2 item 6) ---
  const aad = concat(headBytes, fnsBytes);
  const pool: number[] = [];
  let chainKey = constKeyChainRoot(options.constKey);
  for (let i = 0; i < protos.length; i++) {
    if (i > 0) chainKey = constKeyChainStep(chainKey, i);
    const fnPlain: number[] = [];
    encodeVarint(fnPlain, protos[i].consts.length);
    for (const c of protos[i].consts) appendConst(fnPlain, c);
    const nonce = randomBytes(12);
    const sealed = aeadSeal(chainKey, nonce, Uint8Array.from(fnPlain), aad);
    encodeVarint(pool, sealed.ciphertext.length);
    for (const b of nonce) pool.push(b);
    for (const b of sealed.ciphertext) pool.push(b);
    for (const b of sealed.tag) pool.push(b);
  }
  const poolSection = Uint8Array.from(pool);

  // --- build hash over magic|version|fcount|functions|pool (§5.9: the hash
  //     lives in the header and is not part of the hashed bytes) ---
  const body = concat(headBytes, fnsBytes, poolSection);
  const buildHash = sha256Raw(body);

  // --- trailer CRC over everything preceding it ---
  const withHash = concat(headBytes.subarray(0, 5), buildHash, headBytes.subarray(5), fnsBytes, poolSection);
  const trailer = crc32(withHash);

  const container = concat(withHash, u32le(trailer));

  return {
    container,
    manifest: {
      build_hash: toHex(buildHash),
      format_version: FORMAT_VERSION,
      opcode_seed: toHex(seed),
      created_at: Math.floor(Date.now() / 1000),
    },
  };
}

// ---------------------------------------------------------------------------
// unpack
// ---------------------------------------------------------------------------

/** Decoded, execution-ready container. */
export interface LoadedProto {
  readonly numParams: number;
  readonly isVararg: boolean;
  readonly maxRegs: number;
  /** Instruction words with CANONICAL opcodes (map already inverted). */
  readonly words: ReadonlyArray<number>;
  /** Pre-decoded instructions (pc unit = one Insn; jump offsets are
   *  instruction-relative — this is what the reference interpreter and
   *  M6 runtimes index directly). */
  readonly insns: ReadonlyArray<Insn>;
  readonly upvals: readonly UpvalDesc[];
  readonly consts: readonly Const[];
  readonly childIndices: readonly number[];
}

export interface UnpackOptions {
  readonly constKey: Uint8Array;
  readonly opcodeSeed: Uint8Array;
}

export interface LoadedContainer {
  readonly protos: readonly LoadedProto[];
  readonly formatVersion: number;
  readonly buildHash: string;
}

export function unpack(bytes: Uint8Array, options: UnpackOptions): LoadedContainer {
  if (options.constKey.length !== 32) throw new Error('constKey must be 32 bytes');
  if (options.opcodeSeed.length !== 32) throw new Error('opcodeSeed must be 32 bytes');
  if (bytes.length < 4 + 1 + 32 + 1 + 4) throw new Error('container too short');
  for (let i = 0; i < 4; i++) {
    if (bytes[i] !== MAGIC[i]) throw new Error('bad magic');
  }
  const version = bytes[4];
  if (version !== FORMAT_VERSION) throw new Error(`unsupported format version ${version}`);
  // Trailer CRC over everything before it.
  const crcBytes = bytes.subarray(0, bytes.length - 4);
  const stored =
    (bytes[bytes.length - 4]) |
    (bytes[bytes.length - 3] << 8) |
    (bytes[bytes.length - 2] << 16) |
    (bytes[bytes.length - 1] << 24);
  const actual = crc32(crcBytes);
  if (actual !== (stored >>> 0)) throw new Error('CRC-32 mismatch (corrupt container)');
  // Build hash at 5..37.
  const buildHash = bytes.subarray(5, 37);
  let pos = 37;
  const [fcount, p1] = decodeVarint(bytes, pos);
  pos = p1;
  
  const inv = inverseMap(opcodeMapFromSeed(options.opcodeSeed));

  const rawWords: number[][] = [];
  const rawInsns: Insn[][] = [];
  const upvalsAll: UpvalDesc[][] = [];
  const metaAll: { numParams: number; isVararg: boolean; maxRegs: number }[] = [];
  for (let f = 0; f < fcount; f++) {
    const [numParams, p2] = decodeVarint(bytes, pos); pos = p2;
    const [maxRegs, p3] = decodeVarint(bytes, pos); pos = p3;
    const flags = bytes[pos++];
    const [nInst, p4] = decodeVarint(bytes, pos); pos = p4;
    const words: number[] = [];
    for (let i = 0; i < nInst; i++) {
      const w = readU32(bytes, pos); pos += 4;
      const emitted = w & 0xff;
      const canon = emitted < inv.length ? inv[emitted] : -1;
      if (canon < 0) throw new Error(`invalid emitted opcode ${emitted} (trap slot)`);
      // Canonicalize the low byte so downstream decodeInsn (and the
      // NEWCLOSURE scan below) read canonical opcodes directly.
      words.push(((w & 0xffffff00) | canon) >>> 0);
      if (OP_INFO[canon][2]) {
        const aux = readU32(bytes, pos); pos += 4;
        words.push(aux);
      }
    }
    const [nUp, p5] = decodeVarint(bytes, pos); pos = p5;
    const ups: UpvalDesc[] = [];
    for (let i = 0; i < nUp; i++) {
      const kind = bytes[pos++];
      const [src, p6] = decodeVarint(bytes, pos); pos = p6;
      if (kind === 0) ups.push({ kind: 'val', reg: src });
      else if (kind === 1) ups.push({ kind: 'ref', reg: src });
      else if (kind === 2) ups.push({ kind: 'upval', idx: src });
      else throw new Error(`bad upvalue kind ${kind}`);
    }
    rawWords.push(words);
    rawInsns.push(decodeAll(words));
    upvalsAll.push(ups);
    metaAll.push({ numParams, isVararg: (flags & 1) !== 0, maxRegs });
  }
  const fnsEnd = pos;

  // --- pool section: per-function AEAD blobs ---
  // [varint ctLen][nonce 12][ct ctLen][tag 16] per function, chained keys.
  // (Reference interpreter decrypts eagerly; M6 runtimes may decrypt
  // lazily — the ctLen prefix makes blobs skippable, the chain walks
  // forward with the head cached.)
  const aad = concat(bytes.subarray(0, 5), bytes.subarray(37, fnsEnd));
  const poolPlainAll: Uint8Array[] = [];
  {
    let pp = pos;
    let chainKey = constKeyChainRoot(options.constKey);
    for (let f = 0; f < fcount; f++) {
      if (f > 0) chainKey = constKeyChainStep(chainKey, f);
      const [ctLen, q0] = decodeVarint(bytes, pp); pp = q0;
      const blobNonce = bytes.subarray(pp, pp + 12); pp += 12;
      const ct = bytes.subarray(pp, pp + ctLen); pp += ctLen;
      const tag = bytes.subarray(pp, pp + 16); pp += 16;
      if (pp > bytes.length - 4) throw new Error(`constant pool blob ${f} truncated`);
      const plain = aeadOpen(chainKey, blobNonce, aad, ct, tag);
      if (!plain) throw new Error(`constant pool ${f} authentication failed`);
      poolPlainAll.push(plain);
    }
    if (pp !== bytes.length - 4) throw new Error('trailing bytes in constant pool section');
  }

  // Verify build hash: SHA-256 over magic|version|fcount|functions|pool
  // (the hash field at bytes 5..37 is excluded, mirroring pack).
  const hashed = concat(bytes.subarray(0, 5), bytes.subarray(37, bytes.length - 4));
  const recomputed = sha256Raw(hashed);
  for (let i = 0; i < 32; i++) {
    if (recomputed[i] !== buildHash[i]) throw new Error('build hash mismatch');
  }

  // --- decode pools per function ---
  const constsAll: Const[][] = [];
  for (let f = 0; f < fcount; f++) {
    const poolPlain = poolPlainAll[f];
    let pp = 0;
    const [nC, q1] = decodeVarint(poolPlain, pp); pp = q1;
    const consts: Const[] = [];
    for (let i = 0; i < nC; i++) {
      const tagB = poolPlain[pp++];
      if (tagB === 1) {
        consts.push({ kind: 'bool', b: poolPlain[pp++] !== 0 });
      } else if (tagB === 2) {
        const f64 = new Float64Array(1);
        const u8 = new Uint8Array(f64.buffer);
        for (let k = 0; k < 8; k++) u8[k] = poolPlain[pp + k];
        pp += 8;
        consts.push({ kind: 'num', n: f64[0], bits: 0 });
      } else if (tagB === 3) {
        const [len, q2] = decodeVarint(poolPlain, pp); pp = q2;
        let s = '';
        for (let k = 0; k < len; k++) s += String.fromCharCode(poolPlain[pp + k]);
        pp += len;
        consts.push({ kind: 'str', s });
      } else {
        throw new Error(`bad constant tag ${tagB}`);
      }
    }
    if (pp !== poolPlain.length) throw new Error('trailing bytes in constant pool');
    constsAll.push(consts);
  }

  // --- assemble loaded protos (children from NEWCLOSURE operands) ---
  const protos: LoadedProto[] = [];
  for (let f = 0; f < fcount; f++) {
    const words = rawWords[f];
    const children: number[] = [];
    for (let i = 0; i < words.length; ) {
      const canon = words[i] & 0xff; // canonicalized at decode time
      if (canon >= OPCODE_COUNT) throw new Error('internal: opcode map desync');
      if (canon === Op.NEWCLOSURE) {
        const d = (words[i] >>> 16) & 0xffff;
        if (d >= fcount) throw new Error('NEWCLOSURE child index out of range');
        children.push(d);
      }
      i += OP_INFO[canon][2] ? 2 : 1;
    }
    protos.push({
      numParams: metaAll[f].numParams,
      isVararg: metaAll[f].isVararg,
      maxRegs: metaAll[f].maxRegs,
      words,
      insns: rawInsns[f],
      upvals: upvalsAll[f],
      consts: constsAll[f],
      childIndices: children,
    });
  }
  return { protos, formatVersion: version, buildHash: toHex(buildHash) };
}

// --- helpers ---------------------------------------------------------------

function assembleWord(insn: { op: number; a: number; b: number; c: number; d: number }, map: ReadonlyArray<number>): number {
  const canon = insn.op & 0xff;
  const emitted = map[canon];
  const shape = OP_INFO[canon][1];
  if (shape === 'ABC') {
    return (emitted | (insn.a & 0xff) << 8 | (insn.b & 0xff) << 16 | (insn.c & 0xff) << 24) >>> 0;
  }
  if (shape === 'AD') {
    return (emitted | (insn.a & 0xff) << 8 | (insn.d & 0xffff) << 16) >>> 0;
  }
  return (emitted | (insn.d & 0xffffff) << 8) >>> 0;
}

export function randomBytes(n: number): Uint8Array {
  const out = new Uint8Array(n);
  crypto.getRandomValues(out);
  return out;
}

function concat(...parts: Uint8Array[]): Uint8Array {
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

function u32le(v: number): Uint8Array {
  return new Uint8Array([v & 0xff, (v >>> 8) & 0xff, (v >>> 16) & 0xff, (v >>> 24) & 0xff]);
}

function u32be(v: number): Uint8Array {
  return new Uint8Array([(v >>> 24) & 0xff, (v >>> 16) & 0xff, (v >>> 8) & 0xff, v & 0xff]);
}

function ascii(s: string): Uint8Array {
  const out = new Uint8Array(s.length);
  for (let i = 0; i < s.length; i++) out[i] = s.charCodeAt(i) & 0xff;
  return out;
}

function readU32(bytes: Uint8Array, pos: number): number {
  return ((bytes[pos]) | (bytes[pos + 1] << 8) | (bytes[pos + 2] << 16) | (bytes[pos + 3] << 24)) >>> 0;
}

function appendConst(out: number[], c: Const): void {
  switch (c.kind) {
    case 'bool':
      out.push(1, c.b ? 1 : 0);
      break;
    case 'num': {
      out.push(2);
      const f64 = new Float64Array(1);
      f64[0] = c.n;
      const u8 = new Uint8Array(f64.buffer);
      for (const b of u8) out.push(b);
      break;
    }
    case 'str': {
      out.push(3);
      encodeVarint(out, c.s.length);
      for (let i = 0; i < c.s.length; i++) out.push(c.s.charCodeAt(i) & 0xff);
      break;
    }
  }
}
