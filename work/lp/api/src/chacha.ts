// ChaCha20-Poly1305 AEAD per RFC 8439 (§2.3 block function, §2.4 cipher,
// §2.5 Poly1305, §2.8 AEAD construction). Pure TypeScript: WebCrypto has no
// ChaCha20-Poly1305 and node:crypto's AEAD surface is not guaranteed on
// Workers (RESEARCH-M1.md). Correctness is pinned by RFC 8439 test vectors in
// test/chacha.test.ts.

function le32(bytes: Uint8Array, offset: number): number {
  return (bytes[offset] | (bytes[offset + 1] << 8) | (bytes[offset + 2] << 16) | (bytes[offset + 3] << 24)) >>> 0;
}

function writeLE32(out: Uint8Array, offset: number, value: number): void {
  const v = value >>> 0;
  out[offset] = v & 0xff;
  out[offset + 1] = (v >>> 8) & 0xff;
  out[offset + 2] = (v >>> 16) & 0xff;
  out[offset + 3] = (v >>> 24) & 0xff;
}

function rotl(v: number, c: number): number {
  return ((v << c) | (v >>> (32 - c))) >>> 0;
}

function quarterRound(s: number[], a: number, b: number, c: number, d: number): void {
  s[a] = (s[a] + s[b]) >>> 0;
  s[d] = rotl(s[d] ^ s[a], 16);
  s[c] = (s[c] + s[d]) >>> 0;
  s[b] = rotl(s[b] ^ s[c], 12);
  s[a] = (s[a] + s[b]) >>> 0;
  s[d] = rotl(s[d] ^ s[a], 8);
  s[c] = (s[c] + s[d]) >>> 0;
  s[b] = rotl(s[b] ^ s[c], 7);
}

export function chacha20Block(key: Uint8Array, counter: number, nonce: Uint8Array): Uint8Array {
  if (key.length !== 32) throw new Error("chacha20 key must be 32 bytes");
  if (nonce.length !== 12) throw new Error("chacha20 nonce must be 12 bytes");
  const st = new Array<number>(16);
  st[0] = 0x61707865;
  st[1] = 0x3320646e;
  st[2] = 0x79622d32;
  st[3] = 0x6b206574;
  for (let i = 0; i < 8; i++) st[4 + i] = le32(key, i * 4);
  st[12] = counter >>> 0;
  st[13] = le32(nonce, 0);
  st[14] = le32(nonce, 4);
  st[15] = le32(nonce, 8);
  const x = st.slice();
  for (let i = 0; i < 10; i++) {
    quarterRound(x, 0, 4, 8, 12);
    quarterRound(x, 1, 5, 9, 13);
    quarterRound(x, 2, 6, 10, 14);
    quarterRound(x, 3, 7, 11, 15);
    quarterRound(x, 0, 5, 10, 15);
    quarterRound(x, 1, 6, 11, 12);
    quarterRound(x, 2, 7, 8, 13);
    quarterRound(x, 3, 4, 9, 14);
  }
  const out = new Uint8Array(64);
  for (let i = 0; i < 16; i++) writeLE32(out, i * 4, (x[i] + st[i]) >>> 0);
  return out;
}

export function chacha20Xor(key: Uint8Array, counter: number, nonce: Uint8Array, data: Uint8Array): Uint8Array {
  const out = new Uint8Array(data.length);
  let blockIndex = 0;
  for (let offset = 0; offset < data.length; offset += 64) {
    const keystream = chacha20Block(key, counter + blockIndex, nonce);
    const n = Math.min(64, data.length - offset);
    for (let i = 0; i < n; i++) out[offset + i] = data[offset + i] ^ keystream[i];
    blockIndex++;
  }
  return out;
}

const POLY_P = (1n << 130n) - 5n;
const POLY_CLAMP = 0x0ffffffc0ffffffc0ffffffc0fffffffn;
const POLY_MASK128 = (1n << 128n) - 1n;

function bytesToLE(bytes: Uint8Array): bigint {
  let v = 0n;
  for (let i = bytes.length - 1; i >= 0; i--) {
    v = (v << 8n) | BigInt(bytes[i]);
  }
  return v;
}

function leToBytes16(value: bigint): Uint8Array {
  const out = new Uint8Array(16);
  let v = value;
  for (let i = 0; i < 16; i++) {
    out[i] = Number(v & 0xffn);
    v >>= 8n;
  }
  return out;
}

export function poly1305(key: Uint8Array, message: Uint8Array): Uint8Array {
  if (key.length !== 32) throw new Error("poly1305 key must be 32 bytes");
  const r = bytesToLE(key.subarray(0, 16)) & POLY_CLAMP;
  const s = bytesToLE(key.subarray(16, 32));
  let acc = 0n;
  for (let offset = 0; offset < message.length; offset += 16) {
    const end = Math.min(offset + 16, message.length);
    const n = bytesToLE(message.subarray(offset, end)) | (1n << BigInt((end - offset) * 8));
    acc = ((acc + n) * r) % POLY_P;
  }
  const tag = (acc + s) & POLY_MASK128;
  return leToBytes16(tag);
}

export function poly1305KeyGen(key: Uint8Array, nonce: Uint8Array): Uint8Array {
  return chacha20Block(key, 0, nonce).subarray(0, 32);
}

export function concatBytes(...parts: Uint8Array[]): Uint8Array {
  let total = 0;
  for (const p of parts) total += p.length;
  const out = new Uint8Array(total);
  let offset = 0;
  for (const p of parts) {
    out.set(p, offset);
    offset += p.length;
  }
  return out;
}

function padTo16(length: number): Uint8Array {
  const rem = length % 16;
  return rem === 0 ? new Uint8Array(0) : new Uint8Array(16 - rem);
}

function le64(value: number): Uint8Array {
  const out = new Uint8Array(8);
  let v = value;
  for (let i = 0; i < 8; i++) {
    out[i] = v & 0xff;
    v = Math.floor(v / 256);
  }
  return out;
}

export interface AeadSealed {
  ciphertext: Uint8Array;
  tag: Uint8Array;
}

export function aeadSeal(key: Uint8Array, nonce: Uint8Array, plaintext: Uint8Array, aad: Uint8Array): AeadSealed {
  const polyKey = poly1305KeyGen(key, nonce);
  const ciphertext = chacha20Xor(key, 1, nonce, plaintext);
  const macData = concatBytes(aad, padTo16(aad.length), ciphertext, padTo16(ciphertext.length), le64(aad.length), le64(ciphertext.length));
  const tag = poly1305(polyKey, macData);
  return { ciphertext, tag };
}

export function aeadOpen(key: Uint8Array, nonce: Uint8Array, aad: Uint8Array, ciphertext: Uint8Array, tag: Uint8Array): Uint8Array | null {
  const polyKey = poly1305KeyGen(key, nonce);
  const macData = concatBytes(aad, padTo16(aad.length), ciphertext, padTo16(ciphertext.length), le64(aad.length), le64(ciphertext.length));
  const expected = poly1305(polyKey, macData);
  if (tag.length !== 16) return null;
  let diff = 0;
  for (let i = 0; i < 16; i++) diff |= tag[i] ^ expected[i];
  if (diff !== 0) return null;
  return chacha20Xor(key, 1, nonce, ciphertext);
}
