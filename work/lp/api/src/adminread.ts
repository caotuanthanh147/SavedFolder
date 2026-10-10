import { ApiConfig, AppContext, RequestInput } from "./flow";
import { authenticate } from "./admin";

// CCP-2 additive read endpoints (see CCP-M9-M11.md): doc §16 dashboard pages
// require listing data the §16 endpoint table never defined. These are read-
// only, owner/admin-gated (reseller: own keys only), never return key hashes
// or tokens. Marked additive: the owner may reject them without breaking the
// contract, in which case the dashboard falls back to audit-log-derived views.

interface KeyRow {
  id: string;
  project_id: string;
  tier: string;
  status: string;
  hwid_hash: string | null;
  hwid_resets: number;
  discord_id: string | null;
  roblox_user_id: number | null;
  note: string | null;
  total_executions: number;
  created_by: string;
  created_at: number;
  expires_at: number | null;
  first_used_at: number | null;
  last_used_at: number | null;
}

function json(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), { status, headers: { "content-type": "application/json" } });
}

function parseLimitOffset(q: Record<string, string>): { limit: number; offset: number } {
  const limit = Math.min(Math.max(parseInt(q.limit ?? "50", 10) || 50, 1), 200);
  const offset = Math.min(Math.max(parseInt(q.offset ?? "0", 10) || 0, 0), 100000);
  return { limit, offset };
}
function queryOf(input: RequestInput): Record<string, string> {
  const qIndex = input.path.indexOf("?");
  if (qIndex < 0) return {};
  const out: Record<string, string> = {};
  for (const pair of input.path.slice(qIndex + 1).split("&")) {
    const eq = pair.indexOf("=");
    if (eq > 0) out[decodeURIComponent(pair.slice(0, eq))] = decodeURIComponent(pair.slice(eq + 1));
  }
  return out;
}

export async function handleAdminListKeys(ctx: AppContext, _config: ApiConfig, input: RequestInput): Promise<Response> {
  const admin = await authenticate(ctx, _config, input);
  if (!admin) return json({ error: "unauthorized" }, 401);
  if (admin.role !== "owner" && admin.role !== "admin" && admin.role !== "reseller" && admin.role !== "support") {
    return json({ error: "forbidden" }, 403);
  }
  const q = queryOf(input);
  const { limit, offset } = parseLimitOffset(q);
  const where: string[] = [];
  const params: unknown[] = [];
  if (q.project_id && /^[0-9a-f]{32}$/.test(q.project_id)) {
    where.push("project_id = ?");
    params.push(q.project_id);
  }
  if (q.tier && /^[a-z]{1,16}$/.test(q.tier)) {
    where.push("tier = ?");
    params.push(q.tier);
  }
  if (q.status && /^[a-z]{1,16}$/.test(q.status)) {
    where.push("status = ?");
    params.push(q.status);
  }
  if (q.q && q.q.length <= 64) {
    where.push("(id LIKE ? OR note LIKE ? OR discord_id LIKE ?)");
    params.push(q.q + "%", "%" + q.q + "%", q.q + "%");
  }
  if (admin.role === "reseller") {
    where.push("created_by = ?");
    params.push(admin.id);
  }
  const whereSql = where.length > 0 ? " WHERE " + where.join(" AND ") : "";
  const rows = await ctx.db.all<KeyRow>(
    `SELECT id, project_id, tier, status, hwid_hash, hwid_resets, discord_id, roblox_user_id, note, total_executions, created_by, created_at, expires_at, first_used_at, last_used_at FROM keys${whereSql} ORDER BY created_at DESC LIMIT ? OFFSET ?`,
    [...params, limit, offset],
  );
  const total = await ctx.db.first<{ n: number }>(`SELECT COUNT(*) AS n FROM keys${whereSql}`, params);
  return json({
    rows: rows.map((r) => ({ ...r, hwid_bound: r.hwid_hash !== null })),
    total: total?.n ?? 0,
    limit,
    offset,
  });
}

