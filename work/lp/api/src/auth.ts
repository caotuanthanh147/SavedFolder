// /auth/<script_id>/init, /auth/<script_id>/payload, /auth/<script_id>/heartbeat
// per doc.md §5.3, §5.5, §8 (steps 7-11), §12 (watermark sessions).
//
// Wire formats (M3 interop, mirrored in DECISIONS-M1.md + CCP-1):
//   init success  : text/plain body = b64url( serverPub(32) | serverNonce(16) | ct | tag(16) )
//                   AEAD key = sessionKey, nonce = serverNonce[0..12),
//                   aad = utf8(scriptId) | serverPub | serverNonce
//                   sessionKey = HKDF-SHA256(ikm = X25519 shared, salt = clientNonce(16) | serverNonce(16), info = "session-key")
//   payload ref   : b64url( nonce(12) | ct | tag(16) ) sealing sessionId(16) | sessionKey(32) |
//                   buildHash(32) | watermark(16) | expiresAt(8 LE), sealed with refSealKey,
//                   aad = utf8(scriptId) — stateless session-key continuity, no schema change
//   payload success: text/plain body = b64url( nonce(12) | ct | tag(16) )
//                   AEAD key = payloadKey = HKDF(ikm = sessionKey, salt = buildHash(32),
//                   info = "payload-key" | watermark(16)), aad = utf8(scriptId) | sessionId(16)
//   failures      : signed JSON envelope with the §5.4 codes (AEAD cannot be
//                   produced before the handshake completes)

import { b64urlDecode, b64urlEncode, canonicalJson, fromHex, makeEnvelope, toHex, Code } from "./contracts";
import { constantTimeEqual, hkdfSha256, randomBytes, randomId, sha256Hex, Signer, utf8 } from "./crypto";
import { ApiConfig, AppContext, RequestInput, checkRequestGate, headerValue, readJsonBody, recordEvent, signedResponse } from "./flow";
import { hashHwid, hashKey, keyPassesChecksum, normalizeKey, projectHwidSalt } from "./keys";
import { aeadOpen, aeadSeal, concatBytes } from "./chacha";
import { generateX25519KeyPair, isAllZero, x25519SharedSecret } from "./x25519";
import { HEADERS } from "./contracts";

const HKDF_SESSION_INFO = utf8("session-key");
const HKDF_PAYLOAD_INFO = utf8("payload-key");
const REF_SEAL_SALT = utf8("m1-ref-seal");
const REF_SEAL_INFO = utf8("ref-key");
const REF_PLAINTEXT_LEN = 16 + 32 + 32 + 16 + 8;
const HELLO_LEN = 32 + 16;

interface ScriptRow {
  id: string;
  project_id: string;
  keyless: number;
  active_version: number;
}

interface KeyRow {
  id: string;
  project_id: string;
  tier: string;
  status: string;
  hwid_hash: string | null;
  note: string | null;
  discord_id: string | null;
  total_executions: number;
  expires_at: number | null;
}

interface SessionRow {
  id: string;
  key_id: string | null;
  script_id: string;
  version: number;
  watermark_id: string;
  expires_at: number;
}

interface VersionRow {
  version: number;
  blob_ref: string;
  build_hash: string;
  init_build: string;
}

export async function refSealKey(secret: string): Promise<Uint8Array> {
  return hkdfSha256(utf8(secret), REF_SEAL_SALT, REF_SEAL_INFO, 32);
}

async function deny(ctx: AppContext, config: ApiConfig, keyId: string | null, code: Code, eventType: string, detail: string): Promise<Response> {
  await recordEvent(ctx, keyId, eventType, detail);
  return signedResponse(makeEnvelope(code, null), config.signer, ctx.nowSec);
}

async function sessionKeyFrom(shared: Uint8Array, clientNonce: Uint8Array, serverNonce: Uint8Array): Promise<Uint8Array> {
  return hkdfSha256(shared, concatBytes(clientNonce, serverNonce), HKDF_SESSION_INFO, 32);
}

