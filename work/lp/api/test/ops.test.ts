// Module M12 tests — derived metrics (D-M12-1), alert rules (D-M12-6),
// route auth gates, and the §18 URL/log hygiene scan (D-M12-13).
//
// Derivation is proven two ways: (a) REAL flows through the router write
// the events the handlers actually write (wiring proof), (b) synthetic
// rows exercise the aggregation math and alert thresholds (volume proof).

import { beforeAll, describe, expect, test } from "bun:test";
import { readdirSync, readFileSync } from "node:fs";
import { join } from "node:path";
import {
  ADMIN_TOKEN,
  RESELLER_TOKEN,
  SCRIPT_ID,
  TestEnv,
  buildEnv,
  makeSignedInput,
} from "./helpers";
import { buildRoutes, dispatch } from "../src/router";
import { evaluateAlerts, ALERT_THRESHOLDS, MetricsSnapshot } from "../src/ops";

function now(): number {
  return Math.floor(Date.now() / 1000);
}

async function getJson(env: TestEnv, path: string, token = ADMIN_TOKEN): Promise<{ status: number; json: Record<string, unknown> }> {
  const input = await makeSignedInput("GET", path, null, { headers: { authorization: `Bearer ${token}` } });
  const res = await dispatch(buildRoutes(), env.ctx, env.config, input);
  let parsed: Record<string, unknown> = {};
  try {
    parsed = JSON.parse(await res.text()) as Record<string, unknown>;
  } catch {
    /* non-JSON */
  }
  return { status: res.status, json: parsed };
}

async function checkKey(env: TestEnv, key: string): Promise<void> {
  const input = await makeSignedInput("POST", "/check_key", { key, script_id: SCRIPT_ID, lv: "1.0.0" });
  await dispatch(buildRoutes(), env.ctx, env.config, input);
}

