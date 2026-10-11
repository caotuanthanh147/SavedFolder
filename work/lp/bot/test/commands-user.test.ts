// User-command tests — real admin API over real HTTP; Discord surface is
// the doc-shaped FakeInteraction. Covers every doc §15 user command plus
// the ephemeral contract (D-M8-4) and the resethwid ownership gate.
import { beforeAll, describe, expect, test } from "bun:test";
import { startBotTestEnv, FakeInteraction, createLinkedKey, type BotTestEnv } from "./helpers";
import { runCommand } from "../src/commands";
import { generateKey } from "../../api/src/keys";

let t: BotTestEnv;

beforeAll(async () => {
  t = await startBotTestEnv();
});

// Fresh snowflake per test — the env is shared across the file, so tests
// never depend on execution order. Counter stays below 2^53: Discord ids
// this large would silently collide under float arithmetic.
let snowflake = 6_000_000_000_000_000;
function freshUser(): string {
  snowflake += 1;
  return String(snowflake);
}

async function run(opts: { command: string; sub?: string; user?: string; strings?: Record<string, string>; integers?: Record<string, number> }, configOverrides?: Parameters<typeof t.makeDeps>[0]): Promise<FakeInteraction> {
  const i = new FakeInteraction(opts);
  await runCommand(t.makeDeps(configOverrides), i);
  return i;
}

describe("/redeem", () => {
  test("links a key, grants the active-key role, replies ephemeral", async () => {
    const user = freshUser();
    const created = await t.api.createKeys({ project_id: "11111111111111111111111111111111", tier: "paid", days: 30, script_ids: ["22222222222222222222222222222222"] });
    expect(created.ok).toBe(true);
    if (!created.ok) return;
    const i = await run({ command: "redeem", user, strings: { key: created.keys[0].key } });
    expect(i.deferred?.ephemeral).toBe(true);
    expect(i.reply?.content).toContain("linked to your Discord account");
    expect(i.reply?.content).toContain("paid");
    expect(i.reply?.content).toContain("Active-key role granted");
    expect(t.roles.granted).toContain(user);
  });

  test("already-linked-to-self is idempotent; other-owner key is rejected", async () => {
    const owner = freshUser();
    const stranger = freshUser();
    const key = await createLinkedKey(t, owner);
    const self = await run({ command: "redeem", user: owner, strings: { key: key.plaintext } });
    expect(self.reply?.content).toContain("already linked to your account");
    const other = await run({ command: "redeem", user: stranger, strings: { key: key.plaintext } });
    expect(other.reply?.content).toContain("already linked to a different Discord account");
  });

  test("unknown key (valid checksum) 404s; bad format is a 400", async () => {
    const user = freshUser();
    // generateKey() produces a format+checksum-valid key that was never stored.
    const unknownKey = generateKey("YURI").plaintext;
    const unknown = await run({ command: "redeem", user, strings: { key: unknownKey } });
    expect(unknown.deferred?.ephemeral).toBe(true);
    expect(unknown.reply?.content).toContain("Not found");
    const bad = await run({ command: "redeem", user, strings: { key: "garbage" } });
    expect(bad.reply?.content).toContain("Admin API error");
  });

  test("blacklisted discord account cannot redeem", async () => {
    const user = freshUser();
    await t.api.blacklistAdd({ kind: "discord", value: user });
    const created = await t.api.createKeys({ project_id: "11111111111111111111111111111111", tier: "paid", script_ids: ["22222222222222222222222222222222"] });
    if (!created.ok) return;
    const i = await run({ command: "redeem", user, strings: { key: created.keys[0].key } });
    expect(i.reply?.content).toContain("blacklisted");
  });

  test("expired-but-linked key does not grant the role", async () => {
    const user = freshUser();
    const created = await t.api.createKeys({ project_id: "11111111111111111111111111111111", tier: "paid", days: 1, script_ids: ["22222222222222222222222222222222"] });
    if (!created.ok) return;
    // Force expiry in the future clock.
    t.nowOverride.value += 2 * 86400;
    const i = await run({ command: "redeem", user, strings: { key: created.keys[0].key } });
    expect(i.reply?.content).toContain("linked");
    expect(i.reply?.content).not.toContain("role granted");
    t.nowOverride.value -= 2 * 86400;
  });
});