async function payloadKeyFrom(sessionKey: Uint8Array, buildHash: Uint8Array, watermark: Uint8Array): Promise<Uint8Array> {
  return hkdfSha256(sessionKey, buildHash, concatBytes(HKDF_PAYLOAD_INFO, watermark), 32);
}

function leU64(value: number): Uint8Array {
  const out = new Uint8Array(8);
  let v = Math.floor(value);
  for (let i = 0; i < 8; i++) {
    out[i] = v & 0xff;
    v = Math.floor(v / 256);
  }
  return out;
}

function readLeU64(bytes: Uint8Array): number {
  let v = 0;
  for (let i = 7; i >= 0; i--) v = v * 256 + bytes[i];
  return v;
}

function textResponse(bytes: Uint8Array, nowSec: number): Response {
  return new Response(b64urlEncode(bytes), {
    status: 200,
    headers: { "content-type": "text/plain", [HEADERS.serverTime]: String(Math.floor(nowSec)) },
  });
}

function validIdField(v: unknown, maxLen = 64): v is string {
  return typeof v === "string" && v.length > 0 && v.length <= maxLen;
}

function validIntField(v: unknown, max: number): v is number {
  return typeof v === "number" && Number.isInteger(v) && v >= 0 && v <= max;
}

function executorHwid(config: ApiConfig, input: RequestInput): string | null {
  for (const name of config.executorHwidHeaders) {
    const v = headerValue(input.headers, name);
    if (v !== null && v.length > 0 && v.length <= 256) return v;
  }
  return null;
}

async function protocolGate(ctx: AppContext, v: number): Promise<{ ok: boolean; minLoader: string | null }> {
  // The auth endpoints know the client's protocol version from the request's
  // `v` field. The gate row is protocol_versions[version = v] (owner answer Q1
  // seeds version "1" / handler "v1"). Unknown or retired version = kill
  // switch (doc §19); min_loader above the client loader version = update
  // required.
  const row = await ctx.db.first<{ min_loader: string | null; active: number }>(
    "SELECT min_loader, active FROM protocol_versions WHERE version = ?",
    [String(v)],
  );
  if (!row || row.active !== 1) return { ok: false, minLoader: null };
  return { ok: true, minLoader: row.min_loader };
}

function compareVersions(a: string, b: string): number {
  const pa = a.split(".").map((x) => parseInt(x, 10) || 0);
  const pb = b.split(".").map((x) => parseInt(x, 10) || 0);
  const n = Math.max(pa.length, pb.length);
  for (let i = 0; i < n; i++) {
    const d = (pa[i] ?? 0) - (pb[i] ?? 0);
    if (d !== 0) return d;
  }
  return 0;
}

