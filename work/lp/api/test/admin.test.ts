import { beforeAll, describe, expect, test } from "bun:test";
import { ADMIN_ID, ADMIN_TOKEN, RESELLER_TOKEN, buildEnv, makeSignedInput, envelopeOf, SCRIPT_ID, PROJECT_ID, TestEnv } from "./helpers";
import { buildRoutes, dispatch } from "../src/router";
import { hashKey, KEY_PATTERN } from "../src/keys";

let env: TestEnv;

beforeAll(async () => {
  env = await buildEnv();
});

async function adminRequest(method: string, path: string, body: Record<string, unknown> | null, token: string | null): Promise<Response> {
  const headers: Record<string, string> = {};
  if (token !== null) headers.authorization = `Bearer ${token}`;
  const input = await makeSignedInput(method, path, body, { headers, ip: "192.0.2.1" });
  return dispatch(buildRoutes(), env.ctx, env.config, input);
}

function bodyOf(res: Response): Promise<Record<string, unknown>> {
  return res.json() as Promise<Record<string, unknown>>;
}

describe("admin authentication", () => {
  test("no or wrong token is 401", async () => {
    const noAuth = await adminRequest("POST", "/admin/keys", { project_id: PROJECT_ID, tier: "paid", script_ids: [SCRIPT_ID] }, null);
    expect(noAuth.status).toBe(401);
    const wrong = await adminRequest("POST", "/admin/keys", { project_id: PROJECT_ID, tier: "paid", script_ids: [SCRIPT_ID] }, "wrong-token");
    expect(wrong.status).toBe(401);
  });
});

describe("POST /admin/keys", () => {
  test("creates keys with one-time plaintext, hash-only storage, entitlements, and audit", async () => {
    const res = await adminRequest("POST", "/admin/keys", { project_id: PROJECT_ID, tier: "paid", count: 2, days: 30, note: "batch-a", script_ids: [SCRIPT_ID] }, ADMIN_TOKEN);
    expect(res.status).toBe(201);
    const body = await bodyOf(res);
    const keys = body.keys as { id: string; key: string }[];
    expect(keys).toHaveLength(2);
    for (const k of keys) {
      expect(k.key).toMatch(KEY_PATTERN);
      expect(k.id).toMatch(/^[0-9a-f]{32}$/);
      const row = env.db.prepare("SELECT key_hash, tier, status, note, expires_at, project_id FROM keys WHERE id = ?").get(k.id) as { key_hash: string; tier: string; status: string; note: string; expires_at: number; project_id: string };
      expect(row.key_hash).toBe(await hashKey(k.key, env.config.pepper));
      expect(row.tier).toBe("paid");
      expect(row.status).toBe("active");
      expect(row.note).toBe("batch-a");
      expect(row.expires_at).toBeGreaterThan(Math.floor(Date.now() / 1000) + 29 * 86400);
      expect(row.project_id).toBe(PROJECT_ID);
      const entitled = env.db.prepare("SELECT COUNT(*) AS n FROM key_scripts WHERE key_id = ?").get(k.id) as { n: number };
      expect(entitled.n).toBe(1);
    }
    const audit = env.db.prepare("SELECT actor_id, action, target FROM audit_log WHERE action = 'admin.key.create'").all() as { actor_id: string; action: string; target: string }[];
    expect(audit).toHaveLength(1);
    expect(audit[0].actor_id).toBe(ADMIN_ID);
    expect(audit[0].target).toBe(PROJECT_ID);

    const created = await dispatch(buildRoutes(), env.ctx, env.config, await makeSignedInput("POST", "/check_key", { key: keys[0].key, script_id: SCRIPT_ID, lv: "1.0.0" }, { ip: "192.0.2.2", headers: { "Delta-User-Identifier": "fresh-device" } }));
    expect((await envelopeOf(created)).code).toBe("KEY_VALID");
  });

  test("validates inputs", async () => {
    const badTier = await adminRequest("POST", "/admin/keys", { project_id: PROJECT_ID, tier: "platinum", script_ids: [SCRIPT_ID] }, ADMIN_TOKEN);
    expect(badTier.status).toBe(400);
    const badCount = await adminRequest("POST", "/admin/keys", { project_id: PROJECT_ID, tier: "paid", count: 0, script_ids: [SCRIPT_ID] }, ADMIN_TOKEN);
    expect(badCount.status).toBe(400);
    const foreignScript = await adminRequest("POST", "/admin/keys", { project_id: PROJECT_ID, tier: "paid", script_ids: ["4".repeat(32)] }, ADMIN_TOKEN);
    expect(foreignScript.status).toBe(400);
    const unknownProject = await adminRequest("POST", "/admin/keys", { project_id: "9".repeat(32), tier: "paid", script_ids: [SCRIPT_ID] }, ADMIN_TOKEN);
    expect(unknownProject.status).toBe(404);
  });

  test("reseller quota is enforced", async () => {
    const first = await adminRequest("POST", "/admin/keys", { project_id: PROJECT_ID, tier: "free", count: 2, script_ids: [SCRIPT_ID] }, RESELLER_TOKEN);
    expect(first.status).toBe(201);
    const second = await adminRequest("POST", "/admin/keys", { project_id: PROJECT_ID, tier: "free", count: 1, script_ids: [SCRIPT_ID] }, RESELLER_TOKEN);
    expect(second.status).toBe(201);
    const third = await adminRequest("POST", "/admin/keys", { project_id: PROJECT_ID, tier: "free", count: 1, script_ids: [SCRIPT_ID] }, RESELLER_TOKEN);
    expect(third.status).toBe(403);
  });
});

