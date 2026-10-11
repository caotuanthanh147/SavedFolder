// Module M12 — Ops: derived service metrics + alert evaluation (doc §19).
// PURE-DERIVED from existing tables (D-M12-1): no new tables, no
// migrations, no hot-path writes. Every counter below is read from data
// the running service already persists (events taxonomy, sessions, keys,
// free_attempts, payment_events, nodes, protocol_versions — see
// RESEARCH-M12 sources 3-11).
//
// Routes (registered in router.ts):
//   GET /admin/metrics?window=1h|24h|7d   — metrics snapshot (owner/admin)
//   GET /admin/alerts                     — evaluated alert rows (owner/admin)
//
// NOT in v1 (D-M12-4): latency distribution, CDN hit ratio — need
// per-request instrumentation; recommended path is Workers Analytics
// Engine (owner infrastructure decision, runbook §latency).

import { AppContext, ApiConfig, RequestInput } from "./flow";
import { authenticate } from "./admin";

function json(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), { status, headers: { "content-type": "application/json" } });
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

const WINDOWS: Record<string, number> = { "1h": 3600, "24h": 86400, "7d": 604800 };
const CHURN_WINDOW_SEC = 604800; // hwid churn is always a 7d semantic (D-M12-6 rule 7)

// Alert thresholds (D-M12-2: exported constants, pinned by tests).
export const ALERT_THRESHOLDS = {
  serverErrors1hCritical: 10,
  tamper1hWarning: 20,
  tamper1hCritical: 100,
  authFail1hCount: 200,
  authFail1hRatio: 0.5,
  errorBudget24hAttempts: 500,
  errorBudget24hRatio: 0.05,
  freeBypass1hWarning: 30,
  webhookFailures24hWarning: 10,
  hwidChurn7dDistinct: 5,
  nodesMinimumActive: 2,
} as const;

export interface DetailCount {
  detail: string;
  n: number;
}

export interface FlowCount {
  ok: number;
}

export interface HwidChurnRow {
  key_id: string;
  distinct_hwids: number;
  hwid_resets: number;
}

export interface MetricsSnapshot {
  window: string;
  since: number;
  generated_at: number;
  auth: {
    init: FlowCount;
    payload: FlowCount;
    heartbeat: FlowCount;
    check_key: FlowCount;
    total_ok: number;
    total_fail: number;
    attempts: number;
    success_rate: number | null;
  };
  failure_reasons: DetailCount[];
  update_required: number;
  tamper: { total: number; by_detail: DetailCount[] };
  free_flow: {
    starts: number;
    steps: number;
    claims: number;
    attempts_started: number;
    attempts_completed: number;
    keys_issued: number;
    conversion: number | null;
  };
  bypass: { total: number; by_detail: DetailCount[] };
  payments: { webhook_failures: number; by_detail: DetailCount[]; outcomes: DetailCount[] };
  sessions: { created: number; live_now: number; killed: number };
  keys: { active: number; revoked: number; expiring_7d: number };
  hwid_churn: { window: "7d"; rows: HwidChurnRow[] };
  server_errors: { total: number; by_detail: DetailCount[] };
  nodes: { active: number; inactive: number };
  protocol: { active_versions: number };
}

async function detailCounts(ctx: AppContext, type: string, since: number, limit: number): Promise<DetailCount[]> {
  // Totals come from separate exact COUNT(*) queries (see below) so a
  // >limit distinct-detail cardinality can never under-count a total.
  return await ctx.db.all<{ detail: string; n: number }>(
    "SELECT detail, COUNT(*) AS n FROM events WHERE type = ? AND created_at >= ? GROUP BY detail ORDER BY n DESC LIMIT ?",
    [type, since, limit],
  );
}

