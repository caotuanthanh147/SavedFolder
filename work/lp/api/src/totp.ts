// RFC 6238 TOTP + RFC 4648 base32 — used by the dashboard's optional second
// factor (doc §16). Zero-dependency: HMAC-SHA1 via WebCrypto, matching the
// api/ tree's style. Test oracle = RFC 6238 Appendix B official vectors.

const B32_ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567";

export function base32Encode(bytes: Uint8Array): string {
  let bits = 0;
  let acc = 0;
  let out = "";
  for (const b of bytes) {
    acc = (acc << 8) | b;
    bits += 8;
    while (bits >= 5) {
      bits -= 5;
      out += B32_ALPHABET[(acc >> bits) & 31];
    }
  }
  if (bits > 0) out += B32_ALPHABET[(acc << (5 - bits)) & 31];
  return out;
}

export function base32Decode(s: string): Uint8Array {
  let bits = 0;
  let acc = 0;
  const out: number[] = [];
  for (const c of s.toUpperCase().replace(/=+$/, "")) {
    const v = B32_ALPHABET.indexOf(c);
    if (v < 0) throw new Error("invalid base32 character");
    acc = (acc << 5) | v;
    bits += 5;
    if (bits >= 8) {
      bits -= 8;
      out.push((acc >> bits) & 0xff);
    }
  }
  return new Uint8Array(out);
}

async function hmacSha1(key: Uint8Array, data: Uint8Array): Promise<Uint8Array> {
  const cryptoKey = await globalThis.crypto.subtle.importKey("raw", key as BufferSource, { name: "HMAC", hash: "SHA-1" }, false, ["sign"]);
  return new Uint8Array(await globalThis.crypto.subtle.sign("HMAC", cryptoKey, data as BufferSource));
}

export function utf8(s: string): Uint8Array {
  return new TextEncoder().encode(s);
}

export async function hotp(secret: Uint8Array, counter: number, digits = 6): Promise<string> {
  const msg = new Uint8Array(8);
  let c = counter;
  for (let i = 7; i >= 0; i--) {
    msg[i] = c & 0xff;
    c = Math.floor(c / 256);
  }
  const mac = await hmacSha1(secret, msg);
  const offset = mac[mac.length - 1] & 0xf;
  const code = (((mac[offset] & 0x7f) << 24) | (mac[offset + 1] << 16) | (mac[offset + 2] << 8) | mac[offset + 3]) % 10 ** digits;
  return String(code).padStart(digits, "0");
}

export async function totp(secret: Uint8Array, unixTime: number, step = 30, digits = 6): Promise<string> {
  return hotp(secret, Math.floor(unixTime / step), digits);
}

export function verifyWindow(code: string, expected: string): boolean {
  if (code.length !== expected.length) return false;
  let same = true;
  for (let i = 0; i < code.length; i++) {
    if (code.charCodeAt(i) !== expected.charCodeAt(i)) same = false;
  }
  return same;
}

export function otpauthUri(secretB32: string, issuer: string, account: string): string {
  return `otpauth://totp/${encodeURIComponent(issuer)}:${encodeURIComponent(account)}?secret=${secretB32}&issuer=${encodeURIComponent(issuer)}&algorithm=SHA1&digits=6&period=30`;
}
