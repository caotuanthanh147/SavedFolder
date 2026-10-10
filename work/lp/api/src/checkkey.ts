import { HEADERS, makeEnvelope } from "./contracts";
import { sha256Hex } from "./crypto";
import { ApiConfig, AppContext, RequestInput, checkRequestGate, headerValue, readJsonBody, recordEvent, signedResponse } from "./flow";
import { hashKey, keyPassesChecksum, normalizeKey, projectHwidSalt, hashHwid } from "./keys";

interface KeyRow {
  id: string;
  project_id: string;
  status: string;
  hwid_hash: string | null;
  note: string | null;
  total_executions: number;
  expires_at: number | null;
}

interface ScriptRow {
  id: string;
  project_id: string;
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

export async function handleCheckKey(ctx: AppContext, config: ApiConfig, input: RequestInput): Promise<Response> {
  const gate = await checkRequestGate(ctx, config, input);
  if (!gate.ok) {
    const extra: Record<string, string> = {};
    if (gate.retryAfterSec > 0) extra["retry-after"] = String(gate.retryAfterSec);
    return signedResponse(gate.envelope, config.signer, ctx.nowSec, extra);
  }

  const body = readJsonBody(input);
  if (!body) return deny(ctx, config, null, "BAD_REQUEST", "validate_fail", "body");

  const keyRaw = typeof body.key === "string" ? body.key : "";
  const scriptId = typeof body.script_id === "string" ? body.script_id : "";
  const lv = typeof body.lv === "string" ? body.lv : "";

  if (keyRaw.length === 0 || keyRaw.length > 64 || scriptId.length !== 32 || !/^[0-9a-f]{32}$/.test(scriptId) || lv.length === 0 || lv.length > 16) {
    return deny(ctx, config, null, "BAD_REQUEST", "validate_fail", "fields");
  }

  const lvHeader = headerValue(input.headers, HEADERS.lv) ?? lv;
  const loaderGate = await minLoaderGate(ctx);
  if (loaderGate.kill || (loaderGate.minLoader !== null && compareVersions(lvHeader, loaderGate.minLoader) < 0)) {
    return deny(ctx, config, null, "UPDATE_REQUIRED", "validate_fail", "loader-version");
  }

  const callerIpHash = await sha256Hex(config.pepper + "|ip|" + input.ip);
  const lockout = await ctx.limiter.blocked(`invalid:${callerIpHash}`, 5, 600);
  if (!lockout.ok) {
    await recordEvent(ctx, null, "tamper", "invalid-key-lockout");
    return signedResponse(makeEnvelope("RATE_LIMITED", null), config.signer, ctx.nowSec, {
      "retry-after": String(lockout.retryAfterSec),
    });
  }

  const key = normalizeKey(keyRaw);
  if (!keyPassesChecksum(key)) {
    await invalidKeyPenaltyHit(ctx, config, input);
    return deny(ctx, config, null, "KEY_INVALID", "validate_fail", "checksum");
  }

  const keyHash = await hashKey(key, config.pepper);
  const keyRow = await ctx.db.first<KeyRow>(
    "SELECT id, project_id, status, hwid_hash, note, total_executions, expires_at FROM keys WHERE key_hash = ?",
    [keyHash],
  );
  if (!keyRow) {
    await invalidKeyPenaltyHit(ctx, config, input);
    return deny(ctx, config, null, "KEY_INVALID", "validate_fail", "not-found");
  }

  if (keyRow.status === "blacklisted") {
    return deny(ctx, config, keyRow.id, "KEY_BLACKLISTED", "validate_fail", "key-status");
  }
  if (keyRow.status !== "active") {
    await invalidKeyPenaltyHit(ctx, config, input);
    return deny(ctx, config, keyRow.id, "KEY_INVALID", "validate_fail", "key-status");
  }
  if (keyRow.expires_at !== null && keyRow.expires_at < ctx.nowSec) {
    return deny(ctx, config, keyRow.id, "KEY_EXPIRED", "validate_fail", "expired");
  }

  const script = await ctx.db.first<ScriptRow>("SELECT id, project_id FROM scripts WHERE id = ?", [scriptId]);
  if (!script || script.project_id !== keyRow.project_id) {
    return deny(ctx, config, keyRow.id, "SCRIPT_NOT_ALLOWED", "validate_fail", "script");
  }

  const entitled = await ctx.db.first<{ n: number }>("SELECT COUNT(*) AS n FROM key_scripts WHERE key_id = ? AND script_id = ?", [keyRow.id, scriptId]);
  if (!entitled || entitled.n === 0) {
    return deny(ctx, config, keyRow.id, "SCRIPT_NOT_ALLOWED", "validate_fail", "entitlement");
  }

  const hwid = executorHwid(config, input);
  const salt = await projectHwidSalt(config.pepper, keyRow.project_id);
  const hwidHash = hwid !== null ? await hashHwid(hwid, salt) : null;
  const ipHash = await sha256Hex(config.pepper + "|ip|" + input.ip);

  const blacklisted = hwidHash !== null
    ? await ctx.db.first("SELECT id FROM blacklist WHERE (kind = 'ip' AND value_hash = ?) OR (kind = 'hwid' AND value_hash = ?)", [ipHash, hwidHash])
    : await ctx.db.first("SELECT id FROM blacklist WHERE kind = 'ip' AND value_hash = ?", [ipHash]);
  if (blacklisted) {
    return deny(ctx, config, keyRow.id, "KEY_BLACKLISTED", "validate_fail", "blacklist");
  }

  const now = Math.floor(ctx.nowSec);
  if (hwidHash !== null) {
    const bind = await ctx.db.run(
      "UPDATE keys SET hwid_hash = ?, first_used_at = COALESCE(first_used_at, ?), last_used_at = ?, total_executions = total_executions + 1 WHERE id = ? AND (hwid_hash IS NULL OR hwid_hash = ?)",
      [hwidHash, now, now, keyRow.id, hwidHash],
    );
    if (bind.changes === 0) {
      return deny(ctx, config, keyRow.id, "HWID_MISMATCH", "validate_fail", "hwid");
    }
  } else {
    await ctx.db.run(
      "UPDATE keys SET first_used_at = COALESCE(first_used_at, ?), last_used_at = ?, total_executions = total_executions + 1 WHERE id = ?",
      [now, now, keyRow.id],
    );
  }

  await recordEvent(ctx, keyRow.id, "validate_ok", "check_key");
  const data = {
    note: keyRow.note,
    auth_expire: keyRow.expires_at ?? 0,
    total_executions: keyRow.total_executions + 1,
  };
  return signedResponse(makeEnvelope("KEY_VALID", data), config.signer, ctx.nowSec);
}

function executorHwid(config: ApiConfig, input: RequestInput): string | null {
  for (const name of config.executorHwidHeaders) {
    const v = headerValue(input.headers, name);
    if (v !== null && v.length > 0 && v.length <= 256) return v;
  }
  return null;
}

async function minLoaderGate(ctx: AppContext): Promise<{ kill: boolean; minLoader: string | null }> {
  // check_key is protocol-version-agnostic (doc §1.1 capture: the same SDK
  // calls check_key across auth protocol versions), so it gates on the least
  // strict requirement among ACTIVE protocol rows — retiring every row is the
  // kill switch (doc §19). An empty table means no protocol gating is
  // configured. Owner answer Q1 seeds version "1" / handler "v1".
  const rows = await ctx.db.all<{ min_loader: string | null; active: number }>(
    "SELECT min_loader, active FROM protocol_versions",
    [],
  );
  if (rows.length === 0) return { kill: false, minLoader: null };
  const active = rows.filter((r) => r.active === 1);
  if (active.length === 0) return { kill: true, minLoader: null };
  let min: string | null = null;
  for (const r of active) {
    if (r.min_loader !== null && (min === null || compareVersions(r.min_loader, min) < 0)) min = r.min_loader;
  }
  return { kill: false, minLoader: min };
}

async function invalidKeyPenaltyHit(ctx: AppContext, config: ApiConfig, input: RequestInput): Promise<void> {
  const ipHash = await sha256Hex(config.pepper + "|ip|" + input.ip);
  await ctx.limiter.hit(`invalid:${ipHash}`, 5, 600);
}

async function deny(
  ctx: AppContext,
  config: ApiConfig,
  keyId: string | null,
  code: "KEY_INVALID" | "KEY_EXPIRED" | "KEY_BLACKLISTED" | "HWID_MISMATCH" | "SCRIPT_NOT_ALLOWED" | "RATE_LIMITED" | "UPDATE_REQUIRED" | "BAD_REQUEST",
  eventType: string,
  detail: string,
): Promise<Response> {
  await recordEvent(ctx, keyId, eventType, detail);
  return signedResponse(makeEnvelope(code, null), config.signer, ctx.nowSec);
}