// One SQL pass over the derivation inputs for a given window.
export async function collectMetrics(ctx: AppContext, windowKey: string): Promise<MetricsSnapshot> {
  const windowSec = WINDOWS[windowKey];
  const now = Math.floor(ctx.nowSec);
  const since = now - windowSec;

  const okFlowsP = ctx.db.all<{ detail: string; n: number }>(
    "SELECT detail, COUNT(*) AS n FROM events WHERE type = 'validate_ok' AND created_at >= ? GROUP BY detail",
    [since],
  );
  const failTotalP = ctx.db.first<{ n: number }>("SELECT COUNT(*) AS n FROM events WHERE type = 'validate_fail' AND created_at >= ?", [since]);
  const failReasonsP = ctx.db.all<{ detail: string; n: number }>(
    "SELECT detail, COUNT(*) AS n FROM events WHERE type = 'validate_fail' AND created_at >= ? GROUP BY detail ORDER BY n DESC LIMIT 12",
    [since],
  );
  const tamperTotalP = ctx.db.first<{ n: number }>("SELECT COUNT(*) AS n FROM events WHERE type = 'tamper' AND created_at >= ?", [since]);
  const tamperDetailP = detailCounts(ctx, "tamper", since, 12);
  const freeFlowP = ctx.db.all<{ detail: string; n: number }>(
    "SELECT detail, COUNT(*) AS n FROM events WHERE type = 'free_flow' AND created_at >= ? GROUP BY detail",
    [since],
  );
  const bypassTotalP = ctx.db.first<{ n: number }>("SELECT COUNT(*) AS n FROM events WHERE type = 'free_bypass' AND created_at >= ?", [since]);
  const bypassDetailP = detailCounts(ctx, "free_bypass", since, 12);
  const paymentsFailP = ctx.db.all<{ detail: string; n: number }>(
    "SELECT detail, COUNT(*) AS n FROM events WHERE type = 'payment_webhook' AND created_at >= ? GROUP BY detail ORDER BY n DESC LIMIT 12",
    [since],
  );
  // payment_events is applied lazily by the payments module (payments.ts
  // PAYMENTS_SCHEMA_SQL) — a deployment that never received a webhook has
  // no table, and the truthful outcome histogram for it is empty. Guarded
  // so metrics renders on payments-less environments too. (The adapter can
  // throw synchronously — SqliteAdapter.all is not an async fn — so the
  // guard must wrap the call, not just the promise.)
  const paymentOutcomesP = (async () => {
    try {
      return await ctx.db.all<{ outcome: string; n: number }>("SELECT outcome, COUNT(*) AS n FROM payment_events WHERE created_at >= ? GROUP BY outcome", [since]);
    } catch {
      return [] as { outcome: string; n: number }[];
    }
  })();
  const attemptsP = ctx.db.first<{ n: number; c: number }>(
    "SELECT COUNT(*) AS n, SUM(CASE WHEN completed_at IS NOT NULL THEN 1 ELSE 0 END) AS c FROM free_attempts WHERE started_at >= ?",
    [since],
  );
  const freeKeysP = ctx.db.first<{ n: number }>("SELECT COUNT(*) AS n FROM keys WHERE created_by = 'free-flow' AND created_at >= ?", [since]);
  const sessionsCreatedP = ctx.db.first<{ n: number }>("SELECT COUNT(*) AS n FROM sessions WHERE created_at >= ?", [since]);
  const sessionsLiveP = ctx.db.first<{ n: number }>("SELECT COUNT(*) AS n FROM sessions WHERE expires_at > ?", [now]);
  const sessionsKilledP = ctx.db.first<{ n: number }>("SELECT COUNT(*) AS n FROM events WHERE type = 'session_kill' AND created_at >= ?", [since]);
  const keysActiveP = ctx.db.first<{ n: number }>("SELECT COUNT(*) AS n FROM keys WHERE status = 'active'", []);
  const keysRevokedP = ctx.db.first<{ n: number }>("SELECT COUNT(*) AS n FROM keys WHERE status = 'revoked'", []);
  const keysExpiringP = ctx.db.first<{ n: number }>(
    "SELECT COUNT(*) AS n FROM keys WHERE status = 'active' AND expires_at IS NOT NULL AND expires_at > ? AND expires_at <= ?",
    [now, now + 604800],
  );
  const churnP = ctx.db.all<{ key_id: string; dh: number; hwid_resets: number }>(
    `SELECT s.key_id AS key_id, COUNT(DISTINCT s.hwid_hash) AS dh, MAX(k.hwid_resets) AS hwid_resets
     FROM sessions s JOIN keys k ON k.id = s.key_id
     WHERE s.created_at >= ?
     GROUP BY s.key_id HAVING dh >= 2 ORDER BY dh DESC LIMIT 5`,
    [now - CHURN_WINDOW_SEC],
  );
  const serverErrorsTotalP = ctx.db.first<{ n: number }>("SELECT COUNT(*) AS n FROM events WHERE type = 'server_error' AND created_at >= ?", [since]);
  const serverErrorsDetailP = detailCounts(ctx, "server_error", since, 8);
  const nodesP = ctx.db.all<{ active: number; n: number }>("SELECT active, COUNT(*) AS n FROM nodes GROUP BY active", []);
  const protocolP = ctx.db.first<{ n: number }>("SELECT COUNT(*) AS n FROM protocol_versions WHERE active = 1", []);

  const [okFlows, failTotal, failReasons, tamperTotalRow, tamperDetail, freeFlow, bypassTotalRow, bypassDetail, paymentsFail, paymentOutcomes, attempts, freeKeys, sessionsCreated, sessionsLive, sessionsKilled, keysActive, keysRevoked, keysExpiring, churn, serverErrorsTotalRow, serverErrorsDetail, nodes, protocol] =
    await Promise.all([
      okFlowsP, failTotalP, failReasonsP, tamperTotalP, tamperDetailP, freeFlowP, bypassTotalP, bypassDetailP, paymentsFailP, paymentOutcomesP, attemptsP,
      freeKeysP, sessionsCreatedP, sessionsLiveP, sessionsKilledP, keysActiveP, keysRevokedP, keysExpiringP, churnP, serverErrorsTotalP, serverErrorsDetailP, nodesP, protocolP,
    ]);

  const okBy = new Map(okFlows.map((r) => [r.detail, r.n]));
  const flow = (d: string): FlowCount => ({ ok: okBy.get(d) ?? 0 });
  let starts = 0;
  let steps = 0;
  let claims = 0;
  for (const r of freeFlow) {
    if (r.detail.startsWith("start:")) starts += r.n;
    else if (r.detail.startsWith("step:")) steps += r.n;
    else if (r.detail.startsWith("claim:")) claims += r.n;
  }
  const updateRequiredDetails = new Set(["loader-version", "init-build", "version-gone", "build-changed"]);
  const updateRequired = failReasons.filter((r) => updateRequiredDetails.has(r.detail)).reduce((acc, r) => acc + r.n, 0);

  const totalOk = okFlows.reduce((acc, r) => acc + r.n, 0);
  const totalFail = failTotal?.n ?? 0;
  // Auth attempts over the window (ok + fail). Distinct from `attempts`
  // above, which is the free_attempts table row (started/completed counts).
  const authAttempts = totalOk + totalFail;
  const attemptsStarted = attempts?.n ?? 0;
  const attemptsCompleted = attempts?.c ?? 0;
  const webhookFailures = paymentsFail.reduce((acc, r) => acc + r.n, 0);
  let nodesActive = 0;
  let nodesInactive = 0;
  for (const r of nodes) {
    if (r.active === 1) nodesActive += r.n;
    else nodesInactive += r.n;
  }

  return {
    window: windowKey,
    since,
    generated_at: now,
    auth: {
      init: flow("auth_init"),
      payload: flow("auth_payload"),
      heartbeat: flow("heartbeat"),
      check_key: flow("check_key"),
      total_ok: totalOk,
      total_fail: totalFail,
      attempts: authAttempts,
      success_rate: authAttempts > 0 ? totalOk / authAttempts : null,
    },
    failure_reasons: failReasons,
    update_required: updateRequired,
    tamper: { total: tamperTotalRow?.n ?? 0, by_detail: tamperDetail },
    free_flow: {
      starts,
      steps,
      claims,
      attempts_started: attemptsStarted,
      attempts_completed: attemptsCompleted,
      keys_issued: freeKeys?.n ?? 0,
      conversion: attemptsStarted > 0 ? (freeKeys?.n ?? 0) / attemptsStarted : null,
    },
    bypass: { total: bypassTotalRow?.n ?? 0, by_detail: bypassDetail },
    payments: {
      webhook_failures: webhookFailures,
      by_detail: paymentsFail,
      outcomes: paymentOutcomes.map((r) => ({ detail: r.outcome, n: r.n })),
    },
    sessions: { created: sessionsCreated?.n ?? 0, live_now: sessionsLive?.n ?? 0, killed: sessionsKilled?.n ?? 0 },
    keys: { active: keysActive?.n ?? 0, revoked: keysRevoked?.n ?? 0, expiring_7d: keysExpiring?.n ?? 0 },
    hwid_churn: {
      window: "7d",
      rows: churn.map((r) => ({ key_id: r.key_id, distinct_hwids: r.dh, hwid_resets: r.hwid_resets ?? 0 })),
    },
    server_errors: { total: serverErrorsTotalRow?.n ?? 0, by_detail: serverErrorsDetail },
    nodes: { active: nodesActive, inactive: nodesInactive },
    protocol: { active_versions: protocol?.n ?? 0 },
  };
}