export async function handleAuthInit(ctx: AppContext, config: ApiConfig, input: RequestInput, scriptId: string): Promise<Response> {
  const gate = await checkRequestGate(ctx, config, input);
  if (!gate.ok) {
    const extra: Record<string, string> = {};
    if (gate.retryAfterSec > 0) extra["retry-after"] = String(gate.retryAfterSec);
    return signedResponse(gate.envelope, config.signer, ctx.nowSec, extra);
  }

  if (!/^[0-9a-f]{32}$/.test(scriptId)) {
    return deny(ctx, config, null, "BAD_REQUEST", "validate_fail", "script-id");
  }

  const body = readJsonBody(input);
  if (!body) return deny(ctx, config, null, "BAD_REQUEST", "validate_fail", "body");

  const v = body.v;
  const keyRaw = typeof body.key === "string" ? body.key : "";
  const build = body.build;
  const placeId = body.place_id;
  const gameId = body.game_id;
  const userId = body.user_id;
  const hello = body.hello;

  if (v !== 1) return deny(ctx, config, null, "BAD_REQUEST", "validate_fail", "v");
  const protoGate = await protocolGate(ctx, 1);
  const lvHeader = headerValue(input.headers, HEADERS.lv) ?? "0";
  if (!protoGate.ok || (protoGate.minLoader !== null && compareVersions(lvHeader, protoGate.minLoader) < 0)) {
    return deny(ctx, config, null, "UPDATE_REQUIRED", "validate_fail", "loader-version");
  }
  if (keyRaw.length > 64) return deny(ctx, config, null, "BAD_REQUEST", "validate_fail", "key");
  if (!validIdField(build, 64)) return deny(ctx, config, null, "BAD_REQUEST", "validate_fail", "build");
  if (!validIntField(placeId, Number.MAX_SAFE_INTEGER)) return deny(ctx, config, null, "BAD_REQUEST", "validate_fail", "place_id");
  if (!validIntField(gameId, Number.MAX_SAFE_INTEGER)) return deny(ctx, config, null, "BAD_REQUEST", "validate_fail", "game_id");
  if (!validIntField(userId, Number.MAX_SAFE_INTEGER)) return deny(ctx, config, null, "BAD_REQUEST", "validate_fail", "user_id");

  let helloBytes: Uint8Array;
  try {
    helloBytes = b64urlDecode(typeof hello === "string" ? hello : "");
  } catch {
    return deny(ctx, config, null, "BAD_REQUEST", "validate_fail", "hello");
  }
  if (helloBytes.length !== HELLO_LEN) return deny(ctx, config, null, "BAD_REQUEST", "validate_fail", "hello");
  const clientPub = helloBytes.subarray(0, 32);
  const clientNonce = helloBytes.subarray(32, 48);
  if (isAllZero(clientPub)) return deny(ctx, config, null, "BAD_REQUEST", "validate_fail", "hello-pub");

  const script = await ctx.db.first<ScriptRow>("SELECT id, project_id, keyless, active_version FROM scripts WHERE id = ?", [scriptId]);
  if (!script) return deny(ctx, config, null, "SCRIPT_NOT_ALLOWED", "validate_fail", "script");

  const version = await ctx.db.first<VersionRow>(
    "SELECT version, blob_ref, build_hash, init_build FROM script_versions WHERE script_id = ? AND version = ?",
    [scriptId, script.active_version],
  );
  if (!version) return signedResponse(makeEnvelope("SERVER_ERROR", null), config.signer, ctx.nowSec);
  if (version.init_build !== build) {
    return deny(ctx, config, null, "UPDATE_REQUIRED", "validate_fail", "init-build");
  }

  const routed = await ctx.db.first<{ n: number }>("SELECT COUNT(*) AS n FROM script_games WHERE script_id = ?", [scriptId]);
  if (routed !== null && routed.n > 0) {
    const match = await ctx.db.first<{ n: number }>("SELECT COUNT(*) AS n FROM script_games WHERE script_id = ? AND game_id = ?", [scriptId, gameId]);
    if (!match || match.n === 0) {
      return deny(ctx, config, null, "SCRIPT_NOT_ALLOWED", "validate_fail", "game");
    }
  }

  const callerIpHash = await sha256Hex(config.pepper + "|ip|" + input.ip);
  const lockout = await ctx.limiter.blocked(`invalid:${callerIpHash}`, 5, 600);
  if (!lockout.ok) {
    await recordEvent(ctx, null, "tamper", "invalid-key-lockout");
    return signedResponse(makeEnvelope("RATE_LIMITED", null), config.signer, ctx.nowSec, {
      "retry-after": String(lockout.retryAfterSec),
    });
  }

  let keyRow: KeyRow | null = null;
  if (script.keyless === 0) {
    if (keyRaw.length === 0) return deny(ctx, config, null, "KEY_INVALID", "validate_fail", "key-missing");
    const key = normalizeKey(keyRaw);
    if (!keyPassesChecksum(key)) {
      await ctx.limiter.hit(`invalid:${callerIpHash}`, 5, 600);
      return deny(ctx, config, null, "KEY_INVALID", "validate_fail", "checksum");
    }
    const keyHash = await hashKey(key, config.pepper);
    keyRow = await ctx.db.first<KeyRow>(
      "SELECT id, project_id, tier, status, hwid_hash, note, discord_id, total_executions, expires_at FROM keys WHERE key_hash = ?",
      [keyHash],
    );
    if (!keyRow) {
      await ctx.limiter.hit(`invalid:${callerIpHash}`, 5, 600);
      return deny(ctx, config, null, "KEY_INVALID", "validate_fail", "not-found");
    }
    if (keyRow.status === "blacklisted") {
      return deny(ctx, config, keyRow.id, "KEY_BLACKLISTED", "validate_fail", "key-status");
    }
    if (keyRow.status !== "active") {
      await ctx.limiter.hit(`invalid:${callerIpHash}`, 5, 600);
      return deny(ctx, config, keyRow.id, "KEY_INVALID", "validate_fail", "key-status");
    }
    if (keyRow.expires_at !== null && keyRow.expires_at < ctx.nowSec) {
      return deny(ctx, config, keyRow.id, "KEY_EXPIRED", "validate_fail", "expired");
    }
    if (keyRow.project_id !== script.project_id) {
      return deny(ctx, config, keyRow.id, "SCRIPT_NOT_ALLOWED", "validate_fail", "script-project");
    }
    const entitled = await ctx.db.first<{ n: number }>("SELECT COUNT(*) AS n FROM key_scripts WHERE key_id = ? AND script_id = ?", [keyRow.id, scriptId]);
    if (!entitled || entitled.n === 0) {
      return deny(ctx, config, keyRow.id, "SCRIPT_NOT_ALLOWED", "validate_fail", "entitlement");
    }
  }

  const hwid = executorHwid(config, input);
  const salt = await projectHwidSalt(config.pepper, script.project_id);
  const hwidHash = hwid !== null ? await hashHwid(hwid, salt) : await hashHwid("", salt);
  const userIdHash = await sha256Hex(config.pepper + "|roblox_user|" + String(userId));

  const blacklistChecks: { sql: string; params: unknown[] }[] = [
    { sql: "SELECT id FROM blacklist WHERE kind = 'ip' AND value_hash = ?", params: [callerIpHash] },
    { sql: "SELECT id FROM blacklist WHERE kind = 'hwid' AND value_hash = ?", params: [hwidHash] },
  ];
  if (userId > 0) {
    blacklistChecks.push({ sql: "SELECT id FROM blacklist WHERE kind = 'roblox_user' AND value_hash = ?", params: [userIdHash] });
  }
  if (keyRow !== null && keyRow.discord_id !== null) {
    blacklistChecks.push({ sql: "SELECT id FROM blacklist WHERE kind = 'discord' AND value_hash = ?", params: [await sha256Hex(config.pepper + "|discord|" + keyRow.discord_id)] });
  }
  for (const check of blacklistChecks) {
    const hit = await ctx.db.first(check.sql, check.params);
    if (hit) return deny(ctx, config, keyRow?.id ?? null, "KEY_BLACKLISTED", "validate_fail", "blacklist");
  }

  const now = Math.floor(ctx.nowSec);
  if (keyRow !== null && hwid !== null) {
    const bind = await ctx.db.run(
      "UPDATE keys SET hwid_hash = ?, first_used_at = COALESCE(first_used_at, ?), last_used_at = ?, total_executions = total_executions + 1 WHERE id = ? AND (hwid_hash IS NULL OR hwid_hash = ?)",
      [hwidHash, now, now, keyRow.id, hwidHash],
    );
    if (bind.changes === 0) {
      return deny(ctx, config, keyRow.id, "HWID_MISMATCH", "validate_fail", "hwid");
    }
  } else if (keyRow !== null) {
    await ctx.db.run(
      "UPDATE keys SET first_used_at = COALESCE(first_used_at, ?), last_used_at = ?, total_executions = total_executions + 1 WHERE id = ?",
      [now, now, keyRow.id],
    );
  }

  const server = generateX25519KeyPair(randomBytes(32));
  let shared: Uint8Array;
  try {
    shared = x25519SharedSecret(server.privateKey, clientPub);
  } catch {
    return deny(ctx, config, null, "BAD_REQUEST", "validate_fail", "hello-small-order");
  }
  const serverNonce = randomBytes(16);
  const sessionKey = await sessionKeyFrom(shared, clientNonce, serverNonce);

  const sessionId = randomId();
  const watermarkId = randomId();
  const expiresAt = now + config.sessionTtlSec;

  await ctx.db.run(
    "INSERT INTO sessions (id, key_id, script_id, version, hwid_hash, ip_hash, roblox_user_id, place_id, watermark_id, created_at, expires_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
    [sessionId, keyRow?.id ?? null, scriptId, script.active_version, hwidHash, callerIpHash, userId > 0 ? userId : null, placeId, watermarkId, now, expiresAt],
  );

  const sessionIdRaw = fromHex(sessionId);
  const watermarkRaw = fromHex(watermarkId);
  const buildHashRaw = fromHex(version.build_hash);
  const refPlain = concatBytes(sessionIdRaw, sessionKey, buildHashRaw, watermarkRaw, leU64(expiresAt));
  const refNonce = randomBytes(12);
  const refSealed = aeadSeal(config.refSealKey, refNonce, refPlain, utf8(scriptId));
  const payloadRef = b64urlEncode(concatBytes(refNonce, refSealed.ciphertext, refSealed.tag));

  const sessionToken = b64urlEncode(sessionIdRaw);
  const responseJson = canonicalJson({
    session_token: sessionToken,
    session_expires_at: expiresAt,
    tier: keyRow?.tier ?? "free",
    auth_expire: keyRow?.expires_at ?? 0,
    discord_id: keyRow?.discord_id ?? null,
    note: keyRow?.note ?? null,
    build_hash: version.build_hash,
    watermark_id: watermarkId,
    payload_ref: payloadRef,
  });

  const aad = concatBytes(utf8(scriptId), server.publicKey, serverNonce);
  const sealed = aeadSeal(sessionKey, serverNonce.subarray(0, 12), utf8(responseJson), aad);
  const wire = concatBytes(server.publicKey, serverNonce, sealed.ciphertext, sealed.tag);

  await recordEvent(ctx, keyRow?.id ?? null, "validate_ok", "auth_init");
  return textResponse(wire, ctx.nowSec);
}

