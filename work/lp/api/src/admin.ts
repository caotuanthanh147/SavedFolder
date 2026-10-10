import { makeEnvelope, b64urlDecode, fromHex } from "./contracts";
import { constantTimeEqual, randomId, sha256, sha256Hex } from "./crypto";
import { ApiConfig, AppContext, RequestInput, headerValue } from "./flow";
import { generateKey, hashKey, KEY_PREFIX, projectHwidSalt, hashHwid } from "./keys";

const TIERS = ["free", "paid", "lifetime", "reseller"] as const;

const RESET_COOLDOWN_SEC = 7 * 86400;
const RESET_MONTHLY_CAP = 2;

const BLACKLIST_KINDS = ["hwid", "ip", "roblox_user", "discord"] as const;

interface AdminRow {
  id: string;
  role: string;
  quota_keys: number | null;
  api_token_hash: string | null;
}

interface AuditRow {
  id: string;
  actor_id: string;
  action: string;
  target: string | null;
  detail: string | null;
  created_at: number;
}

function json(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), { status, headers: { "content-type": "application/json" } });
}

async function authenticate(ctx: AppContext, _config: ApiConfig, input: RequestInput): Promise<AdminRow | null> {
  const auth = headerValue(input.headers, "authorization");
  if (!auth || !auth.startsWith("Bearer ")) return null;
  const token = auth.slice(7).trim();
  if (token.length === 0 || token.length > 128) return null;
  // Owner answer Q2 (docowner.txt): format adm_<admin id>.<secret> with a
  // 32-byte CSPRNG secret in base64url (43 chars, no padding). Store only
  // SHA-256(secret); the id prefix enables one lookup + one constant-time
  // comparison and lets secret scanners spot leaks.
  const dot = token.indexOf(".");
  if (!token.startsWith("adm_") || dot < 4) return null;
  const adminId = token.slice(4, dot);
  const secret = token.slice(dot + 1);
  if (adminId.length === 0 || adminId.length > 64 || secret.length !== 43) return null;
  let secretBytes: Uint8Array;
  try {
    secretBytes = b64urlDecode(secret);
  } catch {
    return null;
  }
  if (secretBytes.length !== 32) return null;
  const row = await ctx.db.first<AdminRow>(
    "SELECT id, role, quota_keys, api_token_hash FROM admins WHERE id = ?",
    [adminId],
  );
  if (!row || !row.api_token_hash) return null;
  const expected = fromHex(row.api_token_hash);
  const actual = await sha256(secretBytes);
  return constantTimeEqual(actual, expected) ? row : null;
}

async function audit(ctx: AppContext, actorId: string, action: string, target: string | null, detail: string): Promise<void> {
  await ctx.db.run(
    "INSERT INTO audit_log (id, actor_id, action, target, detail, created_at) VALUES (?, ?, ?, ?, ?, ?)",
    [randomId(), actorId, action, target, detail, Math.floor(ctx.nowSec)],
  );
}

async function keysCreatedBy(ctx: AppContext, actorId: string): Promise<number> {
  const row = await ctx.db.first<{ n: number }>(
    "SELECT COUNT(*) AS n FROM keys WHERE created_by = ?",
    [actorId],
  );
  return row?.n ?? 0;
}

