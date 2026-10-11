// CCP-M8 (Tier 3 proposal — see api/CCP-M8.md / bot/CCP-M8.md): additive admin
// endpoints required by the Discord bot (doc.md §15). Clearly marked patch:
// accept = keep this file + the 3 router rows tagged `// CCP-M8`; reject =
// delete both and the bot degrades honestly (501 path). No existing M1
// handler is touched. Auth mirrors the sibling handlers in admin.ts.
import { ApiConfig, AppContext, RequestInput } from "./flow";
import { authenticate } from "./admin";
import { hashKey, keyPassesChecksum, normalizeKey, KEY_PATTERN } from "./keys";
import { randomId, sha256Hex } from "./crypto";

function json(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), { status, headers: { "content-type": "application/json" } });
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

async function audit(ctx: AppContext, actorId: string, action: string, target: string | null, detail: string): Promise<void> {
  await ctx.db.run(
    "INSERT INTO audit_log (id, actor_id, action, target, detail, created_at) VALUES (?, ?, ?, ?, ?, ?)",
    [randomId(), actorId, action, target, detail, Math.floor(ctx.nowSec)],
  );
}

// CCP-M8 P1 — POST /admin/keys/link { key, discord_id }
export async function handleAdminLinkKey(ctx: AppContext, config: ApiConfig, input: RequestInput): Promise<Response> {
  const admin = await authenticate(ctx, config, input);
  if (!admin) return json({ error: "unauthorized" }, 401);
  if (admin.role !== "owner" && admin.role !== "admin") return json({ error: "forbidden" }, 403);
  const body = parseBody(input);
  if (!body) return json({ error: "bad_request" }, 400);

  const rawKey = typeof body.key === "string" ? body.key : "";
  const discordId = typeof body.discord_id === "string" ? body.discord_id : "";
  const normalized = normalizeKey(rawKey);
  if (!KEY_PATTERN.test(normalized) || !keyPassesChecksum(normalized)) {
    return json({ error: "bad_request", field: "key" }, 400);
  }
  if (!/^\d{1,32}$/.test(discordId)) return json({ error: "bad_request", field: "discord_id" }, 400);

  const keyHash = await hashKey(normalized, config.pepper);
  const key = await ctx.db.first<{ id: string; tier: string; status: string; expires_at: number | null; discord_id: string | null }>(
    "SELECT id, tier, status, expires_at, discord_id FROM keys WHERE key_hash = ?",
    [keyHash],
  );
  if (!key) return json({ error: "not_found" }, 404);

  // Same blacklist gate the auth flow applies to a linked discord id.
  const discordHash = await sha256Hex(config.pepper + "|discord|" + discordId);
  const banned = await ctx.db.first<{ id: string }>("SELECT id FROM blacklist WHERE kind = 'discord' AND value_hash = ?", [discordHash]);
  if (banned) return json({ error: "blacklisted" }, 403);

  if (key.discord_id !== null && key.discord_id !== discordId) {
    return json({ error: "already_linked" }, 409);
  }
  if (key.discord_id === discordId) {
    return json({ ok: true, id: key.id, tier: key.tier, status: key.status, expires_at: key.expires_at, already: true });
  }

  await ctx.db.run("UPDATE keys SET discord_id = ? WHERE id = ?", [discordId, key.id]);
  await audit(ctx, admin.id, "admin.key.link", key.id, discordId);
  return json({ ok: true, id: key.id, tier: key.tier, status: key.status, expires_at: key.expires_at, already: false });
}

// CCP-M8 P2 — GET /admin/keys/:id (detail incl. entitlements)
export async function handleAdminKeyDetail(ctx: AppContext, config: ApiConfig, input: RequestInput, keyId: string): Promise<Response> {
  const admin = await authenticate(ctx, config, input);
  if (!admin) return json({ error: "unauthorized" }, 401);
  if (admin.role !== "owner" && admin.role !== "admin" && admin.role !== "reseller" && admin.role !== "support") {
    return json({ error: "forbidden" }, 403);
  }
  const key = await ctx.db.first<{
    id: string; project_id: string; tier: string; status: string; hwid_hash: string | null;
    hwid_resets: number; discord_id: string | null; roblox_user_id: number | null; note: string | null;
    total_executions: number; created_by: string; created_at: number; expires_at: number | null;
    first_used_at: number | null; last_used_at: number | null;
  }>(
    "SELECT id, project_id, tier, status, hwid_hash, hwid_resets, discord_id, roblox_user_id, note, total_executions, created_by, created_at, expires_at, first_used_at, last_used_at FROM keys WHERE id = ?",
    [keyId],
  );
  if (!key || (admin.role === "reseller" && key.created_by !== admin.id)) return json({ error: "not_found" }, 404);
  const scripts = await ctx.db.all<{ script_id: string; name: string; keyless: number }>(
    "SELECT ks.script_id, s.name, s.keyless FROM key_scripts ks JOIN scripts s ON s.id = ks.script_id WHERE ks.key_id = ? ORDER BY s.name",
    [keyId],
  );
  return json({ ...key, hwid_bound: key.hwid_hash !== null, scripts: scripts.map((s) => ({ script_id: s.script_id, name: s.name, keyless: s.keyless === 1 })) });
}

// CCP-M8 P3 — POST /admin/blacklist/:id/remove
export async function handleAdminBlacklistRemove(ctx: AppContext, config: ApiConfig, input: RequestInput, entryId: string): Promise<Response> {
  const admin = await authenticate(ctx, config, input);
  if (!admin) return json({ error: "unauthorized" }, 401);
  if (admin.role !== "owner" && admin.role !== "admin") return json({ error: "forbidden" }, 403);
  const existing = await ctx.db.first<{ id: string; kind: string }>("SELECT id, kind FROM blacklist WHERE id = ?", [entryId]);
  if (!existing) return json({ error: "not_found" }, 404);
  await ctx.db.run("DELETE FROM blacklist WHERE id = ?", [entryId]);
  await audit(ctx, admin.id, "admin.blacklist.remove", entryId, existing.kind);
  return json({ ok: true });
}
