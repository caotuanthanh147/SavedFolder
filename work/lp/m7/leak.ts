// Module M7 — leak tracing (doc §12) + abuse correlation (doc §11).
//
// D-M7-1 carrier inventory: the live extractable carriers are the sealed
// payload_ref (watermark(16) under refSealKey) and the sessions table's
// watermark_id. This module is the first-class extractor ("survives renaming
// and reformatting": candidates are grepped out of arbitrary leaked text and
// classified) plus the admin leak workflow (lookup → revoke chain) and the
// computed abuse scores (never stored; weights pinned in DECISIONS-M7 D-M7-7).

import { b64urlDecode, toHex } from "./contracts";
import { randomId } from "./crypto";
import { ApiConfig, AppContext, RequestInput, readJsonBody, recordEvent } from "./flow";
import { authenticate } from "./admin";
import { openRef } from "./auth";

function json(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), { status, headers: { "content-type": "application/json" } });
}

function readBody(input: RequestInput): Record<string, unknown> {
  return readJsonBody(input) ?? {};
}

// ---------------------------------------------------------------------------
// Extractor (D-M7-8): tolerant candidate scan.
// ---------------------------------------------------------------------------

export interface Extraction {
  watermark_id: string;
  session_id: string | null;
  source: "sealed_ref" | "session_token" | "watermark_id";
  script_id: string | null;
}

const HEX32 = /^[0-9a-fA-F]{32}$/;
const CANDIDATE = /[A-Za-z0-9_-]{16,}/g;

async function scriptsInDb(ctx: AppContext): Promise<string[]> {
  const rows = await ctx.db.all<{ id: string }>("SELECT id FROM scripts", []);
  return rows.map((r) => r.id);
}

async function sessionByWatermark(ctx: AppContext, watermarkId: string): Promise<{ id: string; script_id: string } | null> {
  return ctx.db.first<{ id: string; script_id: string }>(
    "SELECT id, script_id FROM sessions WHERE watermark_id = ? ORDER BY created_at DESC LIMIT 1",
    [watermarkId],
  );
}

/**
 * Try a single token as each carrier class, in cheapest-first order.
 * The sealed-ref class needs the AEAD to open under one of the script ids —
 * a wrong script id (AAD) fails the open, so we try them all (script count is
 * small; each attempt is one AES-GCM open).
 */
async function classifyToken(
  ctx: AppContext,
  refSealKey: Uint8Array,
  token: string,
  scriptIds: string[],
): Promise<Extraction | null> {
  // 1) Raw watermark id (32 hex chars).
  if (HEX32.test(token)) {
    const wm = token.toLowerCase();
    const session = await sessionByWatermark(ctx, wm);
    if (session !== null) return { watermark_id: wm, session_id: session.id, source: "watermark_id", script_id: session.script_id };
    return null;
  }
  // 2) Sealed ref (b64url of nonce12|ct104|tag16 = 132 bytes) or session
  //    token (b64url of 16 bytes). Try the ref first — it is the strongest
  //    artifact (works even if the session row was pruned).
  let raw: Uint8Array;
  try {
    raw = b64urlDecode(token);
  } catch {
    return null;
  }
  if (raw.length === 16) {
    const sessionId = toHex(raw);
    const session = await ctx.db.first<{ id: string; watermark_id: string; script_id: string }>(
      "SELECT id, watermark_id, script_id FROM sessions WHERE id = ?",
      [sessionId],
    );
    if (session !== null) {
      return { watermark_id: session.watermark_id, session_id: session.id, source: "session_token", script_id: session.script_id };
    }
    return null;
  }
  if (raw.length === 12 + 104 + 16) {
    for (const scriptId of scriptIds) {
      const ref = openRef(token, refSealKey, scriptId);
      if (ref !== null) {
        const wm = toHex(ref.watermarkRaw);
        const session = await sessionByWatermark(ctx, wm);
        return {
          watermark_id: wm,
          session_id: session?.id ?? toHex(ref.sessionIdRaw),
          source: "sealed_ref",
          script_id: scriptId,
        };
      }
    }
  }
  return null;
}