export async function handleAdminCreateKeys(ctx: AppContext, config: ApiConfig, input: RequestInput): Promise<Response> {
  const admin = await authenticate(ctx, config, input);
  if (!admin) return json({ error: "unauthorized" }, 401);
  const body = parseBody(input);
  if (!body) return json({ error: "bad_request" }, 400);

  const projectId = typeof body.project_id === "string" ? body.project_id : "";
  const tier = typeof body.tier === "string" ? body.tier : "";
  const count: unknown = body.count === undefined ? 1 : body.count;
  const days: unknown = body.days === undefined || body.days === null ? null : body.days;
  const note = body.note === undefined || body.note === null ? null : body.note;
  const scriptIds = Array.isArray(body.script_ids) ? body.script_ids.filter((s): s is string => typeof s === "string") : [];

  if (!/^[0-9a-f]{32}$/.test(projectId)) return json({ error: "bad_request", field: "project_id" }, 400);
  if (!(TIERS as readonly string[]).includes(tier)) return json({ error: "bad_request", field: "tier" }, 400);
  if (typeof count !== "number" || !Number.isInteger(count) || count < 1 || count > 500) return json({ error: "bad_request", field: "count" }, 400);
  if (days !== null && (typeof days !== "number" || !Number.isInteger(days) || days < 1 || days > 3650)) return json({ error: "bad_request", field: "days" }, 400);
  if (note !== null && (typeof note !== "string" || note.length > 256)) return json({ error: "bad_request", field: "note" }, 400);
  if (scriptIds.length === 0 || scriptIds.length > 100 || !scriptIds.every((s) => /^[0-9a-f]{32}$/.test(s))) {
    return json({ error: "bad_request", field: "script_ids" }, 400);
  }

  const project = await ctx.db.first<{ id: string }>("SELECT id FROM projects WHERE id = ?", [projectId]);
  if (!project) return json({ error: "not_found", field: "project_id" }, 404);

  const placeholders = scriptIds.map(() => "?").join(",");
  const scripts = await ctx.db.all<{ id: string }>(
    `SELECT id FROM scripts WHERE project_id = ? AND id IN (${placeholders})`,
    [projectId, ...scriptIds],
  );
  if (scripts.length !== scriptIds.length) return json({ error: "bad_request", field: "script_ids", what: "foreign" }, 400);

  if (admin.role === "reseller" && admin.quota_keys !== null) {
    const created = await keysCreatedBy(ctx, admin.id);
    if (created + count > admin.quota_keys) return json({ error: "quota_exceeded" }, 403);
  } else if (admin.role !== "owner" && admin.role !== "admin" && admin.role !== "reseller") {
    return json({ error: "forbidden" }, 403);
  }

  const expiresAt = days !== null ? Math.floor(ctx.nowSec) + (days as number) * 86400 : null;
  const created: { id: string; key: string }[] = [];
  const statements: { sql: string; params: unknown[] }[] = [];
  for (let i = 0; i < count; i++) {
    const generated = generateKey(KEY_PREFIX);
    const keyId = randomId();
    const keyHash = await hashKey(generated.plaintext, config.pepper);
    statements.push({
      sql: "INSERT INTO keys (id, project_id, key_hash, tier, status, note, total_executions, created_by, created_at, expires_at) VALUES (?, ?, ?, ?, 'active', ?, 0, ?, ?, ?)",
      params: [keyId, projectId, keyHash, tier, note, admin.id, Math.floor(ctx.nowSec), expiresAt],
    });
    for (const scriptId of scriptIds) {
      statements.push({
        sql: "INSERT INTO key_scripts (key_id, script_id) VALUES (?, ?)",
        params: [keyId, scriptId],
      });
    }
    created.push({ id: keyId, key: generated.plaintext });
  }
  await ctx.db.batch(statements);
  await audit(ctx, admin.id, "admin.key.create", projectId, JSON.stringify({ count, tier, days, scripts: scriptIds }));
  return json({ keys: created }, 201);
}

export async function handleAdminPatchKey(ctx: AppContext, config: ApiConfig, input: RequestInput, keyId: string): Promise<Response> {
  const admin = await authenticate(ctx, config, input);
  if (!admin) return json({ error: "unauthorized" }, 401);
  if (admin.role !== "owner" && admin.role !== "admin") return json({ error: "forbidden" }, 403);
  const body = parseBody(input);
  if (!body) return json({ error: "bad_request" }, 400);

  const existing = await ctx.db.first<{ id: string; expires_at: number | null }>("SELECT id, expires_at FROM keys WHERE id = ?", [keyId]);
  if (!existing) return json({ error: "not_found" }, 404);

  const updates: string[] = [];
  const params: unknown[] = [];
  if (body.tier !== undefined) {
    if (typeof body.tier !== "string" || !(TIERS as readonly string[]).includes(body.tier)) return json({ error: "bad_request", field: "tier" }, 400);
    updates.push("tier = ?");
    params.push(body.tier);
  }
  if (body.note !== undefined) {
    if (body.note !== null && (typeof body.note !== "string" || body.note.length > 256)) return json({ error: "bad_request", field: "note" }, 400);
    updates.push("note = ?");
    params.push(body.note);
  }
  if (body.extend_days !== undefined) {
    if (typeof body.extend_days !== "number" || !Number.isInteger(body.extend_days) || body.extend_days < 1 || body.extend_days > 3650) return json({ error: "bad_request", field: "extend_days" }, 400);
    const base = existing.expires_at !== null ? Math.max(existing.expires_at, Math.floor(ctx.nowSec)) : Math.floor(ctx.nowSec);
    updates.push("expires_at = ?");
    params.push(base + (body.extend_days as number) * 86400);
  }
  if (updates.length === 0) return json({ error: "bad_request", field: "none" }, 400);
  params.push(keyId);
  await ctx.db.run(`UPDATE keys SET ${updates.join(", ")} WHERE id = ?`, params);
  await audit(ctx, admin.id, "admin.key.update", keyId, JSON.stringify(body));
  return json({ ok: true });
}

