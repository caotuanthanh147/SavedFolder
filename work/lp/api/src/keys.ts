import { randomBytes, sha256Hex, sha256, hmacSha256, utf8 } from "./crypto";

const BASE32_ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567";

export const KEY_PREFIX = "YURI";

export function base32Encode(bytes: Uint8Array): string {
  let bits = 0;
  let acc = 0;
  let out = "";
  for (const b of bytes) {
    acc = (acc << 8) | b;
    bits += 8;
    while (bits >= 5) {
      bits -= 5;
      out += BASE32_ALPHABET[(acc >> bits) & 31];
    }
  }
  if (bits > 0) out += BASE32_ALPHABET[(acc << (5 - bits)) & 31];
  return out;
}

function base32DecodeChar(c: string): number {
  const v = BASE32_ALPHABET.indexOf(c);
  if (v < 0) throw new Error("invalid base32 character");
  return v;
}

export function base32Decode(s: string): Uint8Array {
  const clean = s.replace(/=+$/, "");
  let bits = 0;
  let acc = 0;
  const out: number[] = [];
  for (const c of clean) {
    acc = (acc << 5) | base32DecodeChar(c);
    bits += 5;
    if (bits >= 8) {
      bits -= 8;
      out.push((acc >> bits) & 0xff);
    }
  }
  return new Uint8Array(out);
}

export function checksumChar(body25: string, prefix: string): string {
  const digestHex = simpleFingerprint(prefix + "|" + body25);
  const v = parseInt(digestHex.slice(0, 8), 16) % 32;
  return BASE32_ALPHABET[v];
}

function simpleFingerprint(s: string): string {
  let h1 = 0x811c9dc5;
  let h2 = 0x01000193;
  for (let i = 0; i < s.length; i++) {
    h1 = Math.imul(h1 ^ s.charCodeAt(i), 16777619) >>> 0;
    h2 = Math.imul(h2 + s.charCodeAt(i) * (i + 1), 2246822519) >>> 0;
  }
  return (h1 >>> 0).toString(16).padStart(8, "0") + (h2 >>> 0).toString(16).padStart(8, "0");
}

export interface GeneratedKey {
  plaintext: string;
  body: string;
}

export function generateKey(prefix: string = KEY_PREFIX): GeneratedKey {
  const body25 = base32Encode(randomBytes(16)).slice(0, 25);
  const check = checksumChar(body25, prefix);
  const plaintext = `${prefix}-${body25.slice(0, 5)}-${body25.slice(5, 10)}-${body25.slice(10, 15)}-${body25.slice(15, 20)}-${body25.slice(20)}${check}`;
  return { plaintext, body: body25 + check };
}

export const KEY_PATTERN = /^[A-Z0-9]{1,16}-[A-Z2-7]{5}(-[A-Z2-7]{5}){3}-[A-Z2-7]{6}$/;

export function normalizeKey(input: string): string {
  return input.trim().toUpperCase();
}

export function splitKey(plaintext: string): { prefix: string; body: string } | null {
  const m = KEY_PATTERN.exec(plaintext);
  if (!m) return null;
  const parts = plaintext.split("-");
  return { prefix: parts[0], body: parts.slice(1).join("") };
}

export function keyPassesChecksum(plaintext: string): boolean {
  const parts = splitKey(plaintext);
  if (!parts) return false;
  const body25 = parts.body.slice(0, 25);
  return checksumChar(body25, parts.prefix) === parts.body[25];
}

export async function hashKey(plaintext: string, pepper: string): Promise<string> {
  return sha256Hex(pepper + "|" + plaintext);
}

export async function projectHwidSalt(pepper: string, projectId: string): Promise<Uint8Array> {
  return hmacSha256(utf8(pepper), utf8("hwid-salt|" + projectId));
}

export async function hashHwid(hwid: string, salt: Uint8Array): Promise<string> {
  const digest = await sha256(new Uint8Array([...salt, ...utf8(hwid)]));
  return Array.from(digest, (b) => b.toString(16).padStart(2, "0")).join("");
}