/**
 * Extract a watermark from a leaked artifact. The input may be:
 *  - a clean artifact (sealed ref / session token / watermark id), or
 *  - arbitrary messy text (log dump, chat message, JSON blob) — candidates
 *    are scanned out and classified (doc §12 "survives renaming and
 *    reformatting").
 */
export async function extractWatermark(
  ctx: AppContext,
  refSealKey: Uint8Array,
  artifact: string,
): Promise<Extraction | null> {
  const text = artifact.trim();
  if (text.length === 0 || text.length > 65536) return null;
  const scriptIds = await scriptsInDb(ctx);
  // Direct classification first (clean artifact, no scan).
  const direct = await classifyToken(ctx, refSealKey, text, scriptIds);
  if (direct !== null) return direct;
  // Free-text scan: longest candidates first (refs are longer than session
  // tokens, which are longer than hex ids — but ordering by length also
  // prefers complete tokens over truncated ones).
  const candidates = Array.from(new Set(text.match(CANDIDATE) ?? [])).sort((a, b) => b.length - a.length);
  for (const token of candidates.slice(0, 200)) {
    const hit = await classifyToken(ctx, refSealKey, token, scriptIds);
    if (hit !== null) return hit;
  }
  return null;
}

// ---------------------------------------------------------------------------
// Admin leak workflow (D-M7-8).
// ---------------------------------------------------------------------------

interface LeakSessionRow {
  id: string;
  key_id: string | null;
  script_id: string;
  version: number;
  hwid_hash: string | null;
  ip_hash: string | null;
  roblox_user_id: number | null;
  watermark_id: string;
  created_at: number;
  expires_at: number;
}

interface LeakKeyRow {
  id: string;
  project_id: string;
  tier: string;
  status: string;
  hwid_hash: string | null;
  discord_id: string | null;
  roblox_user_id: number | null;
  note: string | null;
  created_at: number;
  expires_at: number | null;
}

async function leakPayload(ctx: AppContext, watermarkId: string) {
  const sessions = await ctx.db.all<LeakSessionRow>(
    "SELECT id, key_id, script_id, version, hwid_hash, ip_hash, roblox_user_id, watermark_id, created_at, expires_at FROM sessions WHERE watermark_id = ? ORDER BY created_at DESC",
    [watermarkId],
  );
  const keyId = sessions.find((s) => s.key_id !== null)?.key_id ?? null;
  const key = keyId !== null
    ? await ctx.db.first<LeakKeyRow>(
        "SELECT id, project_id, tier, status, hwid_hash, discord_id, roblox_user_id, note, created_at, expires_at FROM keys WHERE id = ?",
        [keyId],
      )
    : null;
  const events = keyId !== null
    ? await ctx.db.all<{ type: string; detail: string | null; created_at: number }>(
        "SELECT type, detail, created_at FROM events WHERE key_id = ? ORDER BY created_at DESC LIMIT 20",
        [keyId],
      )
    : [];
  return { watermark_id: watermarkId, sessions, key, events };
}

export async function handleAdminLeakLookup(ctx: AppContext, config: ApiConfig, input: RequestInput): Promise<Response> {
  const admin = await authenticate(ctx, config, input);
  if (!admin || (admin.role !== "owner" && admin.role !== "admin")) return json({ error: "forbidden" }, 403);
  const body = readBody(input);

  let watermarkId: string | null = null;
  let extraction: Extraction | null = null;

  if (typeof body.watermark_id === "string" && HEX32.test(body.watermark_id)) {
    watermarkId = body.watermark_id.toLowerCase();
  } else if (typeof body.session_token === "string" && body.session_token.length > 0) {
    extraction = await extractWatermark(ctx, config.refSealKey, body.session_token);
  } else if (typeof body.artifact === "string" && body.artifact.length > 0) {
    extraction = await extractWatermark(ctx, config.refSealKey, body.artifact);
  }
  if (extraction !== null) watermarkId = extraction.watermark_id;
  if (watermarkId === null) {
    return json({ error: "no_watermark", detail: "No watermark-bearing artifact found in the input." }, 404);
  }
  const payload = await leakPayload(ctx, watermarkId);
  if (payload.key === null && payload.sessions.length === 0) {
    return json({ error: "not_found", detail: "Watermark recognized but no session/key found." }, 404);
  }
  return json({ ...payload, extraction });
}