export async function handleAdminRevokeKey(ctx: AppContext, config: ApiConfig, input: RequestInput, keyId: string): Promise<Response> {
  const admin = await authenticate(ctx, config, input);
  if (!admin) return json({ error: "unauthorized" }, 401);
  if (admin.role !== "owner" && admin.role !== "admin") return json({ error: "forbidden" }, 403);
  const res = await ctx.db.run("UPDATE keys SET status = 'revoked' WHERE id = ?", [keyId]);
  if (res.changes === 0) return json({ error: "not_found" }, 404);
  await audit(ctx, admin.id, "admin.key.revoke", keyId, "");
  return json({ ok: true });
}

export async function handleAdminResetHwid(ctx: AppContext, config: ApiConfig, input: RequestInput, keyId: string): Promise<Response> {
  const admin = await authenticate(ctx, config, input);
  if (!admin) return json({ error: "unauthorized" }, 401);
  if (admin.role !== "owner" && admin.role !== "admin") return json({ error: "forbidden" }, 403);

  const key = await ctx.db.first<{ id: string; last_reset_at: number | null }>("SELECT id, last_reset_at FROM keys WHERE id = ?", [keyId]);
  if (!key) return json({ error: "not_found" }, 404);

  if (key.last_reset_at !== null && key.last_reset_at + RESET_COOLDOWN_SEC > ctx.nowSec) {
    const retryAfter = Math.ceil(key.last_reset_at + RESET_COOLDOWN_SEC - ctx.nowSec);
    return new Response(JSON.stringify(makeEnvelope("RATE_LIMITED", { retry_after_sec: retryAfter })), {
      status: 429,
      headers: { "content-type": "application/json", "retry-after": String(retryAfter) },
    });
  }

  const since = Math.floor(ctx.nowSec) - 30 * 86400;
  const monthCount = await ctx.db.first<{ n: number }>(
    "SELECT COUNT(*) AS n FROM audit_log WHERE action = 'admin.key.reset_hwid' AND target = ? AND created_at > ?",
    [keyId, since],
  );
  if ((monthCount?.n ?? 0) >= RESET_MONTHLY_CAP) {
    return json({ error: "monthly_cap_exceeded" }, 429);
  }

  const res = await ctx.db.run(
    "UPDATE keys SET hwid_hash = NULL, hwid_resets = hwid_resets + 1, last_reset_at = ? WHERE id = ?",
    [Math.floor(ctx.nowSec), keyId],
  );
  if (res.changes === 0) return json({ error: "not_found" }, 404);
  await audit(ctx, admin.id, "admin.key.reset_hwid", keyId, "");
  return json({ ok: true });
}

export async function handleAdminAudit(ctx: AppContext, config: ApiConfig, input: RequestInput): Promise<Response> {
  const admin = await authenticate(ctx, config, input);
  if (!admin) return json({ error: "unauthorized" }, 401);
  if (admin.role !== "owner" && admin.role !== "admin") return json({ error: "forbidden" }, 403);
  const rows = await ctx.db.all<AuditRow>(
    "SELECT id, actor_id, action, target, detail, created_at FROM audit_log ORDER BY created_at DESC LIMIT 200",
    [],
  );
  return json({ entries: rows });
}