export async function handleAdminListScripts(ctx: AppContext, _config: ApiConfig, input: RequestInput): Promise<Response> {
  const admin = await authenticate(ctx, _config, input);
  if (!admin || (admin.role !== "owner" && admin.role !== "admin")) return json({ error: admin ? "forbidden" : "unauthorized" }, admin ? 403 : 401);
  const q = queryOf(input);
  const rows = await ctx.db.all<{ id: string; project_id: string; name: string; keyless: number; active_version: number; created_at: number }>(
    "SELECT id, project_id, name, keyless, active_version, created_at FROM scripts" + (q.project_id && /^[0-9a-f]{32}$/.test(q.project_id) ? " WHERE project_id = ?" : "") + " ORDER BY created_at DESC LIMIT 200",
    q.project_id && /^[0-9a-f]{32}$/.test(q.project_id) ? [q.project_id] : [],
  );
  const scriptIds = rows.map((r) => r.id);
  const versions = scriptIds.length > 0
    ? await ctx.db.all<{ script_id: string; version: number; build_hash: string; init_build: string; notes: string | null; created_at: number; blob_ref: string }>(
        `SELECT script_id, version, build_hash, init_build, notes, created_at, blob_ref FROM script_versions WHERE script_id IN (${scriptIds.map(() => "?").join(",")}) ORDER BY version DESC`,
        scriptIds,
      )
    : [];
  const games = scriptIds.length > 0
    ? await ctx.db.all<{ script_id: string; game_id: number }>(
        `SELECT script_id, game_id FROM script_games WHERE script_id IN (${scriptIds.map(() => "?").join(",")})`,
        scriptIds,
      )
    : [];
  return json({
    rows: rows.map((r) => ({
      ...r,
      keyless: r.keyless === 1,
      versions: versions.filter((v) => v.script_id === r.id),
      game_ids: games.filter((g) => g.script_id === r.id).map((g) => g.game_id),
    })),
  });
}

export async function handleAdminListBlacklist(ctx: AppContext, _config: ApiConfig, input: RequestInput): Promise<Response> {
  const admin = await authenticate(ctx, _config, input);
  if (!admin || (admin.role !== "owner" && admin.role !== "admin")) return json({ error: admin ? "forbidden" : "unauthorized" }, admin ? 403 : 401);
  const q = queryOf(input);
  const kindOk = q.kind && /^(hwid|ip|roblox_user|discord)$/.test(q.kind);
  const rows = await ctx.db.all<{ id: string; kind: string; value_hash: string; reason: string | null; created_by: string; created_at: number }>(
    "SELECT id, kind, value_hash, reason, created_by, created_at FROM blacklist" + (kindOk ? " WHERE kind = ?" : "") + " ORDER BY created_at DESC LIMIT 200",
    kindOk ? [q.kind] : [],
  );
  return json({ rows });
}

export async function handleAdminListNodes(ctx: AppContext, _config: ApiConfig, input: RequestInput): Promise<Response> {
  const admin = await authenticate(ctx, _config, input);
  if (!admin || (admin.role !== "owner" && admin.role !== "admin")) return json({ error: admin ? "forbidden" : "unauthorized" }, admin ? 403 : 401);
  const rows = await ctx.db.all<{ id: string; hostname: string; region: string | null; active: number }>(
    "SELECT id, hostname, region, active FROM nodes ORDER BY hostname LIMIT 100",
    [],
  );
  return json({ rows: rows.map((r) => ({ ...r, active: r.active === 1 })) });
}

export async function handleAdminListProtocolVersions(ctx: AppContext, _config: ApiConfig, input: RequestInput): Promise<Response> {
  const admin = await authenticate(ctx, _config, input);
  if (!admin || (admin.role !== "owner" && admin.role !== "admin")) return json({ error: admin ? "forbidden" : "unauthorized" }, admin ? 403 : 401);
  const rows = await ctx.db.all<{ version: string; handler: string; min_loader: string | null; active: number }>(
    "SELECT version, handler, min_loader, active FROM protocol_versions ORDER BY version LIMIT 100",
    [],
  );
  return json({ rows: rows.map((r) => ({ ...r, active: r.active === 1 })) });
}

