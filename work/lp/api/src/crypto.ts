import { b64urlDecode, b64urlEncode, toHex } from "./contracts";

export const subtle = globalThis.crypto.subtle;

export function randomBytes(n: number): Uint8Array {
  const b = new Uint8Array(n);
  globalThis.crypto.getRandomValues(b);
  return b;
}

export function randomId(): string {
  return toHex(randomBytes(16));
}

export function utf8(s: string): Uint8Array {
  return new TextEncoder().encode(s);
}

export async function sha256(bytes: Uint8Array): Promise<Uint8Array> {
  return new Uint8Array(await subtle.digest("SHA-256", bytes as BufferSource));
}

export async function sha256Hex(s: string | Uint8Array): Promise<string> {
  return toHex(await sha256(typeof s === "string" ? utf8(s) : s));
}

async function hmacKey(raw: Uint8Array, usage: KeyUsage[]): Promise<CryptoKey> {
  return subtle.importKey("raw", raw as BufferSource, { name: "HMAC", hash: "SHA-256" }, false, usage);
}

export async function hmacSha256(key: Uint8Array, data: Uint8Array): Promise<Uint8Array> {
  const k = await hmacKey(key, ["sign"]);
  return new Uint8Array(await subtle.sign("HMAC", k, data as BufferSource));
}

export async function hmacVerify(key: Uint8Array, data: Uint8Array, mac: Uint8Array): Promise<boolean> {
  if (mac.length !== 32) return false;
  const k = await hmacKey(key, ["verify"]);
  return subtle.verify("HMAC", k, mac as BufferSource, data as BufferSource);
}

export function constantTimeEqual(a: Uint8Array, b: Uint8Array): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a[i] ^ b[i];
  return diff === 0;
}

export interface SigningKeys {
  privateKeyPkcs8: Uint8Array;
  publicKeyRaw: Uint8Array;
}

export async function generateSigningKeys(): Promise<SigningKeys> {
  const pair = (await subtle.generateKey({ name: "Ed25519" }, true, ["sign", "verify"])) as CryptoKeyPair;
  const pkcs8 = new Uint8Array(await subtle.exportKey("pkcs8", pair.privateKey));
  const raw = new Uint8Array(await subtle.exportKey("raw", pair.publicKey));
  return { privateKeyPkcs8: pkcs8, publicKeyRaw: raw };
}

export interface Signer {
  sign(payload: Uint8Array): Promise<Uint8Array>;
}

export interface Verifier {
  verify(payload: Uint8Array, signature: Uint8Array): Promise<boolean>;
}

export async function makeSigner(pkcs8B64url: string): Promise<Signer> {
  const key = await subtle.importKey("pkcs8", b64urlDecode(pkcs8B64url) as BufferSource, { name: "Ed25519" }, false, ["sign"]);
  return {
    async sign(payload) {
      return new Uint8Array(await subtle.sign("Ed25519", key, payload as BufferSource));
    },
  };
}

export async function makeVerifier(publicKeyB64url: string): Promise<Verifier> {
  const key = await subtle.importKey("raw", b64urlDecode(publicKeyB64url) as BufferSource, { name: "Ed25519" }, false, ["verify"]);
  return {
    async verify(payload, signature) {
      try {
        return await subtle.verify("Ed25519", key, signature as BufferSource, payload as BufferSource);
      } catch {
        return false;
      }
    },
  };
}

export function b64urlOf(bytes: Uint8Array): string {
  return b64urlEncode(bytes);
}

export async function hkdfSha256(ikm: Uint8Array, salt: Uint8Array, info: Uint8Array, length: number): Promise<Uint8Array> {
  const baseKey = await subtle.importKey("raw", ikm as BufferSource, "HKDF", false, ["deriveBits"]);
  const bits = await subtle.deriveBits(
    { name: "HKDF", hash: "SHA-256", salt: salt as BufferSource, info: info as BufferSource },
    baseKey,
    length * 8,
  );
  return new Uint8Array(bits);
}
