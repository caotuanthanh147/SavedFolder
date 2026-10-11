// CCP-M8 endpoint tests — run the REAL api router (with the additive
// routes mounted) over real HTTP and verify the three proposed endpoints'
// contracts, plus the P4 corrected-entry behavior (query strings flow
// through). These are the tests the M1 owner can lift when accepting the CCP.
import { beforeAll, describe, expect, test } from "bun:test";
import { ADMIN_TOKEN, PROJECT_ID, SCRIPT_ID, RESELLER_TOKEN, TestEnv } from "../../api/test/helpers";
import { makeSignedInput } from "../../api/test/helpers";
import { buildRoutes, dispatch } from "../../api/src/router";
import { hashKey, generateKey } from "../../api/src/keys";
import { startBotTestEnv, type BotTestEnv } from "./helpers";

let t: BotTestEnv;

beforeAll(async () => {
  t = await startBotTestEnv();
});

describe("CCP-M8 P1 — POST /admin/keys/link", () => {
  test("links a valid key to a discord id and reports tier/status/expiry", async () => {
    const created = await t.api.createKeys({ project_id: PROJECT_ID, tier: "paid", days: 30, script_ids: [SCRIPT_ID] });
    expect(created.ok).toBe(true);
    if (!created.ok) return;
    const res = await t.api.linkKey(created.keys[0].key, "123456789012345678");
    expect(res.ok).toBe(true);
    if (!res.ok) return;
    expect(res.id).toBe(created.keys[0].id);
    expect(res.tier).toBe("paid");
    expect(res.status).toBe("active");
    expect(res.expires_at).toBeGreaterThan(29 * 86400);
    expect(res.already).toBe(false);
    const row = t.env.db.prepare("SELECT discord_id FROM keys WHERE id = ?").get(created.keys[0].id) as { discord_id: string };
    expect(row.discord_id).toBe("123456789012345678");
    const audit = t.env.db.prepare("SELECT action, target, detail FROM audit_log WHERE action = 'admin.key.link' AND target = ?").get(created.keys[0].id) as { action: string; target: string; detail: string } | undefined;
    expect(audit?.detail).toBe("123456789012345678");
  });

  test("idempotent when the same discord id re-links its own key", async () => {
    const created = await t.api.createKeys({ project_id: PROJECT_ID, tier: "free", script_ids: [SCRIPT_ID] });
    if (!created.ok) return;
    const first = await t.api.linkKey(created.keys[0].key, "111111111111111111");
    expect(first.ok && first.already).toBe(false);
    const second = await t.api.linkKey(created.keys[0].key, "111111111111111111");
    expect(second.ok).toBe(true);
    if (second.ok) expect(second.already).toBe(true);
  });

  test("409 when the key belongs to a different discord id", async () => {
    const created = await t.api.createKeys({ project_id: PROJECT_ID, tier: "paid", script_ids: [SCRIPT_ID] });
    if (!created.ok) return;
    await t.api.linkKey(created.keys[0].key, "222222222222222222");
    const res = await t.api.linkKey(created.keys[0].key, "333333333333333333");
    expect(res.ok).toBe(false);
    if (!res.ok) {
      expect(res.status).toBe(409);
      expect(res.error).not.toBe("network");
      if (res.error !== "network") expect(res.error.error).toBe("already_linked");
    }
  });

  test("403 blacklisted when the discord id is banned", async () => {
    const created = await t.api.createKeys({ project_id: PROJECT_ID, tier: "paid", script_ids: [SCRIPT_ID] });
    if (!created.ok) return;
    const bl = await t.api.blacklistAdd({ kind: "discord", value: "444444444444444444" });
    expect(bl.ok).toBe(true);
    const res = await t.api.linkKey(created.keys[0].key, "444444444444444444");
    expect(res.ok).toBe(false);
    if (!res.ok && res.error !== "network") expect(res.error.error).toBe("blacklisted");
  });

  test("404 for an unknown key plaintext (checksum-valid, never stored)", async () => {
    const res = await t.api.linkKey(generateKey("YURI").plaintext, "555555555555555555");
    expect(res.ok).toBe(false);
    if (!res.ok) expect(res.status).toBe(404);
  });

  test("400 for malformed key (checksum/format) and non-numeric discord id", async () => {
    const badKey = await t.api.linkKey("not-a-key", "123");
    expect(badKey.ok).toBe(false);
    if (!badKey.ok) expect(res_status(badKey)).toBe(400);
    const created = await t.api.createKeys({ project_id: PROJECT_ID, tier: "paid", script_ids: [SCRIPT_ID] });
    if (!created.ok) return;
    const badDiscord = await t.api.linkKey(created.keys[0].key, "abc");
    expect(badDiscord.ok).toBe(false);
    if (!badDiscord.ok) expect(res_status(badDiscord)).toBe(400);
  });

  test("rejects non-admin tokens (reseller cannot link)", async () => {
    const created = await t.api.createKeys({ project_id: PROJECT_ID, tier: "paid", script_ids: [SCRIPT_ID] });
    if (!created.ok) return;
    const res = await fetch(`http://127.0.0.1:${t.port}/admin/keys/link`, {
      method: "POST",
      headers: { authorization: `Bearer ${RESELLER_TOKEN}`, "content-type": "application/json" },
      body: JSON.stringify({ key: created.keys[0].key, discord_id: "666666666666666666" }),
    });
    expect(res.status).toBe(403);
  });

  test("key hash stays pepper-hashed (no plaintext or hash leak in storage)", async () => {
    const created = await t.api.createKeys({ project_id: PROJECT_ID, tier: "paid", script_ids: [SCRIPT_ID] });
    if (!created.ok) return;
    await t.api.linkKey(created.keys[0].key, "777777777777777777");
    const row = t.env.db.prepare("SELECT key_hash FROM keys WHERE id = ?").get(created.keys[0].id) as { key_hash: string };
    expect(row.key_hash).toBe(await hashKey(created.keys[0].key, t.env.config.pepper));
  });
});