interface SealedRef {
  sessionIdRaw: Uint8Array;
  sessionKey: Uint8Array;
  buildHashRaw: Uint8Array;
  watermarkRaw: Uint8Array;
  expiresAt: number;
}

function openRef(refB64: string, sealKey: Uint8Array, scriptId: string): SealedRef | null {
  let raw: Uint8Array;
  try {
    raw = b64urlDecode(refB64);
  } catch {
    return null;
  }
  if (raw.length < 12 + REF_PLAINTEXT_LEN + 16) return null;
  const nonce = raw.subarray(0, 12);
  const ct = raw.subarray(12, raw.length - 16);
  const tag = raw.subarray(raw.length - 16);
  const plain = aeadOpen(sealKey, nonce, utf8(scriptId), ct, tag);
  if (plain === null || plain.length !== REF_PLAINTEXT_LEN) return null;
  return {
    sessionIdRaw: plain.subarray(0, 16),
    sessionKey: plain.subarray(16, 48),
    buildHashRaw: plain.subarray(48, 80),
    watermarkRaw: plain.subarray(80, 96),
    expiresAt: readLeU64(plain.subarray(96, 104)),
  };
}

async function killCheck(ctx: AppContext, session: SessionRow): Promise<Code | null> {
  if (session.expires_at < ctx.nowSec) return "KEY_EXPIRED";
  if (session.key_id === null) return null;
  const keyRow = await ctx.db.first<{ status: string; expires_at: number | null }>(
    "SELECT status, expires_at FROM keys WHERE id = ?",
    [session.key_id],
  );
  if (!keyRow) return "KEY_INVALID";
  if (keyRow.status === "blacklisted") return "KEY_BLACKLISTED";
  if (keyRow.status !== "active") return "KEY_INVALID";
  if (keyRow.expires_at !== null && keyRow.expires_at < ctx.nowSec) return "KEY_EXPIRED";
  return null;
}