describe("M12 /admin/metrics — derivation", () => {
  let env: TestEnv;
  let goodKey: { plaintext: string; id: string };

  beforeAll(async () => {
    env = await buildEnv();
    goodKey = await env.createKey({ tier: "paid", days: 30 });
    // Real traffic: 2 valid check_key + 1 invalid-checksum reject via the
    // REAL router (wiring proof for the ok paths and the fail paths).
    await checkKey(env, goodKey.plaintext);
    await checkKey(env, goodKey.plaintext);
    await checkKey(env, "YURI-INVALID-KEY-!!");
    const badBody = await makeSignedInput("POST", "/free/step", { token: "nonexistent", fingerprint: "x".repeat(64) });
    await dispatch(buildRoutes(), env.ctx, env.config, badBody);

    // Synthetic volume rows (aggregation-math proof; shapes verified by the
    // real flows above): tamper spike, server_error, payment_webhook failure,
    // free-flow funnel, hwid churn across sessions, update-required detail.
    const t = now();
    const ins = env.db.prepare("INSERT INTO events (id, key_id, type, detail, created_at) VALUES (?, NULL, ?, ?, ?)");
    for (let i = 0; i < 25; i++) ins.run(`tmspke${i}`, "tamper", "client:http_hook", t - 60);
    for (let i = 0; i < 3; i++) ins.run(`srv${i}`, "server_error", "OperationError", t - 120);
    ins.run("wbf1", "payment_webhook", "invalid_signature", t - 300);
    ins.run("wbf2", "payment_webhook", "invalid_signature", t - 300);
    ins.run("ffs1", "free_flow", "start:yuri", t - 400);
    ins.run("ffs2", "free_flow", "step:1/2", t - 400);
    ins.run("ffs3", "free_flow", "step:2/2", t - 400);
    ins.run("ffc1", "free_flow", "claim:yuri", t - 400);
    ins.run("urf1", "validate_fail", "loader-version", t - 200);

    // A free attempt started + completed, and a free key issued.
    env.db
      .prepare("INSERT INTO free_attempts (id, project_id, fingerprint, step, token_hash, started_at, step_started_at, completed_at) VALUES (?, '11111111111111111111111111111111', 'fp', 2, 'th', ?, ?, ?)")
      .run("fa1", t - 500, t - 500, t - 400);
    env.db
      .prepare("INSERT INTO keys (id, project_id, key_hash, tier, status, note, total_executions, created_by, created_at, expires_at) VALUES (?, '11111111111111111111111111111111', 'x', 'free', 'active', NULL, 0, 'free-flow', ?, NULL)")
      .run("freekey1", t - 400);

    // HWID churn: one key with 3 distinct hwids in sessions (all recent so
    // they land inside BOTH the 1h metrics window and the 7d churn window —
    // the churn query is always-7d, sessions.created is window-scoped).
    for (let i = 0; i < 3; i++) {
      env.db
        .prepare("INSERT INTO sessions (id, key_id, script_id, version, hwid_hash, ip_hash, roblox_user_id, place_id, watermark_id, created_at, expires_at) VALUES (?, ?, ?, 1, ?, 'ip', 1, 1, ?, ?, ?)")
        .run(`schurn${i}`, goodKey.id, SCRIPT_ID, `hw${i}`, `wm${i}`, t - 60 * (i + 1), t + 60);
    }
    env.db.prepare("UPDATE keys SET hwid_resets = 2 WHERE id = ?").run(goodKey.id);
  });

  test("real flows + synthetic rows are counted with correct shapes", async () => {
    const { status, json } = await getJson(env, "/admin/metrics?window=1h");
    expect(status).toBe(200);
    expect(json.window).toBe("1h");
    const auth = json.auth as { check_key: { ok: number }; total_fail: number };
    expect(auth.check_key.ok).toBe(2); // real valid check_key flows
    // validate_fail in window: 1 real checksum reject + 1 synthetic
    // loader-version row below (free/step rejects record free_bypass, not
    // validate_fail — freekey.ts records its own taxonomy).
    expect(auth.total_fail).toBe(2);
    const tamper = json.tamper as { total: number; by_detail: { detail: string; n: number }[] };
    expect(tamper.total).toBe(25);
    expect(tamper.by_detail[0]).toEqual({ detail: "client:http_hook", n: 25 });
    const srv = json.server_errors as { total: number };
    expect(srv.total).toBe(3);
    const pay = json.payments as { webhook_failures: number };
    expect(pay.webhook_failures).toBe(2);
    const ff = json.free_flow as Record<string, number>;
    expect(ff.starts).toBe(1);
    expect(ff.steps).toBe(2);
    expect(ff.claims).toBe(1);
    expect(ff.attempts_started).toBe(1);
    expect(ff.attempts_completed).toBe(1);
    expect(ff.keys_issued).toBe(1);
    expect(ff.conversion).toBe(1);
    expect(json.update_required).toBe(1);
    const churn = json.hwid_churn as { window: string; rows: { key_id: string; distinct_hwids: number; hwid_resets: number }[] };
    expect(churn.window).toBe("7d");
    const mine = churn.rows.find((r) => r.key_id === goodKey.id);
    expect(mine?.distinct_hwids).toBe(3);
    expect(mine?.hwid_resets).toBe(2);
    const sessions = json.sessions as Record<string, number>;
    expect(sessions.created).toBeGreaterThanOrEqual(3);
    const nodes = json.nodes as Record<string, number>;
    expect(nodes.active).toBe(2);
    expect(json.protocol).toEqual({ active_versions: 2 });
  });

  test("window param: invalid falls back to 24h, 7d accepted", async () => {
    const bad = await getJson(env, "/admin/metrics?window=banana");
    expect(bad.json.window).toBe("24h");
    const week = await getJson(env, "/admin/metrics?window=7d");
    expect(week.json.window).toBe("7d");
    expect((week.json.tamper as { total: number }).total).toBe(25); // within 7d too
  });

  test("auth gates: 401 without token, 403 for reseller role", async () => {
    const anon = await getJson(env, "/admin/metrics?window=1h", "nope");
    expect(anon.status).toBe(401);
    const reseller = await getJson(env, "/admin/metrics?window=1h", RESELLER_TOKEN);
    expect(reseller.status).toBe(403);
    const resellerAlerts = await getJson(env, "/admin/alerts", RESELLER_TOKEN);
    expect(resellerAlerts.status).toBe(403);
  });

  test("M1 analytics overview is unchanged (additive check)", async () => {
    const { status, json } = await getJson(env, "/admin/analytics/overview");
    expect(status).toBe(200);
    expect(json.window).toBe("24h");
    expect(json.tamper_24h).toBe(25);
  });
});