export async function handleAdminListSessions(ctx: AppContext, _config: ApiConfig, input: RequestInput): Promise<Response> {
  const admin = await authenticate(ctx, _config, input);
  if (!admin || (admin.role !== "owner" && admin.role !== "admin")) return json({ error: admin ? "forbidden" : "unauthorized" }, admin ? 403 : 401);
  const q = queryOf(input);
  const { limit, offset } = parseLimitOffset(q);
  const where = q.key_id && q.key_id.length <= 64 ? " WHERE key_id = ?" : "";
  const params = where !== "" ? [q.key_id] : [];
  const rows = await ctx.db.all<{ id: string; key_id: string | null; script_id: string; version: number; hwid_hash: string; ip_hash: string; roblox_user_id: number | null; place_id: number | null; watermark_id: string; created_at: number; expires_at: number }>(
    `SELECT id, key_id, script_id, version, hwid_hash, ip_hash, roblox_user_id, place_id, watermark_id, created_at, expires_at FROM sessions${where} ORDER BY created_at DESC LIMIT ? OFFSET ?`,
    [...params, limit, offset],
  );
  const total = await ctx.db.first<{ n: number }>(`SELECT COUNT(*) AS n FROM sessions${where}`, params);
  return json({ rows, total: total?.n ?? 0, limit, offset });
}

export async function handleAdminListAdmins(ctx: AppContext, _config: ApiConfig, input: RequestInput): Promise<Response> {
  const admin = await authenticate(ctx, _config, input);
  if (!admin || admin.role !== "owner") return json({ error: admin ? "forbidden" : "unauthorized" }, admin ? 403 : 401);
  const rows = await ctx.db.all<{ id: string; discord_id: string | null; role: string; quota_keys: number | null; created_at: number }>(
    "SELECT id, discord_id, role, quota_keys, created_at FROM admins ORDER BY created_at LIMIT 100",
    [],
  );
  const counts = await ctx.db.all<{ created_by: string; n: number }>(
    "SELECT created_by, COUNT(*) AS n FROM keys GROUP BY created_by",
    [],
  );
  return json({
    rows: rows.map((r) => ({ ...r, keys_created: counts.find((c) => c.created_by === r.id)?.n ?? 0 })),
  });
}

// CCP-2 addition for the doc §16 "Users (Discord link, HWID and session
// history)" page: end-user identity aggregation over keys + sessions. A user
// row = a discord identity when the key carries one, else the roblox user.
// Read-only, owner/admin-gated, no hashes beyond what /admin/keys exposes.
export async function handleAdminListUsers(ctx: AppContext, _config: ApiConfig, input: RequestInput): Promise<Response> {
  const admin = await authenticate(ctx, _config, input);
  if (!admin || (admin.role !== "owner" && admin.role !== "admin")) return json({ error: admin ? "forbidden" : "unauthorized" }, admin ? 403 : 401);
  const q = queryOf(input);
  const search = q.q && q.q.length <= 64 ? q.q : null;
  const likeDiscord = search !== null ? " AND discord_id LIKE ? " : "";
  const likeRoblox = search !== null ? " AND CAST(roblox_user_id AS TEXT) LIKE ? " : "";
  const paramsD = search !== null ? [search + "%"] : [];
  const paramsR = search !== null ? [search + "%"] : [];
  const rows = await ctx.db.all<{
    identity: string;
    kind: string;
    key_count: number;
    active_keys: number;
    hwids: number;
    total_executions: number;
    first_seen: number;
    last_used: number | null;
  }>(
    `SELECT * FROM (
      SELECT discord_id AS identity, 'discord' AS kind, COUNT(*) AS key_count,
             SUM(CASE WHEN status = 'active' THEN 1 ELSE 0 END) AS active_keys,
             COUNT(DISTINCT hwid_hash) AS hwids,
             SUM(total_executions) AS total_executions,
             MIN(created_at) AS first_seen,
             MAX(last_used_at) AS last_used
      FROM keys WHERE discord_id IS NOT NULL${likeDiscord} GROUP BY discord_id
      UNION ALL
      SELECT CAST(roblox_user_id AS TEXT) AS identity, 'roblox' AS kind, COUNT(*) AS key_count,
             SUM(CASE WHEN status = 'active' THEN 1 ELSE 0 END) AS active_keys,
             COUNT(DISTINCT hwid_hash) AS hwids,
             SUM(total_executions) AS total_executions,
             MIN(created_at) AS first_seen,
             MAX(last_used_at) AS last_used
      FROM keys WHERE discord_id IS NULL AND roblox_user_id IS NOT NULL${likeRoblox} GROUP BY roblox_user_id
    ) ORDER BY last_used IS NULL, last_used DESC
    LIMIT 200`,
    [...paramsD, ...paramsR],
  );
  return json({ rows: rows.map((r) => ({ ...r, hwids: r.hwids ?? 0, total_executions: r.total_executions ?? 0 })) });
}