export async function handleAdminNodes(ctx: AppContext, config: ApiConfig, input: RequestInput): Promise<Response> {
  const admin = await authenticate(ctx, config, input);
  if (!admin) return json({ error: "unauthorized" }, 401);
  if (admin.role !== "owner" && admin.role !== "admin") return json({ error: "forbidden" }, 403);
  const body = parseBody(input);
  if (!body) return json({ error: "bad_request" }, 400);
  const action = body.action === "disable" ? "disable" : "add";
  const hostname = typeof body.hostname === "string" ? body.hostname : "";
  const region = body.region === undefined || body.region === null ? null : body.region;
  if (!/^[a-z0-9.-]{3,253}\.[a-z]{2,}$/i.test(hostname)) return json({ error: "bad_request", field: "hostname" }, 400);
  if (region !== null && (typeof region !== "string" || region.length > 32)) return json({ error: "bad_request", field: "region" }, 400);

  if (action === "add") {
    const existing = await ctx.db.first<{ id: string; active: number }>("SELECT id, active FROM nodes WHERE hostname = ?", [hostname]);
    if (existing) {
      await ctx.db.run("UPDATE nodes SET active = 1, region = ? WHERE id = ?", [region ?? null, existing.id]);
      await audit(ctx, admin.id, "admin.node.add", existing.id, hostname);
      return json({ ok: true, id: existing.id, reactivated: true });
    }
    const id = randomId();
    await ctx.db.run("INSERT INTO nodes (id, hostname, region, active) VALUES (?, ?, ?, 1)", [id, hostname, region]);
    await audit(ctx, admin.id, "admin.node.add", id, hostname);
    return json({ ok: true, id }, 201);
  }

  const res = await ctx.db.run("UPDATE nodes SET active = 0 WHERE hostname = ?", [hostname]);
  if (res.changes === 0) return json({ error: "not_found" }, 404);
  await audit(ctx, admin.id, "admin.node.disable", hostname, "");
  return json({ ok: true });
}

export async function handleAdminProtocolVersions(ctx: AppContext, config: ApiConfig, input: RequestInput): Promise<Response> {
  const admin = await authenticate(ctx, config, input);
  if (!admin) return json({ error: "unauthorized" }, 401);
  if (admin.role !== "owner" && admin.role !== "admin") return json({ error: "forbidden" }, 403);
  const body = parseBody(input);
  if (!body) return json({ error: "bad_request" }, 400);
  const action = body.action === "retire" ? "retire" : "register";
  const version = typeof body.version === "string" ? body.version : "";
  const handler = typeof body.handler === "string" ? body.handler : "";
  const minLoader = body.min_loader === undefined || body.min_loader === null ? null : body.min_loader;
  if (!/^[0-9a-z.-]{1,16}$/i.test(version)) return json({ error: "bad_request", field: "version" }, 400);
  if (action === "register") {
    if (!/^[a-z_]{1,32}$/i.test(handler)) return json({ error: "bad_request", field: "handler" }, 400);
    if (minLoader !== null && (typeof minLoader !== "string" || !/^\d+\.\d+\.\d+$/.test(minLoader))) {
      return json({ error: "bad_request", field: "min_loader" }, 400);
    }
  }

  if (action === "register") {
    await ctx.db.run(
      "INSERT INTO protocol_versions (version, handler, min_loader, active) VALUES (?, ?, ?, 1) ON CONFLICT(version) DO UPDATE SET handler = excluded.handler, min_loader = excluded.min_loader, active = 1",
      [version, handler, minLoader],
    );
    await audit(ctx, admin.id, "admin.protocol.register", version, handler);
    return json({ ok: true }, 201);
  }

  const res = await ctx.db.run("UPDATE protocol_versions SET active = 0 WHERE version = ?", [version]);
  if (res.changes === 0) return json({ error: "not_found" }, 404);
  await audit(ctx, admin.id, "admin.protocol.retire", version, "");
  return json({ ok: true });
}