function decodeSessionToken(token: unknown): Uint8Array | null {
  if (typeof token !== "string" || token.length === 0 || token.length > 64) return null;
  try {
    const raw = b64urlDecode(token);
    return raw.length === 16 ? raw : null;
  } catch {
    return null;
  }
}

export async function handleAuthPayload(ctx: AppContext, config: ApiConfig, input: RequestInput, scriptId: string): Promise<Response> {
  const gate = await checkRequestGate(ctx, config, input);
  if (!gate.ok) {
    const extra: Record<string, string> = {};
    if (gate.retryAfterSec > 0) extra["retry-after"] = String(gate.retryAfterSec);
    return signedResponse(gate.envelope, config.signer, ctx.nowSec, extra);
  }

  if (!/^[0-9a-f]{32}$/.test(scriptId)) {
    return deny(ctx, config, null, "BAD_REQUEST", "validate_fail", "script-id");
  }

  const body = readJsonBody(input);
  if (!body) return deny(ctx, config, null, "BAD_REQUEST", "validate_fail", "body");
  if (body.v !== 1) return deny(ctx, config, null, "BAD_REQUEST", "validate_fail", "v");

  const sessionIdRaw = decodeSessionToken(body.session_token);
  if (sessionIdRaw === null) return deny(ctx, config, null, "BAD_REQUEST", "validate_fail", "session_token");
  if (typeof body.payload_ref !== "string" || body.payload_ref.length === 0 || body.payload_ref.length > 1024) {
    return deny(ctx, config, null, "BAD_REQUEST", "validate_fail", "payload_ref");
  }

  const ref = openRef(body.payload_ref, config.refSealKey, scriptId);
  if (ref === null) return deny(ctx, config, null, "BAD_REQUEST", "validate_fail", "ref");
  if (!constantTimeEqual(ref.sessionIdRaw, sessionIdRaw)) {
    return deny(ctx, config, null, "KEY_INVALID", "validate_fail", "ref-session");
  }

  const sessionId = toHex(sessionIdRaw);
  const session = await ctx.db.first<SessionRow>(
    "SELECT id, key_id, script_id, version, watermark_id, expires_at FROM sessions WHERE id = ?",
    [sessionId],
  );
  if (!session || session.script_id !== scriptId) {
    return deny(ctx, config, null, "KEY_INVALID", "validate_fail", "session");
  }
  if (ref.expiresAt < ctx.nowSec) {
    return deny(ctx, config, session.key_id, "KEY_EXPIRED", "validate_fail", "session-expired");
  }

  const kill = await killCheck(ctx, session);
  if (kill !== null) {
    return deny(ctx, config, session.key_id, kill, "session_kill", "payload");
  }

  const version = await ctx.db.first<VersionRow & { build_hash: string; blob_ref: string; init_build: string }>(
    "SELECT version, blob_ref, build_hash, init_build FROM script_versions WHERE script_id = ? AND version = ?",
    [scriptId, session.version],
  );
  if (!version) {
    return deny(ctx, config, session.key_id, "UPDATE_REQUIRED", "validate_fail", "version-gone");
  }
  const buildHashRaw = fromHex(version.build_hash);
  if (!constantTimeEqual(buildHashRaw, ref.buildHashRaw)) {
    return deny(ctx, config, session.key_id, "UPDATE_REQUIRED", "validate_fail", "build-changed");
  }

  const limit = await ctx.limiter.hit(`payload:${sessionId}`, 5, 60);
  if (!limit.ok) {
    return signedResponse(makeEnvelope("RATE_LIMITED", null), config.signer, ctx.nowSec, {
      "retry-after": String(limit.retryAfterSec),
    });
  }

  const bundle = await config.bundleStore.get(version.blob_ref);
  if (bundle === null) {
    await recordEvent(ctx, session.key_id, "server_error", "bundle-missing");
    return signedResponse(makeEnvelope("SERVER_ERROR", null), config.signer, ctx.nowSec);
  }

  const script = await ctx.db.first<{ project_id: string }>("SELECT project_id FROM scripts WHERE id = ?", [scriptId]);
  const project = await ctx.db.first<{ signing_key_id: string }>("SELECT signing_key_id FROM projects WHERE id = ?", [script?.project_id ?? ""]);
  const signer = config.bundleSignerFor(script?.project_id ?? "", project?.signing_key_id ?? "");
  const bundleSig = await signer.sign(concatBytes(buildHashRaw, bundle));

  const responseJson = canonicalJson({
    build_hash: version.build_hash,
    bundle: b64urlEncode(bundle),
    bundle_sig: b64urlEncode(bundleSig),
  });

  const payloadKey = await payloadKeyFrom(ref.sessionKey, buildHashRaw, ref.watermarkRaw);
  const nonce = randomBytes(12);
  const aad = concatBytes(utf8(scriptId), sessionIdRaw);
  const sealed = aeadSeal(payloadKey, nonce, utf8(responseJson), aad);
  const wire = concatBytes(nonce, sealed.ciphertext, sealed.tag);

  await recordEvent(ctx, session.key_id, "validate_ok", "auth_payload");
  return textResponse(wire, ctx.nowSec);
}

