// X25519 per RFC 7748 §5 (Montgomery ladder, BigInt field arithmetic).
// Pure TypeScript so the exact same code path runs in Bun tests and on
// Cloudflare Workers (Bun 1.3.14 WebCrypto cannot export/derive X25519 keys —
// evidence in RESEARCH-M1.md; node:crypto is not relied on because its
// surface is not guaranteed on Workers). Correctness is pinned by the RFC
// 7748 §5.2 and §6.1 test vectors in test/x25519.test.ts.

const P = (1n << 255n) - 19n;
const A24 = 121665n;

function bytesToLE(bytes: Uint8Array): bigint {
  let v = 0n;
  for (let i = bytes.length - 1; i >= 0; i--) {
    v = (v << 8n) | BigInt(bytes[i]);
  }
  return v;
}

function leToBytes(value: bigint, length: number): Uint8Array {
  const out = new Uint8Array(length);
  let v = value;
  for (let i = 0; i < length; i++) {
    out[i] = Number(v & 0xffn);
    v >>= 8n;
  }
  return out;
}

function modPow(base: bigint, exponent: bigint, modulus: bigint): bigint {
  let result = 1n;
  let b = base % modulus;
  let e = exponent;
  while (e > 0n) {
    if (e & 1n) result = (result * b) % modulus;
    b = (b * b) % modulus;
    e >>= 1n;
  }
  return result;
}

export const X25519_BASEPOINT = new Uint8Array(32);
X25519_BASEPOINT[0] = 9;

function decodeScalar(scalar: Uint8Array): bigint {
  if (scalar.length !== 32) throw new Error("x25519 scalar must be 32 bytes");
  const k = new Uint8Array(scalar);
  k[0] &= 248;
  k[31] &= 127;
  k[31] |= 64;
  return bytesToLE(k);
}

function decodeU(u: Uint8Array): bigint {
  if (u.length !== 32) throw new Error("x25519 u-coordinate must be 32 bytes");
  const b = new Uint8Array(u);
  b[31] &= 127;
  return bytesToLE(b) % P;
}

function cswap(swap: bigint, a: bigint, b: bigint): [bigint, bigint] {
  const mask = 0n - swap;
  const dummy = mask & (a ^ b);
  return [a ^ dummy, b ^ dummy];
}

export function x25519(scalar: Uint8Array, u: Uint8Array): Uint8Array {
  const k = decodeScalar(scalar);
  const x1 = decodeU(u);
  let x_2 = 1n;
  let z_2 = 0n;
  let x_3 = x1;
  let z_3 = 1n;
  let swap = 0n;
  for (let t = 254; t >= 0; t--) {
    const k_t = (k >> BigInt(t)) & 1n;
    swap ^= k_t;
    [x_2, x_3] = cswap(swap, x_2, x_3);
    [z_2, z_3] = cswap(swap, z_2, z_3);
    swap = k_t;
    const A = (x_2 + z_2) % P;
    const AA = (A * A) % P;
    const B = (x_2 - z_2 + P) % P;
    const BB = (B * B) % P;
    const E = (AA - BB + P) % P;
    const C = (x_3 + z_3) % P;
    const D = (x_3 - z_3 + P) % P;
    const DA = (D * A) % P;
    const CB = (C * B) % P;
    const x3new = (DA + CB) % P;
    z_3 = (DA - CB + P) % P;
    z_3 = (x1 * ((z_3 * z_3) % P)) % P;
    x_3 = (x3new * x3new) % P;
    x_2 = (AA * BB) % P;
    z_2 = (E * ((AA + A24 * E) % P)) % P;
  }
  [x_2, x_3] = cswap(swap, x_2, x_3);
  [z_2, z_3] = cswap(swap, z_2, z_3);
  const zInv = modPow(z_2, P - 2n, P);
  const result = (x_2 * zInv) % P;
  return leToBytes(result, 32);
}

export function isAllZero(bytes: Uint8Array): boolean {
  let acc = 0;
  for (const b of bytes) acc |= b;
  return acc === 0;
}

export interface X25519KeyPair {
  privateKey: Uint8Array;
  publicKey: Uint8Array;
}

export function clampScalar(scalar: Uint8Array): Uint8Array {
  const k = new Uint8Array(scalar);
  k[0] &= 248;
  k[31] &= 127;
  k[31] |= 64;
  return k;
}

export function generateX25519KeyPair(seed: Uint8Array): X25519KeyPair {
  if (seed.length !== 32) throw new Error("x25519 seed must be 32 bytes");
  const privateKey = clampScalar(seed);
  const publicKey = x25519(privateKey, X25519_BASEPOINT);
  return { privateKey, publicKey };
}

export function x25519SharedSecret(privateKey: Uint8Array, peerPublicKey: Uint8Array): Uint8Array {
  const shared = x25519(privateKey, peerPublicKey);
  if (isAllZero(shared)) throw new Error("x25519 shared secret is all-zero (small-order input)");
  return shared;
}