describe("/mykeys and /status", () => {
  test("list only the invoker's keys (strict discord filter) with active count", async () => {
    const user = freshUser();
    await createLinkedKey(t, user, { days: 30 });
    await createLinkedKey(t, user, { days: 30, status: "revoked" });
    const other = freshUser();
    await createLinkedKey(t, other, { days: 30 });
    const i = await run({ command: "mykeys", user });
    expect(i.deferred?.ephemeral).toBe(true);
    expect(i.reply?.embed?.description).toContain("2 key(s), 1 currently active");
    expect(i.reply?.embed?.fields).toHaveLength(2);
    const s = await run({ command: "status", user });
    expect(s.reply?.embed?.fields).toHaveLength(2);
    const none = await run({ command: "mykeys", user: "999999999999999999" });
    expect(none.reply?.content).toContain("No keys are linked");
  });

  test("a note containing another user's snowflake never leaks into their list (D-M8-15)", async () => {
    const owner = freshUser();
    const stranger = freshUser();
    // Key with a note that literally contains the stranger's snowflake, owned by owner.
    const created = await t.api.createKeys({ project_id: "11111111111111111111111111111111", tier: "paid", days: 30, note: `escalation for ${stranger}`, script_ids: ["22222222222222222222222222222222"] });
    if (!created.ok) return;
    await t.api.linkKey(created.keys[0].key, owner);
    const i = await run({ command: "mykeys", user: stranger });
    expect(i.reply?.content ?? "").toContain("No keys are linked");
    expect(i.reply?.embed).toBeUndefined();
  });
});

describe("/getscript", () => {
  test("shows loader links for entitled scripts", async () => {
    const user = freshUser();
    const key = await createLinkedKey(t, user, { days: 30 });
    const i = await run({ command: "getscript", user });
    expect(i.deferred?.ephemeral).toBe(true);
    const field = i.reply?.embed?.fields.find((f) => f.name.includes(key.id.slice(0, 8)));
    expect(field).toBeDefined();
    expect(field?.value).toContain("/loaders/22222222222222222222222222222222.lua");
  });

  test("no keys yet → redeem hint", async () => {
    const i = await run({ command: "getscript", user: "999999999999999998" });
    expect(i.reply?.content).toContain("/redeem");
  });
});

describe("/resethwid", () => {
  test("own key resets through the real cooldown/cap endpoint", async () => {
    const user = freshUser();
    const key = await createLinkedKey(t, user, { days: 30 });
    const first = await run({ command: "resethwid", user, strings: { key_id: key.id } });
    expect(first.deferred?.ephemeral).toBe(true);
    expect(first.reply?.content).toContain("HWID reset");
    // Server-side cooldown: 7 days (api/admin.ts RESET_COOLDOWN_SEC).
    const second = await run({ command: "resethwid", user, strings: { key_id: key.id } });
    expect(second.reply?.content).toContain("cooldown");
    expect(second.reply?.content).toContain("retry");
  });

  test("a user cannot reset someone else's key (ownership gate before the privileged call)", async () => {
    const owner = freshUser();
    const attacker = freshUser();
    const key = await createLinkedKey(t, owner, { days: 30 });
    const i = await run({ command: "resethwid", user: attacker, strings: { key_id: key.id } });
    expect(i.reply?.content).toContain("not linked to your Discord account");
    // And the real endpoint was never hit for that key.
    const row = t.env.db.prepare("SELECT hwid_resets FROM keys WHERE id = ?").get(key.id) as { hwid_resets: number };
    expect(row.hwid_resets).toBe(0);
  });
});

describe("/free", () => {
  test("links the configured free-key page", async () => {
    const i = await run({ command: "free" });
    expect(i.reply?.content).toContain("https://dash.example.test/free");
    expect(i.deferred?.ephemeral).toBe(true);
  });

  test("without a configured URL it says so", async () => {
    const i = await run({ command: "free" }, { freeUrl: null });
    expect(i.reply?.content).toContain("not configured");
  });
});