describe("CCP-M8 P2 — GET /admin/keys/:id", () => {
  test("returns the full row plus entitlements", async () => {
    const created = await t.api.createKeys({ project_id: PROJECT_ID, tier: "paid", days: 7, script_ids: [SCRIPT_ID] });
    if (!created.ok) return;
    const detail = await t.api.keyDetail(created.keys[0].id);
    expect(detail.ok).toBe(true);
    if (!detail.ok) return;
    expect(detail.tier).toBe("paid");
    expect(detail.status).toBe("active");
    expect(detail.scripts).toHaveLength(1);
    expect(detail.scripts[0].script_id).toBe(SCRIPT_ID);
    expect(typeof detail.scripts[0].name).toBe("string");
  });

  test("404 for unknown id; reseller scoped to own keys", async () => {
    const missing = await t.api.keyDetail("f".repeat(32));
    expect(missing.ok).toBe(false);
    if (!missing.ok) expect(missing.status).toBe(404);
    const created = await t.api.createKeys({ project_id: PROJECT_ID, tier: "paid", script_ids: [SCRIPT_ID] });
    if (!created.ok) return;
    const res = await fetch(`http://127.0.0.1:${t.port}/admin/keys/${created.keys[0].id}`, {
      headers: { authorization: `Bearer ${RESELLER_TOKEN}` },
    });
    expect(res.status).toBe(404); // created by the owner admin, not this reseller
  });
});

describe("CCP-M8 P3 — POST /admin/blacklist/:id/remove", () => {
  test("removes an entry and writes an audit row", async () => {
    const bl = await t.api.blacklistAdd({ kind: "ip", value: "203.0.113.77", reason: "test" });
    expect(bl.ok).toBe(true);
    if (!bl.ok) return;
    const rem = await t.api.blacklistRemove(bl.id);
    expect(rem.ok).toBe(true);
    const row = t.env.db.prepare("SELECT COUNT(*) AS n FROM blacklist WHERE id = ?").get(bl.id) as { n: number };
    expect(row.n).toBe(0);
    const audit = t.env.db.prepare("SELECT action, target, detail FROM audit_log WHERE action = 'admin.blacklist.remove' AND target = ?").get(bl.id) as { detail: string } | undefined;
    expect(audit?.detail).toBe("ip");
  });

  test("404 for unknown entry id", async () => {
    const res = await t.api.blacklistRemove("e".repeat(32));
    expect(res.ok).toBe(false);
    if (!res.ok) expect(res.status).toBe(404);
  });
});

describe("CCP-M8 P4 — query strings reach handlers over real HTTP", () => {
  test("GET /admin/keys?status=...&q=... filters server-side", async () => {
    await t.api.createKeys({ project_id: PROJECT_ID, tier: "paid", script_ids: [SCRIPT_ID] });
    const res = await fetch(`http://127.0.0.1:${t.port}/admin/keys?status=revoked&limit=5`, { headers: t.adminHeaders });
    expect(res.status).toBe(200);
    const body = (await res.json()) as { rows: { status: string }[] };
    for (const row of body.rows) expect(row.status).toBe("revoked");
  });
});

function res_status(r: { ok: boolean; status: number }): number {
  return r.status;
}

// Direct-dispatch regression for the in-process path (no HTTP): the api's
// own makeSignedInput shape still routes the CCP endpoints.
describe("CCP routes mount in the standard router", () => {
  test("POST /admin/keys/link via makeSignedInput dispatch", async () => {
    const created = await t.api.createKeys({ project_id: PROJECT_ID, tier: "paid", script_ids: [SCRIPT_ID] });
    if (!created.ok) return;
    const input = await makeSignedInput("POST", "/admin/keys/link", { key: created.keys[0].key, discord_id: "999999999999999999" }, { headers: { authorization: `Bearer ${ADMIN_TOKEN}` } });
    const res = await dispatch(buildRoutes(), t.env.ctx, t.env.config, input);
    expect(res.status).toBe(200);
  });
});

export type { TestEnv };