describe("M12 /admin/alerts — rule evaluation", () => {
  let env: TestEnv;

  beforeAll(async () => {
    env = await buildEnv();
    const t = now();
    const ins = env.db.prepare("INSERT INTO events (id, key_id, type, detail, created_at) VALUES (?, NULL, ?, ?, ?)");
    // 1h: tamper 25 (warning band), free_bypass 35, 250 validate_fail + 50 ok (spike + stalled shape)
    for (let i = 0; i < 25; i++) ins.run(`a-t${i}`, "tamper", "client:debug_hook", t - 60);
    for (let i = 0; i < 35; i++) ins.run(`a-b${i}`, "free_bypass", "step-too-fast:1", t - 60);
    for (let i = 0; i < 250; i++) ins.run(`a-f${i}`, "validate_fail", "key-status", t - 60);
    for (let i = 0; i < 50; i++) ins.run(`a-o${i}`, "validate_ok", "check_key", t - 60);
    for (let i = 0; i < 12; i++) ins.run(`a-w${i}`, "payment_webhook", "invalid_signature", t - 3600 * 20);
    for (let i = 0; i < 5; i++) ins.run(`a-s${i}`, "server_error", "OperationError", t - 60);
  });

  test("firing rules match thresholds with severities and runbook anchors", async () => {
    const { status, json } = await getJson(env, "/admin/alerts");
    expect(status).toBe(200);
    const alerts = json.alerts as { id: string; severity: string; runbook: string; detail: string }[];
    const ids = alerts.map((a) => a.id);
    expect(ids).toContain("tamper-spike-1h"); // 25 >= 20 warning
    expect(alerts.find((a) => a.id === "tamper-spike-1h")?.severity).toBe("warning");
    expect(ids).toContain("free-bypass-spike-1h"); // 35 >= 30
    expect(ids).toContain("auth-fail-spike-1h"); // 250 fails, ratio 250/300 >= 0.5
    expect(ids).toContain("webhook-failures-24h"); // 12 >= 10
    expect(ids).not.toContain("server-errors-1h"); // 5 < 10
    expect(ids).not.toContain("error-budget-24h"); // 24h window includes same 300 attempts, ratio 250/300 = 0.83 >= 0.05 BUT attempts 300 < 500
    expect(ids).not.toContain("sessions-stalled-1h"); // 50 ok
    expect(ids).not.toContain("nodes-degraded"); // 2 active nodes seeded
    expect(ids).not.toContain("protocol-inactive"); // 2 active versions seeded
    for (const a of alerts) expect(a.runbook).toMatch(/^tools\/ops\/RUNBOOK-M12\.md#/);
  });

  test("evaluateAlerts is pure and covers every doc §19 class", () => {
    const base: MetricsSnapshot = {
      window: "1h",
      since: 0,
      generated_at: 0,
      auth: { init: { ok: 0 }, payload: { ok: 0 }, heartbeat: { ok: 0 }, check_key: { ok: 0 }, total_ok: 0, total_fail: 0, attempts: 0, success_rate: null },
      failure_reasons: [],
      update_required: 0,
      tamper: { total: 0, by_detail: [] },
      free_flow: { starts: 0, steps: 0, claims: 0, attempts_started: 0, attempts_completed: 0, keys_issued: 0, conversion: null },
      bypass: { total: 0, by_detail: [] },
      payments: { webhook_failures: 0, by_detail: [], outcomes: [] },
      sessions: { created: 0, live_now: 0, killed: 0 },
      keys: { active: 0, revoked: 0, expiring_7d: 0 },
      hwid_churn: { window: "7d", rows: [] },
      server_errors: { total: 0, by_detail: [] },
      nodes: { active: 2, inactive: 0 },
      protocol: { active_versions: 1 },
    };
    expect(evaluateAlerts(base, base)).toEqual([]);

    const t = ALERT_THRESHOLDS;
    const spike = structuredClone(base);
    spike.server_errors.total = t.serverErrors1hCritical;
    spike.tamper.total = t.tamper1hCritical;
    spike.bypass.total = t.freeBypass1hWarning;
    spike.auth.total_fail = t.authFail1hCount;
    spike.auth.attempts = 400;
    spike.auth.total_ok = 150;
    spike.auth.success_rate = 150 / 400;
    spike.payments.webhook_failures = t.webhookFailures24hWarning;
    const alerts = evaluateAlerts(spike, spike).map((a) => a.id);
    expect(alerts).toContain("server-errors-1h");
    expect(alerts).toContain("tamper-spike-1h");
    expect(alerts).toContain("free-bypass-spike-1h");
    expect(alerts).toContain("auth-fail-spike-1h");
    expect(alerts).toContain("webhook-failures-24h");

    const budget = structuredClone(base);
    budget.auth.attempts = 600;
    budget.auth.total_fail = 40;
    budget.auth.total_ok = 560;
    budget.auth.success_rate = 560 / 600;
    expect(evaluateAlerts(budget, budget).map((a) => a.id)).toContain("error-budget-24h");

    const churn = structuredClone(base);
    churn.hwid_churn.rows = [{ key_id: "k1", distinct_hwids: t.hwidChurn7dDistinct, hwid_resets: 4 }];
    expect(evaluateAlerts(churn, churn).map((a) => a.id)).toContain("hwid-churn-7d");

    const stalled = structuredClone(base);
    stalled.auth.total_fail = 3;
    expect(evaluateAlerts(stalled, stalled).map((a) => a.id)).toContain("sessions-stalled-1h");

    const degraded = structuredClone(base);
    degraded.nodes.active = 1;
    expect(evaluateAlerts(degraded, degraded).map((a) => a.id)).toContain("nodes-degraded");
    degraded.nodes.active = 0;
    expect(evaluateAlerts(degraded, degraded).find((a) => a.id === "nodes-degraded")?.severity).toBe("critical");

    const noProto = structuredClone(base);
    noProto.protocol.active_versions = 0;
    expect(evaluateAlerts(noProto, noProto).map((a) => a.id)).toContain("protocol-inactive");
  });
});

// ---------------------------------------------------------------------------
// §18 hygiene scan (D-M12-13): keys/tokens/HWIDs never in URLs or logs.
// ---------------------------------------------------------------------------

describe("M12 hygiene scan (doc §18)", () => {
  test("route table carries no secret-valued path params (ids only)", () => {
    for (const route of buildRoutes()) {
      const secretParams = route.pattern.split("/").filter((seg) => /^:(key|token|hwid|secret|password|signature|proof)/i.test(seg));
      expect(secretParams).toEqual([]);
    }
  });

  test("api/src contains no console logging (the events table is the log)", () => {
    const srcDir = join(import.meta.dir, "..", "src");
    const offenders: string[] = [];
    for (const file of readdirSync(srcDir)) {
      if (!file.endsWith(".ts")) continue;
      const text = readFileSync(join(srcDir, file), "utf8");
      if (/console\.(log|info|warn|error|debug)/.test(text)) offenders.push(file);
    }
    expect(offenders).toEqual([]);
  });
});
