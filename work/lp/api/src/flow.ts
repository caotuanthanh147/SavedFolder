import { HEADERS, MAX_BODY_BYTES, TS_WINDOW_SECONDS, canonicalJson, b64urlDecode, b64urlEncode, makeEnvelope, Envelope } from "./contracts";
import { Signer, hmacSha256, randomId, sha256, sha256Hex, utf8 } from "./crypto";
import { DbAdapter } from "./db";
import { BlobStore } from "./blobs";
import { NonceStore, RateLimiter } from "./state";

export interface AppContext {
  db: DbAdapter;
  limiter: RateLimiter;
  nonce: NonceStore;
  nowSec: number;
}

export interface RequestInput {
  method: string;
  path: string;
  headers: Record<string, string>;
  bodyBytes: Uint8Array;
  ip: string;
  colo: string;
}

export interface ApiConfig {
  pepper: string;
  proofKey: Uint8Array;
  signer: Signer;
  executorHwidHeaders: string[];
  statusActive: boolean;
  sessionTtlSec: number;
  refSealKey: Uint8Array;
  bundleStore: BlobStore;
  bundleSignerFor: (projectId: string, signingKeyId: string) => Signer;
}

const PROOF_LABEL = "m1-proof-v1";

export function headerValue(headers: Record<string, string>, name: string): string | null {
  const lower = name.toLowerCase();
  for (const k of Object.keys(headers)) {
    if (k.toLowerCase() === lower) return headers[k];
  }
  return null;
}

export function proofPayload(method: string, path: string, ts: string, nonce: string, bodyHashHex: string): Uint8Array {
  return utf8(`${PROOF_LABEL}|${method}|${path}|${ts}|${nonce}|${bodyHashHex}`);
}

export async function verifyProof(config: ApiConfig, input: RequestInput, ts: string, nonce: string): Promise<boolean> {
  const supplied = headerValue(input.headers, HEADERS.proof);
  if (!supplied) return false;
  let mac: Uint8Array;
  try {
    mac = b64urlDecode(supplied);
  } catch {
    return false;
  }
  if (mac.length !== 32) return false;
  const bodyHash = await sha256(input.bodyBytes);
  const bodyHashHex = Array.from(bodyHash, (b) => b.toString(16).padStart(2, "0")).join("");
  const payload = proofPayload(input.method, input.path, ts, nonce, bodyHashHex);
  const expected = await hmacSha256(config.proofKey, payload);
  let diff = 0;
  for (let i = 0; i < 32; i++) diff |= mac[i] ^ expected[i];
  return diff === 0;
}

export function extractTimestamp(input: RequestInput, nowSec: number): { ok: boolean; ts: number; raw: string } {
  const raw = headerValue(input.headers, HEADERS.ts);
  if (raw === null || !/^\d{1,12}$/.test(raw)) return { ok: false, ts: 0, raw: raw ?? "" };
  const ts = parseInt(raw, 10);
  if (Math.abs(nowSec - ts) > TS_WINDOW_SECONDS) return { ok: false, ts, raw };
  return { ok: true, ts, raw };
}

export function extractNonce(input: RequestInput): { ok: boolean; value: string } {
  const raw = headerValue(input.headers, HEADERS.nonce);
  if (raw === null) return { ok: false, value: "" };
  try {
    const decoded = b64urlDecode(raw);
    if (decoded.length !== 16) return { ok: false, value: "" };
    return { ok: true, value: raw };
  } catch {
    return { ok: false, value: "" };
  }
}

export function bodyWithinLimit(input: RequestInput): boolean {
  return input.bodyBytes.length <= MAX_BODY_BYTES;
}

export async function checkRequestGate(
  ctx: AppContext,
  config: ApiConfig,
  input: RequestInput,
): Promise<{ ok: true; ts: number; nonce: string } | { ok: false; envelope: Envelope; retryAfterSec: number }> {
  const tsCheck = extractTimestamp(input, ctx.nowSec);
  if (!tsCheck.ok) {
    return { ok: false, envelope: makeEnvelope("BAD_REQUEST", null), retryAfterSec: 0 };
  }
  const nonceCheck = extractNonce(input);
  if (!nonceCheck.ok) {
    return { ok: false, envelope: makeEnvelope("BAD_REQUEST", null), retryAfterSec: 0 };
  }
  const ipHash = await sha256Hex(config.pepper + "|ip|" + input.ip);
  const general = await ctx.limiter.hit(`ip:${ipHash}`, 60, 60);
  if (!general.ok) {
    return { ok: false, envelope: makeEnvelope("RATE_LIMITED", null), retryAfterSec: general.retryAfterSec };
  }
  const proofOk = await verifyProof(config, input, tsCheck.raw, nonceCheck.value);
  if (!proofOk) {
    await recordEvent(ctx, null, "validate_fail", "proof");
    return { ok: false, envelope: makeEnvelope("BAD_REQUEST", null), retryAfterSec: 0 };
  }
  const replayed = await ctx.nonce.seen(nonceCheck.value, ctx.nowSec + TS_WINDOW_SECONDS * 2);
  if (replayed) {
    await recordEvent(ctx, null, "validate_fail", "nonce-replay");
    return { ok: false, envelope: makeEnvelope("BAD_REQUEST", null), retryAfterSec: 0 };
  }
  return { ok: true, ts: tsCheck.ts, nonce: nonceCheck.value };
}

export async function recordEvent(ctx: AppContext, keyId: string | null, type: string, detail: string): Promise<void> {
  await ctx.db.run(
    "INSERT INTO events (id, key_id, type, detail, created_at) VALUES (?, ?, ?, ?, ?)",
    [randomId(), keyId, type, detail, Math.floor(ctx.nowSec)],
  );
}

export function signedResponse(envelope: Envelope, signer: Signer, nowSec: number, extraHeaders: Record<string, string> = {}): Promise<Response> {
  return (async () => {
    const ts = String(Math.floor(nowSec));
    const payload = utf8(`${envelope.code}|${envelope.message}|${canonicalJson(envelope.data ?? null)}|${ts}`);
    const signature = await signer.sign(payload);
    const sigB64 = b64urlEncode(signature);
    const headers: Record<string, string> = {
      "content-type": "application/json",
      [HEADERS.serverTime]: ts,
      [HEADERS.signature]: sigB64,
      ...extraHeaders,
    };
    return new Response(JSON.stringify(envelope), { status: 200, headers });
  })();
}

export function envelopeResponse(envelope: Envelope, status = 200, extraHeaders: Record<string, string> = {}): Response {
  const headers: Record<string, string> = { "content-type": "application/json", ...extraHeaders };
  if (envelope.code === "RATE_LIMITED") headers["retry-after"] = String(extraHeaders["retry-after"] ?? 60);
  return new Response(JSON.stringify(envelope), { status, headers });
}

export function readJsonBody(input: RequestInput): Record<string, unknown> | null {
  if (input.bodyBytes.length === 0) return null;
  try {
    const parsed = JSON.parse(new TextDecoder().decode(input.bodyBytes));
    if (typeof parsed !== "object" || parsed === null || Array.isArray(parsed)) return null;
    return parsed as Record<string, unknown>;
  } catch {
    return null;
  }
}