export async function handleAdminLeakRevoke(ctx: AppContext, config: ApiConfig, input: RequestInput): Promise<Response> {
  const admin = await authenticate(ctx, config, input);
  if (!admin || (admin.role !== "owner" && admin.role !== "admin")) return json({ error: "forbidden" }, 403);
  const body = readBody(input);

  let watermarkId: string | null = null;
  if (typeof body.watermark_id === "string" && HEX32.test(body.watermark_id)) {
    watermarkId = body.watermark_id.toLowerCase();
  } else if (typeof body.artifact === "string" && body.artifact.length > 0) {
    const extraction = await extractWatermark(ctx, config.refSealKey, body.artifact);
    if (extraction !== null) watermarkId = extraction.watermark_id;
  }
  if (watermarkId === null) return json({ error: "no_watermark" }, 400);

  const session = await ctx.db.first<LeakSessionRow>(
    "SELECT id, key_id, script_id, version, hwid_hash, ip_hash, roblox_user_id, watermark_id, created_at, expires_at FROM sessions WHERE watermark_id = ? ORDER BY created_at DESC LIMIT 1",
    [watermarkId],
  );
  if (!session) return json({ error: "not_found" }, 404);
  if (session.key_id === null) return json({ error: "free_session", detail: "Session has no bound key; blacklist manually." }, 409);

  const blacklistHwid = body.blacklist_hwid !== false && session.hwid_hash !== null;
  const blacklistIp = body.blacklist_ip !== false;

  const keyRow = await ctx.db.first<LeakKeyRow>(
    "SELECT id, project_id, tier, status, hwid_hash, discord_id, roblox_user_id, note, created_at, expires_at FROM keys WHERE id = ?",
    [session.key_id],
  );
  if (!keyRow) return json({ error: "not_found" }, 404);

  // Idempotent revoke: a second call reports the already-revoked state and
  // does not insert duplicate blacklist rows.
  const alreadyRevoked = keyRow.status === "revoked";

  if (!alreadyRevoked) {
    await ctx.db.run("UPDATE keys SET status = 'revoked' WHERE id = ?", [session.key_id]);
  }

  const blacklisted: string[] = [];
  if (blacklistHwid && session.hwid_hash !== null) {
    const existingH = await ctx.db.first<{ id: string }>(
      "SELECT id FROM blacklist WHERE kind = 'hwid' AND value_hash = ?",
      [session.hwid_hash],
    );
    if (!existingH) {
      await ctx.db.run(
        "INSERT INTO blacklist (id, kind, value_hash, reason, created_by, created_at) VALUES (?, 'hwid', ?, ?, ?, ?)",
        [randomId(), session.hwid_hash, "leak:" + watermarkId, admin.id, Math.floor(ctx.nowSec)],
      );
      blacklisted.push("hwid");
    }
  }
  if (blacklistIp) {
    const existingI = await ctx.db.first<{ id: string }>(
      "SELECT id FROM blacklist WHERE kind = 'ip' AND value_hash = ?",
      [session.ip_hash],
    );
    if (!existingI) {
      await ctx.db.run(
        "INSERT INTO blacklist (id, kind, value_hash, reason, created_by, created_at) VALUES (?, 'ip', ?, ?, ?, ?)",
        [randomId(), session.ip_hash ?? "", "leak:" + watermarkId, admin.id, Math.floor(ctx.nowSec)],
      );
      blacklisted.push("ip");
    }
  }

  // Kill the session and every other live session of the same key.
  await ctx.db.run(
    "UPDATE sessions SET expires_at = ? WHERE key_id = ? AND expires_at > ?",
    [Math.floor(ctx.nowSec), session.key_id, Math.floor(ctx.nowSec)],
  );

  if (!alreadyRevoked) {
    await recordEvent(ctx, session.key_id, "leak", "revoke:" + watermarkId);
  }
  await ctx.db.run(
    "INSERT INTO audit_log (id, actor_id, action, target, detail, created_at) VALUES (?, ?, 'admin.leak.revoke', ?, ?, ?)",
    [randomId(), admin.id, session.key_id, JSON.stringify({ watermark_id: watermarkId, blacklisted, already_revoked: alreadyRevoked }), Math.floor(ctx.nowSec)],
  );

  return json({
    watermark_id: watermarkId,
    key_id: session.key_id,
    key_status: alreadyRevoked ? "revoked" : "revoked",
    already_revoked: alreadyRevoked,
    blacklisted,
    sessions_killed: true,
  });
}

