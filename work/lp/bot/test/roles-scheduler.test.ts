// Role-sync + scheduler tests — real admin API over HTTP; FakeRoles /
// FakeChannel capture the Discord-side effects. Covers doc §15's "Roles
// are granted for active keys and removed on expiry or revoke" and the
// "Scheduled job for expiry reminders and role cleanup".
import { beforeAll, describe, expect, test } from "bun:test";
import { startBotTestEnv, createLinkedKey, type BotTestEnv } from "./helpers";
import { RoleSync, keyGrantsRole, NoopRolePort } from "../src/roles";
import { runOnce } from "../src/scheduler";
import type { KeyRow } from "../src/adminapi";

let t: BotTestEnv;

beforeAll(async () => {
  t = await startBotTestEnv();
});

const USER_A = "100000000000000001";
const USER_B = "100000000000000002";
const USER_C = "100000000000000003";

describe("keyGrantsRole", () => {
  const key = (over: Partial<KeyRow>): KeyRow => ({
    id: "a".repeat(32), project_id: "p", tier: "paid", status: "active", hwid_bound: false,
    hwid_resets: 0, discord_id: null, roblox_user_id: null, note: null, total_executions: 0,
    created_by: "x", created_at: 0, expires_at: null, first_used_at: null, last_used_at: null,
    ...over,
  });
  const NOW = 1_000_000;
  test("active + unexpired or lifetime grants; revoked/expired do not", () => {
    expect(keyGrantsRole(key({}), NOW)).toBe(true);
    expect(keyGrantsRole(key({ expires_at: NOW + 1 }), NOW)).toBe(true);
    expect(keyGrantsRole(key({ expires_at: NOW }), NOW)).toBe(false);
    expect(keyGrantsRole(key({ expires_at: NOW - 1 }), NOW)).toBe(false);
    expect(keyGrantsRole(key({ status: "revoked" }), NOW)).toBe(false);
  });
});

describe("RoleSync.grantIfActive", () => {
  test("grants only while an active unexpired key exists", async () => {
    const sync = new RoleSync(t.api, t.roles, { activeRoleId: "r", guildId: "g" }, () => t.nowOverride.value);
    const key = await createLinkedKey(t, USER_A, { days: 30 });
    const op = await sync.grantIfActive(USER_A);
    expect(op).toBe("granted");
    // Revoke it → no grant anymore (noop, role removal handled by reconcile).
    await t.api.revokeKey(key.id);
    const op2 = await sync.grantIfActive(USER_A);
    expect(op2).toBe("noop");
  });

  test("no_role_config / no_guild degrade explicitly", async () => {
    const none = new RoleSync(t.api, new NoopRolePort(), { activeRoleId: null, guildId: "g" });
    expect(await none.grantIfActive(USER_A)).toBe("no_role_config");
    const noGuild = new RoleSync(t.api, new NoopRolePort(), { activeRoleId: "r", guildId: null });
    expect(await noGuild.grantIfActive(USER_A)).toBe("no_guild");
  });
});

describe("RoleSync.reconcile + scheduler runOnce", () => {
  test("full pass: grants actives, removes on revoke/expiry, posts expiry reminder", async () => {
    // USER_A: active, expiring in 2 days (within default lead 3).
    await createLinkedKey(t, USER_A, { days: 2 });
    // USER_B: active lifetime — grant, no reminder.
    await createLinkedKey(t, USER_B, { days: null });
    // USER_C: was active, now revoked — must be removed.
    const c = await createLinkedKey(t, USER_C, { days: 30 });
    await t.api.revokeKey(c.id);
    // Pre-seed the role state so removal is observable.
    t.roles.granted.push(USER_C);

    const result = await runOnce({ api: t.api, sync: t.makeDeps().sync, channel: t.channel, config: t.makeDeps().config, now: () => t.nowOverride.value });
    expect(result.reconciled.granted).toContain(USER_A);
    expect(result.reconciled.granted).toContain(USER_B);
    expect(result.reconciled.removed).toContain(USER_C);
    expect(result.reconciled.errors).toBe(0);
    expect(result.reminders).toBe(1);
    expect(t.channel.posts).toHaveLength(1);
    expect(t.channel.posts[0].content).toContain("expiring within 3 days");
    expect(t.channel.posts[0].content).toContain(USER_A);
    // Reminder lists masked key ids, never plaintext (D-M8-11).
    expect(t.channel.posts[0].content).not.toMatch(/YURI-/);
  });

  test("expiry crossing the lead window changes the reminder", async () => {
    const key = await createLinkedKey(t, USER_B, { days: 10 });
    await runOnce({ api: t.api, sync: t.makeDeps().sync, channel: t.channel, config: t.makeDeps().config, now: () => t.nowOverride.value });
    // A 10-day key is outside the 3-day lead window — it must not appear
    // (earlier tests' short keys may still remind; assert on THIS key).
    const beforePost = t.channel.posts[t.channel.posts.length - 1]?.content ?? "";
    expect(beforePost).not.toContain(key.id.slice(0, 8));
    t.nowOverride.value += 8 * 86400; // now 2 days from expiry
    const after = await runOnce({ api: t.api, sync: t.makeDeps().sync, channel: t.channel, config: t.makeDeps().config, now: () => t.nowOverride.value });
    expect(after.reminders).toBeGreaterThanOrEqual(1);
    const post = t.channel.posts[t.channel.posts.length - 1];
    expect(post.content).toContain(key.id.slice(0, 8));
    t.nowOverride.value -= 8 * 86400;
  });

  test("scheduler with no reminder channel posts nothing", async () => {
    const posts = t.channel.posts.length;
    const result = await runOnce({ api: t.api, sync: t.makeDeps().sync, channel: t.channel, config: t.makeDeps({ reminderChannelId: null }).config, now: () => t.nowOverride.value });
    expect(result.reminders).toBe(0);
    expect(t.channel.posts.length).toBe(posts);
  });

  test("role removed when an active key expires past now (reconcile truth source = key rows)", async () => {
    const key = await createLinkedKey(t, USER_A + "5", { days: 1 });
    t.roles.granted.push(USER_A + "5");
    t.nowOverride.value += 2 * 86400;
    const result = await runOnce({ api: t.api, sync: t.makeDeps().sync, channel: t.channel, config: t.makeDeps().config, now: () => t.nowOverride.value });
    expect(result.reconciled.removed).toContain(USER_A + "5");
    t.nowOverride.value -= 2 * 86400;
    expect(key.id).toBeDefined();
  });
});