export async function handleAdminScriptVersion(ctx: AppContext, config: ApiConfig, input: RequestInput, scriptId: string): Promise<Response> {
  const admin = await authenticate(ctx, config, input);
  if (!admin) return json({ error: "unauthorized" }, 401);
  if (admin.role !== "owner" && admin.role !== "admin") return json({ error: "forbidden" }, 403);
  if (!/^[0-9a-f]{32}$/.test(scriptId)) return json({ error: "bad_request" }, 400);
  const body = parseBody(input);
  if (!body) return json({ error: "bad_request" }, 400);

  const buildHash = typeof body.build_hash === "string" ? body.build_hash : "";
  const blobRef = typeof body.blob_ref === "string" ? body.blob_ref : "";
  const initBuild = typeof body.init_build === "string" ? body.init_build : "";
  const notes = body.notes === undefined || body.notes === null ? null : body.notes;
  const activate = body.activate === true;
  if (!/^[0-9a-f]{64}$/.test(buildHash)) return json({ error: "bad_request", field: "build_hash" }, 400);
  if (blobRef.length === 0 || blobRef.length > 256) return json({ error: "bad_request", field: "blob_ref" }, 400);
  if (initBuild.length === 0 || initBuild.length > 64) return json({ error: "bad_request", field: "init_build" }, 400);
  if (notes !== null && (typeof notes !== "string" || notes.length > 256)) return json({ error: "bad_request", field: "notes" }, 400);

  const script = await ctx.db.first<{ id: string; active_version: number }>(
    "SELECT id, active_version FROM scripts WHERE id = ?",
    [scriptId],
  );
  if (!script) return json({ error: "not_found" }, 404);

  const maxRow = await ctx.db.first<{ maxv: number }>("SELECT COALESCE(MAX(version), 0) AS maxv FROM script_versions WHERE script_id = ?", [scriptId]);
  const version = (maxRow?.maxv ?? 0) + 1;

  await ctx.db.run(
    "INSERT INTO script_versions (script_id, version, blob_ref, build_hash, init_build, notes, created_at) VALUES (?, ?, ?, ?, ?, ?, ?)",
    [scriptId, version, blobRef, buildHash, initBuild, notes, Math.floor(ctx.nowSec)],
  );
  if (activate) {
    await ctx.db.run("UPDATE scripts SET active_version = ? WHERE id = ?", [version, scriptId]);
  }
  await audit(ctx, admin.id, "admin.script.version", scriptId, JSON.stringify({ version, build_hash: buildHash, activate }));
  return json({ ok: true, version }, 201);
}

export async function handleAdminScriptActivate(ctx: AppContext, config: ApiConfig, input: RequestInput, scriptId: string): Promise<Response> {
  const admin = await authenticate(ctx, config, input);
  if (!admin) return json({ error: "unauthorized" }, 401);
  if (admin.role !== "owner" && admin.role !== "admin") return json({ error: "forbidden" }, 403);
  if (!/^[0-9a-f]{32}$/.test(scriptId)) return json({ error: "bad_request" }, 400);
  const body = parseBody(input);
  if (!body) return json({ error: "bad_request" }, 400);
  if (typeof body.version !== "number" || !Number.isInteger(body.version) || body.version < 1) {
    return json({ error: "bad_request", field: "version" }, 400);
  }
  const exists = await ctx.db.first<{ n: number }>(
    "SELECT COUNT(*) AS n FROM script_versions WHERE script_id = ? AND version = ?",
    [scriptId, body.version],
  );
  if (!exists || exists.n === 0) return json({ error: "not_found" }, 404);
  await ctx.db.run("UPDATE scripts SET active_version = ? WHERE id = ?", [body.version, scriptId]);
  await audit(ctx, admin.id, "admin.script.activate", scriptId, String(body.version));
  return json({ ok: true });
}

