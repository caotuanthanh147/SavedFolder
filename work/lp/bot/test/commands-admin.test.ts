// Admin-command tests — real admin API over HTTP; verifies the doc §15
// admin command surface, the server-side role gate (reseller token vs
// admin token through the REAL api), and the ephemeral policy (D-M8-4).
import { beforeAll, describe, expect, test } from "bun:test";
import { startBotTestEnv, FakeInteraction, type BotTestEnv } from "./helpers";
import { runCommand } from "../src/commands";
import { ADMIN_TOKEN, RESELLER_TOKEN, makeSignedInput } from "../../api/test/helpers";
import { buildRoutes, dispatch } from "../../api/src/router";

let t: BotTestEnv;

beforeAll(async () => {
  t = await startBotTestEnv();
});

async function run(opts: { command: string; sub?: string; user?: string; strings?: Record<string, string>; integers?: Record<string, number> }): Promise<FakeInteraction> {
  const i = new FakeInteraction(opts);
  await runCommand(t.makeDeps(), i);
  return i;
}

const PROJECT = "11111111111111111111111111111111";
const SCRIPT = "22222222222222222222222222222222";

describe("/key create", () => {
  test("creates keys, shows plaintext ONCE, ephemeral", async () => {
    const i = await run({
      command: "key",
      sub: "create",
      strings: { project_id: PROJECT, tier: "paid", scripts: SCRIPT, note: "bot-test" },
      integers: { days: 30, count: 2 },
    });
    expect(i.deferred?.ephemeral).toBe(true);
    expect(i.reply?.content).toContain("Created 2 key(s)");
    expect(i.reply?.content).toContain("shown once");
    const match = i.reply?.content?.match(/`(YURI-[A-Z2-7-]+)` → id `([0-9a-f]{32})`/g) ?? [];
    expect(match.length).toBe(2);
    // The plaintexts really validate through the real check_key gate
    // (in-process dispatch with the api's own signed-input helper —
    // check_key requires the x-proof headers a raw fetch lacks).
    const firstKey = match[0] ?? "";
    const plaintext = firstKey.match(/`(YURI-[A-Z2-7-]+)`/)?.[1] ?? "";
    const input = await makeSignedInput("POST", "/check_key", { key: plaintext, script_id: SCRIPT, lv: "1.0.0" }, { ip: "192.0.2.77", headers: { "Delta-User-Identifier": "bot-test-device" } });
    const res = await dispatch(buildRoutes(), t.env.ctx, t.env.config, input);
    const body = (await res.json()) as { code?: string };
    expect(body.code).toBe("KEY_VALID");
  });

  test("server-side validation errors surface (unknown project 404, foreign script 400)", async () => {
    const badProject = await run({ command: "key", sub: "create", strings: { project_id: "9".repeat(32), tier: "paid", scripts: SCRIPT } });
    expect(badProject.reply?.content).toContain("Not found");
    const foreign = await run({ command: "key", sub: "create", strings: { project_id: PROJECT, tier: "paid", scripts: "4".repeat(32) } });
    expect(foreign.reply?.content).toContain("Admin API error");
  });
});

describe("/key revoke + extend", () => {
  test("revoke then extend through the real endpoints", async () => {
    const created = await t.api.createKeys({ project_id: PROJECT, tier: "paid", days: 5, script_ids: [SCRIPT] });
    if (!created.ok) return;
    const id = created.keys[0].id;
    const revoked = await run({ command: "key", sub: "revoke", strings: { id } });
    expect(revoked.deferred?.ephemeral).toBe(false);
    expect(revoked.reply?.content).toContain("Revoked key");
    const row = t.env.db.prepare("SELECT status FROM keys WHERE id = ?").get(id) as { status: string };
    expect(row.status).toBe("revoked");
    const extended = await run({ command: "key", sub: "extend", strings: { id }, integers: { days: 10 } });
    expect(extended.reply?.content).toContain("Extended key");
    const row2 = t.env.db.prepare("SELECT expires_at FROM keys WHERE id = ?").get(id) as { expires_at: number };
    expect(row2.expires_at).toBeGreaterThan(t.nowOverride.value + 9 * 86400);
  });
});