describe("PATCH /admin/keys/:id", () => {
  test("extends expiry, changes tier and note, writes audit", async () => {
    const key = await env.createKey({ days: 5 });
    const before = env.db.prepare("SELECT expires_at FROM keys WHERE id = ?").get(key.id) as { expires_at: number };
    const res = await adminRequest("PATCH", `/admin/keys/${key.id}`, { extend_days: 10, tier: "lifetime", note: "upgraded" }, ADMIN_TOKEN);
    expect(res.status).toBe(200);
    const after = env.db.prepare("SELECT expires_at, tier, note FROM keys WHERE id = ?").get(key.id) as { expires_at: number; tier: string; note: string };
    expect(after.expires_at).toBe(before.expires_at + 10 * 86400);
    expect(after.tier).toBe("lifetime");
    expect(after.note).toBe("upgraded");
    const audit = env.db.prepare("SELECT action FROM audit_log WHERE action = 'admin.key.update' AND target = ?").all(key.id) as { action: string }[];
    expect(audit).toHaveLength(1);
  });

  test("reseller cannot patch", async () => {
    const key = await env.createKey();
    const res = await adminRequest("PATCH", `/admin/keys/${key.id}`, { tier: "paid" }, RESELLER_TOKEN);
    expect(res.status).toBe(403);
  });
});

describe("POST /admin/keys/:id/revoke", () => {
  test("revocation blocks check_key", async () => {
    const key = await env.createKey();
    const res = await adminRequest("POST", `/admin/keys/${key.id}/revoke`, null, ADMIN_TOKEN);
    expect(res.status).toBe(200);
    const check = await dispatch(buildRoutes(), env.ctx, env.config, await makeSignedInput("POST", "/check_key", { key: key.plaintext, script_id: SCRIPT_ID, lv: "1.0.0" }, { ip: "192.0.2.3" }));
    expect((await envelopeOf(check)).code).toBe("KEY_INVALID");
    const row = env.db.prepare("SELECT status FROM keys WHERE id = ?").get(key.id) as { status: string };
    expect(row.status).toBe("revoked");
  });
});

describe("POST /admin/keys/:id/reset-hwid", () => {
  test("reset unbinds, has cooldown, monthly cap, and counter", async () => {
    const key = await env.createKey();
    const bound = await dispatch(buildRoutes(), env.ctx, env.config, await makeSignedInput("POST", "/check_key", { key: key.plaintext, script_id: SCRIPT_ID, lv: "1.0.0" }, { ip: "192.0.2.4", headers: { "Delta-User-Identifier": "device-first" } }));
    expect((await envelopeOf(bound)).code).toBe("KEY_VALID");

    const reset = await adminRequest("POST", `/admin/keys/${key.id}/reset-hwid`, null, ADMIN_TOKEN);
    expect(reset.status).toBe(200);
    const row = env.db.prepare("SELECT hwid_hash, hwid_resets, last_reset_at FROM keys WHERE id = ?").get(key.id) as { hwid_hash: string | null; hwid_resets: number; last_reset_at: number };
    expect(row.hwid_hash).toBeNull();
    expect(row.hwid_resets).toBe(1);
    expect(row.last_reset_at).toBeGreaterThan(0);

    const rebound = await dispatch(buildRoutes(), env.ctx, env.config, await makeSignedInput("POST", "/check_key", { key: key.plaintext, script_id: SCRIPT_ID, lv: "1.0.0" }, { ip: "192.0.2.4", headers: { "Delta-User-Identifier": "device-second" } }));
    expect((await envelopeOf(rebound)).code).toBe("KEY_VALID");

    const cooldown = await adminRequest("POST", `/admin/keys/${key.id}/reset-hwid`, null, ADMIN_TOKEN);
    expect(cooldown.status).toBe(429);
    const cooldownBody = await envelopeOf(cooldown);
    expect(cooldownBody.code).toBe("RATE_LIMITED");
    expect(Number(cooldown.headers.get("retry-after"))).toBeGreaterThan(0);

    env.db.prepare("UPDATE keys SET last_reset_at = ? WHERE id = ?").run(Math.floor(Date.now() / 1000) - 8 * 86400, key.id);
    const again = await adminRequest("POST", `/admin/keys/${key.id}/reset-hwid`, null, ADMIN_TOKEN);
    expect(again.status).toBe(200);
    env.db.prepare("UPDATE keys SET last_reset_at = ? WHERE id = ?").run(Math.floor(Date.now() / 1000) - 8 * 86400, key.id);
    env.db.prepare("INSERT INTO audit_log (id, actor_id, action, target, detail, created_at) VALUES (?, 'seed', 'admin.key.reset_hwid', ?, '', ?)").run("audit-seed", key.id, Math.floor(Date.now() / 1000) - 100);
    const capped = await adminRequest("POST", `/admin/keys/${key.id}/reset-hwid`, null, ADMIN_TOKEN);
    expect(capped.status).toBe(429);
    expect((await bodyOf(capped)).error).toBe("monthly_cap_exceeded");
    const finalResets = env.db.prepare("SELECT hwid_resets FROM keys WHERE id = ?").get(key.id) as { hwid_resets: number };
    expect(finalResets.hwid_resets).toBe(2);
  });
});

describe("GET /admin/audit", () => {
  test("returns recent entries for owners only", async () => {
    const res = await adminRequest("GET", "/admin/audit", null, ADMIN_TOKEN);
    expect(res.status).toBe(200);
    const body = await bodyOf(res);
    const entries = body.entries as { action: string }[];
    expect(entries.some((e) => e.action === "admin.key.create")).toBe(true);
    const reseller = await adminRequest("GET", "/admin/audit", null, RESELLER_TOKEN);
    expect(reseller.status).toBe(403);
  });
});