export async function handleAdminBlacklist(ctx: AppContext, config: ApiConfig, input: RequestInput): Promise<Response> {
  const admin = await authenticate(ctx, config, input);
  if (!admin) return json({ error: "unauthorized" }, 401);
  if (admin.role !== "owner" && admin.role !== "admin") return json({ error: "forbidden" }, 403);
  const body = parseBody(input);
  if (!body) return json({ error: "bad_request" }, 400);
  const kind = typeof body.kind === "string" ? body.kind : "";
  const value = typeof body.value === "string" ? body.value : "";
  const reason = body.reason === undefined || body.reason === null ? null : body.reason;
  const projectId = body.project_id === undefined || body.project_id === null ? null : body.project_id;
  if (!(BLACKLIST_KINDS as readonly string[]).includes(kind)) return json({ error: "bad_request", field: "kind" }, 400);
  if (value.length === 0 || value.length > 256) return json({ error: "bad_request", field: "value" }, 400);
  if (reason !== null && (typeof reason !== "string" || reason.length > 256)) return json({ error: "bad_request", field: "reason" }, 400);

  let valueHash: string;
  if (kind === "hwid") {
    if (projectId === null || typeof projectId !== "string" || !/^[0-9a-f]{32}$/.test(projectId)) {
      return json({ error: "bad_request", field: "project_id" }, 400);
    }
    valueHash = await hashHwid(value, await projectHwidSalt(config.pepper, projectId));
  } else if (kind === "ip") {
    valueHash = await sha256Hex(config.pepper + "|ip|" + value);
  } else if (kind === "roblox_user") {
    valueHash = await sha256Hex(config.pepper + "|roblox_user|" + value);
  } else {
    valueHash = await sha256Hex(config.pepper + "|discord|" + value);
  }

  const existing = await ctx.db.first<{ id: string }>("SELECT id FROM blacklist WHERE kind = ? AND value_hash = ?", [kind, valueHash]);
  if (existing) return json({ ok: true, id: existing.id, already: true });
  const id = randomId();
  await ctx.db.run("INSERT INTO blacklist (id, kind, value_hash, reason, created_by, created_at) VALUES (?, ?, ?, ?, ?, ?)", [
    id,
    kind,
    valueHash,
    reason,
    admin.id,
    Math.floor(ctx.nowSec),
  ]);
  await audit(ctx, admin.id, "admin.blacklist.add", id, kind);
  return json({ ok: true, id }, 201);
}

export async function handleAdminAnalytics(ctx: AppContext, config: ApiConfig, input: RequestInput): Promise<Response> {
  const admin = await authenticate(ctx, config, input);
  if (!admin) return json({ error: "unauthorized" }, 401);
  if (admin.role !== "owner" && admin.role !== "admin") return json({ error: "forbidden" }, 403);
  const since = Math.floor(ctx.nowSec) - 86400;
  const [keysActive, keysRevoked, sessions24h, sessionsLive, ok24h, fail24h, tamper24h] = await Promise.all([
    ctx.db.first<{ n: number }>("SELECT COUNT(*) AS n FROM keys WHERE status = 'active'", []),
    ctx.db.first<{ n: number }>("SELECT COUNT(*) AS n FROM keys WHERE status = 'revoked'", []),
    ctx.db.first<{ n: number }>("SELECT COUNT(*) AS n FROM sessions WHERE created_at > ?", [since]),
    ctx.db.first<{ n: number }>("SELECT COUNT(*) AS n FROM sessions WHERE expires_at > ?", [Math.floor(ctx.nowSec)]),
    ctx.db.first<{ n: number }>("SELECT COUNT(*) AS n FROM events WHERE type = 'validate_ok' AND created_at > ?", [since]),
    ctx.db.first<{ n: number }>("SELECT COUNT(*) AS n FROM events WHERE type = 'validate_fail' AND created_at > ?", [since]),
    ctx.db.first<{ n: number }>("SELECT COUNT(*) AS n FROM events WHERE type = 'tamper' AND created_at > ?", [since]),
  ]);
  return json({
    window: "24h",
    keys_active: keysActive?.n ?? 0,
    keys_revoked: keysRevoked?.n ?? 0,
    sessions_24h: sessions24h?.n ?? 0,
    sessions_live: sessionsLive?.n ?? 0,
    validate_ok_24h: ok24h?.n ?? 0,
    validate_fail_24h: fail24h?.n ?? 0,
    tamper_24h: tamper24h?.n ?? 0,
  });
}

function parseBody(input: RequestInput): Record<string, unknown> | null {
  if (input.bodyBytes.length === 0) return null;
  try {
    const parsed = JSON.parse(new TextDecoder().decode(input.bodyBytes));
    if (typeof parsed !== "object" || parsed === null || Array.isArray(parsed)) return null;
    return parsed as Record<string, unknown>;
  } catch {
    return null;
  }
}
