export const CODES = [
  "KEY_VALID",
  "KEY_INVALID",
  "KEY_EXPIRED",
  "KEY_BLACKLISTED",
  "HWID_MISMATCH",
  "SCRIPT_NOT_ALLOWED",
  "RATE_LIMITED",
  "UPDATE_REQUIRED",
  "BAD_REQUEST",
  "SERVER_ERROR",
] as const;

export type Code = (typeof CODES)[number];

export const GENERIC_MESSAGES: Record<Code, string> = {
  KEY_VALID: "The provided key is valid.",
  KEY_INVALID: "The provided key is invalid.",
  KEY_EXPIRED: "The provided key has expired.",
  KEY_BLACKLISTED: "The provided key is blacklisted.",
  HWID_MISMATCH: "This key is bound to a different device.",
  SCRIPT_NOT_ALLOWED: "This key is not entitled to the requested script.",
  RATE_LIMITED: "Too many requests. Try again later.",
  UPDATE_REQUIRED: "Your loader is outdated. Update and retry.",
  BAD_REQUEST: "Malformed request.",
  SERVER_ERROR: "Internal error.",
};

export function isKnownCode(c: string): c is Code {
  return (CODES as readonly string[]).includes(c);
}

const B64URL_ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_";

export function b64urlEncode(bytes: Uint8Array): string {
  let out = "";
  for (let i = 0; i < bytes.length; i += 3) {
    const b0 = bytes[i];
    const b1 = i + 1 < bytes.length ? bytes[i + 1] : 0;
    const b2 = i + 2 < bytes.length ? bytes[i + 2] : 0;
    out += B64URL_ALPHABET[b0 >> 2];
    out += B64URL_ALPHABET[((b0 & 3) << 4) | (b1 >> 4)];
    if (i + 1 < bytes.length) out += B64URL_ALPHABET[((b1 & 15) << 2) | (b2 >> 6)];
    if (i + 2 < bytes.length) out += B64URL_ALPHABET[b2 & 63];
  }
  return out;
}

export function b64urlDecode(s: string): Uint8Array {
  const clean = s.replace(/=+$/, "");
  const out: number[] = [];
  let bits = 0;
  let acc = 0;
  for (const ch of clean) {
    const v = B64URL_ALPHABET.indexOf(ch);
    if (v < 0) throw new Error("invalid base64url character");
    acc = (acc << 6) | v;
    bits += 6;
    if (bits >= 8) {
      bits -= 8;
      out.push((acc >> bits) & 0xff);
    }
  }
  return new Uint8Array(out);
}

export function toHex(bytes: Uint8Array): string {
  return Array.from(bytes, (b) => b.toString(16).padStart(2, "0")).join("");
}

export function fromHex(hex: string): Uint8Array {
  if (hex.length % 2 !== 0 || !/^[0-9a-fA-F]*$/.test(hex)) {
    throw new Error("invalid hex");
  }
  const out = new Uint8Array(hex.length / 2);
  for (let i = 0; i < out.length; i++) out[i] = parseInt(hex.slice(i * 2, i * 2 + 2), 16);
  return out;
}

function canonicalValue(v: unknown): string {
  if (v === null) return "null";
  if (typeof v === "string") return JSON.stringify(v);
  if (typeof v === "number") {
    if (!Number.isInteger(v)) throw new Error("non-integer number in canonical JSON");
    return String(v);
  }
  if (typeof v === "boolean") return v ? "true" : "false";
  if (Array.isArray(v)) return "[" + v.map(canonicalValue).join(",") + "]";
  if (typeof v === "object") {
    const keys = Object.keys(v as Record<string, unknown>).sort();
    const body = keys
      .map((k) => JSON.stringify(k) + ":" + canonicalValue((v as Record<string, unknown>)[k]))
      .join(",");
    return "{" + body + "}";
  }
  throw new Error("unsupported canonical JSON value: " + typeof v);
}

export function canonicalJson(v: unknown): string {
  return canonicalValue(v);
}

export interface Envelope {
  code: Code;
  message: string;
  data: Record<string, unknown> | null;
}

export function makeEnvelope(code: Code, data: Record<string, unknown> | null, message?: string): Envelope {
  return { code, message: message ?? GENERIC_MESSAGES[code], data };
}

export const HEADERS = {
  ts: "x-ts",
  nonce: "x-nonce",
  lv: "x-lv",
  proof: "x-proof",
  serverTime: "x-ts",
  signature: "x-sig",
} as const;

export function jsonHeaders(extra: Record<string, string>): Record<string, string> {
  return { "content-type": "application/json", ...extra };
}

export const MAX_BODY_BYTES = 16 * 1024;

export const TS_WINDOW_SECONDS = 60;