export async function handleAuthHeartbeat(ctx: AppContext, config: ApiConfig, input: RequestInput, scriptId: string): Promise<Response> {
  const gate = await checkRequestGate(ctx, config, input);
  if (!gate.ok) {
    const extra: Record<string, string> = {};
    if (gate.retryAfterSec > 0) extra["retry-after"] = String(gate.retryAfterSec);
    return signedResponse(gate.envelope, config.signer, ctx.nowSec, extra);
  }

  if (!/^[0-9a-f]{32}$/.test(scriptId)) {
    return deny(ctx, config, null, "BAD_REQUEST", "validate_fail", "script-id");
  }

  const body = readJsonBody(input);
  if (!body) return deny(ctx, config, null, "BAD_REQUEST", "validate_fail", "body");
  if (body.v !== 1) return deny(ctx, config, null, "BAD_REQUEST", "validate_fail", "v");

  const sessionIdRaw = decodeSessionToken(body.session_token);
  if (sessionIdRaw === null) return deny(ctx, config, null, "BAD_REQUEST", "validate_fail", "session_token");

  const sessionId = toHex(sessionIdRaw);
  const session = await ctx.db.first<SessionRow>(
    "SELECT id, key_id, script_id, version, watermark_id, expires_at FROM sessions WHERE id = ?",
    [sessionId],
  );
  if (!session || session.script_id !== scriptId) {
    return deny(ctx, config, null, "KEY_INVALID", "validate_fail", "session");
  }

  const kill = await killCheck(ctx, session);
  if (kill !== null) {
    await recordEvent(ctx, session.key_id, "session_kill", "heartbeat");
    return signedResponse(makeEnvelope(kill, null), config.signer, ctx.nowSec);
  }

  await recordEvent(ctx, session.key_id, "validate_ok", "heartbeat");
  return signedResponse(makeEnvelope("KEY_VALID", { session_expires_at: session.expires_at }), config.signer, ctx.nowSec);
}

export async function signPayloadForTests(signer: Signer, buildHash: Uint8Array, bundle: Uint8Array): Promise<Uint8Array> {
  return signer.sign(concatBytes(buildHash, bundle));
}