export type AlertSeverity = "critical" | "warning";

export interface Alert {
  id: string;
  severity: AlertSeverity;
  title: string;
  detail: string;
  runbook: string;
}

function alert(id: string, severity: AlertSeverity, title: string, detail: string): Alert {
  return { id, severity, title, detail, runbook: `tools/ops/RUNBOOK-M12.md#${id}` };
}

// Pure rule evaluation over the 1h and 24h snapshots (D-M12-6).
// Exported for tests; handlers below are the only callers in prod.
export function evaluateAlerts(m1h: MetricsSnapshot, m24h: MetricsSnapshot): Alert[] {
  const out: Alert[] = [];
  const t = ALERT_THRESHOLDS;

  if (m1h.server_errors.total >= t.serverErrors1hCritical) {
    const top = m1h.server_errors.by_detail.map((d) => `${d.detail}×${d.n}`).join(", ");
    out.push(alert("server-errors-1h", "critical", "Server errors in the last hour",
      `${m1h.server_errors.total} server_error events (≥${t.serverErrors1hCritical}). Includes signing failures — they surface as thrown errors. Top: ${top || "none"}`));
  }

  if (m1h.tamper.total >= t.tamper1hCritical) {
    out.push(alert("tamper-spike-1h", "critical", "Tamper events spiked", `${m1h.tamper.total} in the last hour (≥${t.tamper1hCritical})`));
  } else if (m1h.tamper.total >= t.tamper1hWarning) {
    out.push(alert("tamper-spike-1h", "warning", "Tamper events elevated", `${m1h.tamper.total} in the last hour (≥${t.tamper1hWarning})`));
  }

  if (m1h.auth.total_fail >= t.authFail1hCount && m1h.auth.success_rate !== null && m1h.auth.success_rate < 1 - t.authFail1hRatio) {
    const top = m1h.failure_reasons.slice(0, 3).map((d) => `${d.detail}×${d.n}`).join(", ");
    out.push(alert("auth-fail-spike-1h", "warning", "Auth failure spike (brute-force shape)",
      `${m1h.auth.total_fail} failures in 1h with success rate ${(m1h.auth.success_rate * 100).toFixed(1)}%. Top reasons: ${top}`));
  }

  if (m24h.auth.attempts >= t.errorBudget24hAttempts && m24h.auth.success_rate !== null && m24h.auth.success_rate < 1 - t.errorBudget24hRatio) {
    out.push(alert("error-budget-24h", "warning", "24h error budget breach",
      `success rate ${(m24h.auth.success_rate * 100).toFixed(1)}% over ${m24h.auth.attempts} attempts (budget <${(t.errorBudget24hRatio * 100).toFixed(0)}% failures)`));
  }

  if (m1h.bypass.total >= t.freeBypass1hWarning) {
    out.push(alert("free-bypass-spike-1h", "warning", "Free-flow bypass attempts spiked", `${m1h.bypass.total} in the last hour (≥${t.freeBypass1hWarning})`));
  }

  if (m24h.payments.webhook_failures >= t.webhookFailures24hWarning) {
    const top = m24h.payments.by_detail.slice(0, 3).map((d) => `${d.detail}×${d.n}`).join(", ");
    out.push(alert("webhook-failures-24h", "warning", "Payment webhook failures", `${m24h.payments.webhook_failures} rejected webhooks in 24h. Top: ${top || "none"}`));
  }

  const churnOffenders = m24h.hwid_churn.rows.filter((r) => r.distinct_hwids >= t.hwidChurn7dDistinct);
  if (churnOffenders.length > 0) {
    const top = churnOffenders.slice(0, 3).map((r) => `${r.key_id} (${r.distinct_hwids} hwids)`).join(", ");
    out.push(alert("hwid-churn-7d", "warning", "Unusual HWID churn on keys", `Keys with ≥${t.hwidChurn7dDistinct} distinct HWIDs in 7d: ${top}`));
  }

  if (m24h.nodes.active === 0) {
    out.push(alert("nodes-degraded", "critical", "No active nodes", "The /sync node list is empty — new loaders cannot bootstrap. Register at least two hostnames (doc §19)."));
  } else if (m24h.nodes.active < ALERT_THRESHOLDS.nodesMinimumActive) {
    out.push(alert("nodes-degraded", "warning", "Fewer than two active nodes", `${m24h.nodes.active} active node(s) — doc §19 requires at least two hostnames for domain-block resilience.`));
  }

  if (m24h.protocol.active_versions === 0) {
    out.push(alert("protocol-inactive", "critical", "No active protocol version", "protocol_versions has no active row — the min-loader gate rejects or kills every auth init/check_key."));
  }

  if (m1h.auth.total_ok === 0 && m1h.auth.total_fail >= 1) {
    out.push(alert("sessions-stalled-1h", "warning", "No successful auth in the last hour", `0 validate_ok vs ${m1h.auth.total_fail} failures — service is up but rejecting.`));
  }

  return out;
}