// ---------------------------------------------------------------------------
// Abuse scores (D-M7-7): computed on read, never stored.
// score = 5*tamper_7d + 2*hwid_mismatch_7d + 3*distinct_session_hwids_30d
//         + 1*invalid_lockouts_7d, capped 100. Bands: clean <10, watch 10-39,
// high >=40. Signal only — no automatic action keys off this.
// ---------------------------------------------------------------------------

export async function handleAdminAbuseScores(ctx: AppContext, config: ApiConfig, input: RequestInput): Promise<Response> {
  const admin = await authenticate(ctx, config, input);
  if (!admin || (admin.role !== "owner" && admin.role !== "admin")) return json({ error: "forbidden" }, 403);
  const now = Math.floor(ctx.nowSec);
  const d7 = now - 7 * 86400;
  const d30 = now - 30 * 86400;

  const rows = await ctx.db.all<{
    key_id: string;
    tamper_7d: number;
    hwid_mismatch_7d: number;
    lockouts_7d: number;
    distinct_hwids_30d: number;
    last_event_at: number;
  }>(
    `SELECT k.id AS key_id,
       COALESCE(t.n, 0) AS tamper_7d,
       COALESCE(h.n, 0) AS hwid_mismatch_7d,
       COALESCE(l.n, 0) AS lockouts_7d,
       COALESCE(w.n, 0) AS distinct_hwids_30d,
       COALESCE(e.last, 0) AS last_event_at
     FROM keys k
     LEFT JOIN (SELECT key_id, COUNT(*) AS n FROM events WHERE type = 'tamper' AND detail LIKE 'client:%' AND created_at > ? GROUP BY key_id) t ON t.key_id = k.id
     LEFT JOIN (SELECT key_id, COUNT(*) AS n FROM events WHERE type = 'validate_fail' AND detail = 'hwid' AND created_at > ? GROUP BY key_id) h ON h.key_id = k.id
     LEFT JOIN (SELECT key_id, COUNT(*) AS n FROM events WHERE type = 'tamper' AND detail = 'invalid-key-lockout' AND created_at > ? GROUP BY key_id) l ON l.key_id = k.id
     LEFT JOIN (SELECT key_id, COUNT(DISTINCT hwid_hash) AS n FROM sessions WHERE hwid_hash IS NOT NULL AND created_at > ? GROUP BY key_id) w ON w.key_id = k.id
     LEFT JOIN (SELECT key_id, MAX(created_at) AS last FROM events GROUP BY key_id) e ON e.key_id = k.id
     WHERE k.status = 'active'
     ORDER BY COALESCE(t.n,0)*5 + COALESCE(h.n,0)*2 + MAX(COALESCE(w.n,0) - 1, 0)*3 + COALESCE(l.n,0) DESC, k.id
     LIMIT 200`,
    [d7, d7, d7, d30],
  );

  const scores = rows.map((r) => {
    // HWID churn: the first binding is legitimate; extra distinct devices
    // (possible via admin resets + rebinds) are the churn signal.
    const churn = Math.max(r.distinct_hwids_30d - 1, 0);
    const raw = 5 * r.tamper_7d + 2 * r.hwid_mismatch_7d + 3 * churn + 1 * r.lockouts_7d;
    const score = Math.min(raw, 100);
    return {
      key_id: r.key_id,
      score,
      band: score >= 40 ? "high" : score >= 10 ? "watch" : "clean",
      tamper_7d: r.tamper_7d,
      hwid_mismatch_7d: r.hwid_mismatch_7d,
      lockouts_7d: r.lockouts_7d,
      distinct_hwids_30d: r.distinct_hwids_30d,
      hwid_churn_30d: churn,
      last_event_at: r.last_event_at,
    };
  });

  return json({ now, weights: { tamper_7d: 5, hwid_mismatch_7d: 2, distinct_hwids_30d: 3, lockouts_7d: 1 }, scores });
}