describe("/key info", () => {
  test("full detail incl. entitlements, ephemeral", async () => {
    const created = await t.api.createKeys({ project_id: PROJECT, tier: "paid", days: 5, script_ids: [SCRIPT] });
    if (!created.ok) return;
    const i = await run({ command: "key", sub: "info", strings: { id: created.keys[0].id } });
    expect(i.deferred?.ephemeral).toBe(true);
    const embed = i.reply?.embed;
    expect(embed?.title).toContain(created.keys[0].id);
    const scriptsField = embed?.fields.find((f) => f.name === "Scripts");
    expect(scriptsField?.value).toContain(SCRIPT);
  });
});

describe("/blacklist add + /whitelist", () => {
  test("add then remove round-trip with real audit rows", async () => {
    const added = await run({ command: "blacklist", sub: "add", strings: { kind: "ip", value: "198.51.100.9", reason: "abuse" } });
    expect(added.reply?.content).toContain("Blacklisted ip");
    const entryId = added.reply?.content?.match(/entry `([0-9a-f]{32})`/)?.[1];
    expect(entryId).toBeDefined();
    if (entryId === undefined) return;
    const removed = await run({ command: "whitelist", strings: { id: entryId } });
    expect(removed.reply?.content).toContain("Removed blacklist entry");
    const count = t.env.db.prepare("SELECT COUNT(*) AS n FROM blacklist WHERE id = ?").get(entryId) as { n: number };
    expect(count.n).toBe(0);
  });

  test("hwid kind requires project_id (server-side 400 surfaces)", async () => {
    const i = await run({ command: "blacklist", sub: "add", strings: { kind: "hwid", value: "device-abc" } });
    expect(i.reply?.content).toContain("Admin API error");
  });
});

describe("/stats", () => {
  test("renders real M12 metrics + alert summary, non-ephemeral", async () => {
    const i = await run({ command: "stats", strings: { window: "24h" } });
    expect(i.deferred?.ephemeral).toBe(false);
    const embed = i.reply?.embed;
    expect(embed?.title).toContain("24h");
    const names = embed?.fields.map((f) => f.name) ?? [];
    expect(names).toContain("Keys");
    expect(names).toContain("Auth");
    expect(names).toContain("Free flow");
    expect(names).toContain("Alerts");
  });
});

describe("/leak lookup", () => {
  test("traces a watermark id to its key through the real M7 endpoint", async () => {
    const created = await t.api.createKeys({ project_id: PROJECT, tier: "paid", days: 30, script_ids: [SCRIPT] });
    if (!created.ok) return;
    const keyId = created.keys[0].id;
    const watermark = "ab".repeat(16);
    t.env.db.prepare("INSERT INTO sessions (id, key_id, script_id, version, hwid_hash, ip_hash, watermark_id, created_at, expires_at) VALUES (?, ?, ?, 1, ?, ?, ?, ?, ?)")
      .run("s-leak-1", keyId, SCRIPT, "hwid-hash-1", "ip-hash-1", watermark, t.nowOverride.value, t.nowOverride.value + 600);
    const i = await run({ command: "leak", sub: "lookup", strings: { value: watermark } });
    expect(i.deferred?.ephemeral).toBe(true);
    const embed = i.reply?.embed;
    expect(embed?.title).toContain("Leak trace");
    expect(embed?.fields.find((f) => f.name === "Key")?.value).toContain(keyId);
    expect(embed?.fields.find((f) => f.name === "Sessions")?.value).toContain("1 watermarked session");
  });

  test("no watermark in input → clear message, not a crash", async () => {
    const i = await run({ command: "leak", sub: "lookup", strings: { value: "not-watermarked-garbage" } });
    expect(i.reply?.content).toContain("No watermark-bearing artifact");
  });
});

describe("server-side admin role gate (doc §15: checks happen via the admin API)", () => {
  test("a reseller-role token cannot run owner/admin-gated endpoints the bot uses", async () => {
    const res = await fetch(`http://127.0.0.1:${t.port}/admin/blacklist`, {
      method: "POST",
      headers: { authorization: `Bearer ${RESELLER_TOKEN}`, "content-type": "application/json" },
      body: JSON.stringify({ kind: "ip", value: "203.0.113.99" }),
    });
    expect(res.status).toBe(403);
    // And the admin token used by the bot CAN (it is owner-role).
    const ok = await fetch(`http://127.0.0.1:${t.port}/admin/blacklist`, {
      method: "POST",
      headers: { authorization: `Bearer ${ADMIN_TOKEN}`, "content-type": "application/json" },
      body: JSON.stringify({ kind: "ip", value: "203.0.113.99" }),
    });
    expect(ok.status).toBe(201);
  });
});