// GET /admin/metrics?window=1h|24h|7d (owner/admin — same gate as the
// M1 analytics overview; reseller/support excluded).
export async function handleAdminMetrics(ctx: AppContext, config: ApiConfig, input: RequestInput): Promise<Response> {
  const admin = await authenticate(ctx, config, input);
  if (!admin) return json({ error: "unauthorized" }, 401);
  if (admin.role !== "owner" && admin.role !== "admin") return json({ error: "forbidden" }, 403);
  const q = queryOf(input);
  const windowKey = q.window && WINDOWS[q.window] !== undefined ? q.window : "24h";
  const snapshot = await collectMetrics(ctx, windowKey);
  return json(snapshot);
}

// GET /admin/alerts (owner/admin) — evaluates the 1h + 24h snapshots and
// returns the firing alert rows. Poll-consumable (stateless by design,
// D-M12-2); dedupe/muting belongs to the poller (dashboard bell, bot).
export async function handleAdminAlerts(ctx: AppContext, config: ApiConfig, input: RequestInput): Promise<Response> {
  const admin = await authenticate(ctx, config, input);
  if (!admin) return json({ error: "unauthorized" }, 401);
  if (admin.role !== "owner" && admin.role !== "admin") return json({ error: "forbidden" }, 403);
  const [m1h, m24h] = await Promise.all([collectMetrics(ctx, "1h"), collectMetrics(ctx, "24h")]);
  return json({ generated_at: m1h.generated_at, alerts: evaluateAlerts(m1h, m24h) });
}
