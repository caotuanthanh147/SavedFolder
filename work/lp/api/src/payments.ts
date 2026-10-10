import { hmacSha256, randomId, sha256Hex, utf8 } from "./crypto";
import { ApiConfig, AppContext, RequestInput, headerValue, recordEvent } from "./flow";
import { generateKey, hashKey } from "./keys";
import { authenticate } from "./admin";

// Module M10 — payments and webhooks (doc.md §17). Design per DECISIONS-M10:
// provider-agnostic verifier interface (D-M10-1) with `stripe` (documented
// Stripe-Signature scheme: t=/v1= HMAC-SHA256 hex over `${t}.${rawBody}`,
// 5-minute default tolerance, any valid v1 accepted for rotation) and
// `custom` (dev/test: X-Event-Id + X-Signature hex HMAC-SHA256(rawBody)).
// Idempotency = insert-first gate on UNIQUE(provider, event_id) (D-M10-2).
// Confirmed payment issues a key through the same path as M9 (D-M10-4);
// refunds revoke + conditional blacklist, disputes always blacklist
// (D-M10-5). Storage = additive M10-applied tables until CCP-4 ruling
// (D-M10-6). The webhook is unauthenticated by admin token — the signature
// IS the auth — but rate-limited per IP and size-capped by the global
// MAX_BODY_BYTES (16 KiB, stricter than the 256 KiB D-M10-8 note; payment
// events in practice fit comfortably).

export interface PaymentsConfig {
  webhookSecrets: Record<string, string[]>;
  signatureToleranceSec: number;
  requestsPerIpPerMin: number;
  providerBase?: string;
  providerApiKey?: string;
  fetchImpl?: typeof fetch;
}

export const DEFAULT_SIG_TOLERANCE_SEC = 300;
const PROVIDERS = ["stripe", "custom"] as const;
type ProviderName = (typeof PROVIDERS)[number];

// ---------------------------------------------------------------------------
// Additive M10-applied schema (CCP-4). CREATE TABLE IF NOT EXISTS everywhere;
// idempotent, applied lazily per isolate so neither M2's migrations nor any
// other module's tree is touched.
// ---------------------------------------------------------------------------

export const PAYMENTS_SCHEMA_SQL = `
CREATE TABLE IF NOT EXISTS orders (
  id            TEXT PRIMARY KEY,
  provider      TEXT NOT NULL,
  provider_order_id TEXT NOT NULL,
  product_ref   TEXT NOT NULL,
  project_id    TEXT NOT NULL,
  key_id        TEXT,
  discord_id    TEXT,
  email         TEXT,
  amount_minor  INTEGER,
  currency      TEXT,
  status        TEXT NOT NULL,
  created_at    INTEGER NOT NULL,
  updated_at    INTEGER NOT NULL
);
CREATE UNIQUE INDEX IF NOT EXISTS idx_orders_provider_order ON orders(provider, provider_order_id);
CREATE INDEX IF NOT EXISTS idx_orders_status ON orders(status);
CREATE TABLE IF NOT EXISTS payment_events (
  provider      TEXT NOT NULL,
  event_id      TEXT NOT NULL,
  event_type    TEXT NOT NULL,
  outcome       TEXT NOT NULL,
  order_id      TEXT,
  created_at    INTEGER NOT NULL,
  PRIMARY KEY (provider, event_id)
);
CREATE TABLE IF NOT EXISTS payment_products (
  id              TEXT PRIMARY KEY,
  provider        TEXT NOT NULL,
  product_ref     TEXT NOT NULL,
  project_id      TEXT NOT NULL,
  tier            TEXT NOT NULL,
  days            INTEGER,
  scripts         TEXT NOT NULL,
  refund_blacklists INTEGER NOT NULL DEFAULT 0,
  active          INTEGER NOT NULL DEFAULT 1,
  created_at      INTEGER NOT NULL
);
CREATE UNIQUE INDEX IF NOT EXISTS idx_payment_products_ref ON payment_products(provider, product_ref);
`;

let schemaReady: WeakMap<AppContext, Promise<void>> | null = null;

function ensureSchema(ctx: AppContext): Promise<void> {
  if (schemaReady === null) schemaReady = new WeakMap();
  let p = schemaReady.get(ctx);
  if (p === undefined) {
    p = (async () => {
      for (const stmt of PAYMENTS_SCHEMA_SQL.split(";").map((s) => s.trim()).filter((s) => s.length > 0)) {
        await ctx.db.run(stmt, []);
      }
    })();
    schemaReady.set(ctx, p);
  }
  return p;
}

// ---------------------------------------------------------------------------
// Provider verifiers (D-M10-1)
// ---------------------------------------------------------------------------

export interface WebhookVerification {
  ok: boolean;
  reason: "bad_header" | "bad_signature" | "stale_timestamp" | "missing_event_id";
  eventId: string | null;
}

export interface ProviderVerifier {
  name: ProviderName;
  verify(headers: Record<string, string>, bodyBytes: Uint8Array, nowSec: number, secrets: string[], toleranceSec: number): Promise<WebhookVerification>;
}

function constantTimeHexEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let same = true;
  for (let i = 0; i < a.length; i++) {
    if (a.charCodeAt(i) !== b.charCodeAt(i)) same = false;
  }
  return same;
}

async function hmacHex(secret: string, payload: Uint8Array): Promise<string> {
  const mac = await hmacSha256(utf8(secret), payload);
  return Array.from(mac, (b) => b.toString(16).padStart(2, "0")).join("");
}

// Stripe: `Stripe-Signature: t=<unix>,v1=<hex>[,v1=<hex>…]`. Signed payload
// is `${t}.${rawBody}`. Any valid v1 authenticates (rotation window). Only
// t=/v1= fields are parsed — everything else is ignored (downgrade defense).
export const stripeVerifier: ProviderVerifier = {
  name: "stripe",
  async verify(headers, bodyBytes, nowSec, secrets, toleranceSec) {
    const raw = headerValue(headers, "Stripe-Signature");
    if (raw === null || raw.length === 0 || raw.length > 1024) {
      return { ok: false, reason: "bad_header", eventId: null };
    }
    let ts = "";
    const v1s: string[] = [];
    for (const part of raw.split(",")) {
      const eq = part.indexOf("=");
      if (eq <= 0) continue;
      const k = part.slice(0, eq).trim();
      const v = part.slice(eq + 1).trim();
      if (k === "t" && /^\d{1,12}$/.test(v)) ts = v;
      else if (k === "v1" && /^[0-9a-f]{64}$/.test(v)) v1s.push(v);
    }
    if (ts === "" || v1s.length === 0) return { ok: false, reason: "bad_header", eventId: null };
    if (Math.abs(nowSec - parseInt(ts, 10)) > toleranceSec) {
      return { ok: false, reason: "stale_timestamp", eventId: null };
    }
    const signed = utf8(`${ts}.`);
    const payload = new Uint8Array([...signed, ...bodyBytes]);
    for (const secret of secrets) {
      const expected = await hmacHex(secret, payload);
      for (const supplied of v1s) {
        if (constantTimeHexEqual(supplied, expected)) {
          return { ok: true, reason: "bad_signature", eventId: null };
        }
      }
    }
    return { ok: false, reason: "bad_signature", eventId: null };
  },
};

// custom (dev/test): X-Event-Id + X-Signature: hex HMAC-SHA256(rawBody, secret)
export const customVerifier: ProviderVerifier = {
  name: "custom",
  async verify(headers, bodyBytes, _nowSec, secrets) {
    const eventId = headerValue(headers, "X-Event-Id");
    const sig = headerValue(headers, "X-Signature");
    if (eventId === null || eventId.length < 8 || eventId.length > 128 || sig === null || !/^[0-9a-f]{64}$/.test(sig)) {
      return { ok: false, reason: "bad_header", eventId: null };
    }
    for (const secret of secrets) {
      const expected = await hmacHex(secret, bodyBytes);
      if (constantTimeHexEqual(sig, expected)) {
        return { ok: true, reason: "bad_signature", eventId };
      }
    }
    return { ok: false, reason: "bad_signature", eventId };
  },
};

export function verifierFor(name: string): ProviderVerifier | null {
  if (name === "stripe") return stripeVerifier;
  if (name === "custom") return customVerifier;
  return null;
}

// ---------------------------------------------------------------------------
// Event normalization (D-M10-3)
// ---------------------------------------------------------------------------

type NormalizedType = "payment_confirmed" | "refund" | "dispute" | "unknown";

interface NormalizedEvent {
  eventId: string;
  type: NormalizedType;
  providerOrderId: string;
  productRef: string | null;
  amountMinor: number | null;
  currency: string | null;
  discordId: string | null;
  email: string | null;
}

const STRIPE_TYPES: Record<string, NormalizedType> = {
  "checkout.session.completed": "payment_confirmed",
  "charge.refunded": "refund",
  "charge.dispute.created": "dispute",
};

const CUSTOM_TYPES: Record<string, NormalizedType> = {
  "payment.confirmed": "payment_confirmed",
  "payment.refunded": "refund",
  "payment.disputed": "dispute",
};

function str(v: unknown): string | null {
  return typeof v === "string" && v.length > 0 && v.length <= 256 ? v : null;
}

function minor(v: unknown): number | null {
  return typeof v === "number" && Number.isInteger(v) && v >= 0 && v <= 1_000_000_000 ? v : null;
}

export function normalizeStripeEvent(body: Record<string, unknown>): NormalizedEvent | null {
  const eventId = str(body.id);
  const eventType = str(body.type);
  if (eventId === null || eventType === null) return null;
  const obj = (body.data as { object?: unknown } | undefined)?.object;
  const o = typeof obj === "object" && obj !== null ? (obj as Record<string, unknown>) : {};
  const metadata = typeof o.metadata === "object" && o.metadata !== null ? (o.metadata as Record<string, unknown>) : {};
  const orderId =
    str(o.payment_intent) ??
    str(o.id) ??
    str(o.charge);
  if (orderId === null) return null;
  return {
    eventId,
    type: STRIPE_TYPES[eventType] ?? "unknown",
    providerOrderId: orderId,
    productRef: str(metadata.product) ?? str(metadata.product_ref) ?? str(o.client_reference_id),
    amountMinor: minor(o.amount_total) ?? minor(o.amount) ?? minor(o.amount_refunded),
    currency: str(o.currency),
    discordId: str(metadata.discord_id),
    email: str(metadata.email) ?? str(o.customer_email),
  };
}

export function normalizeCustomEvent(body: Record<string, unknown>): NormalizedEvent | null {
  const eventId = str(body.id);
  const eventType = str(body.type);
  const orderId = str(body.order_id);
  if (eventId === null || eventType === null || orderId === null) return null;
  return {
    eventId,
    type: CUSTOM_TYPES[eventType] ?? "unknown",
    providerOrderId: orderId,
    productRef: str(body.product_ref),
    amountMinor: minor(body.amount_minor),
    currency: str(body.currency),
    discordId: str(body.discord_id),
    email: str(body.email),
  };
}

// ---------------------------------------------------------------------------
// Rows
// ---------------------------------------------------------------------------

interface OrderRow {
  id: string;
  provider: string;
  provider_order_id: string;
  product_ref: string;
  project_id: string;
  key_id: string | null;
  discord_id: string | null;
  email: string | null;
  amount_minor: number | null;
  currency: string | null;
  status: string;
  created_at: number;
  updated_at: number;
}

interface ProductRow {
  id: string;
  provider: string;
  product_ref: string;
  project_id: string;
  tier: string;
  days: number | null;
  scripts: string;
  refund_blacklists: number;
  active: number;
}

function json(data: unknown, status = 200, extraHeaders: Record<string, string> = {}): Response {
  return new Response(JSON.stringify(data), { status, headers: { "content-type": "application/json", ...extraHeaders } });
}

async function audit(ctx: AppContext, actor: string, action: string, target: string, detail: string): Promise<void> {
  await ctx.db.run(
    "INSERT INTO audit_log (id, actor_id, action, target, detail, created_at) VALUES (?, ?, ?, ?, ?, ?)",
    [randomId(), actor, action, target, detail, Math.floor(ctx.nowSec)],
  );
}

function paymentsConfig(config: ApiConfig): PaymentsConfig {
  return {
    webhookSecrets: config.payments?.webhookSecrets ?? {},
    signatureToleranceSec: config.payments?.signatureToleranceSec ?? DEFAULT_SIG_TOLERANCE_SEC,
    requestsPerIpPerMin: config.payments?.requestsPerIpPerMin ?? 30,
    providerBase: config.payments?.providerBase,
    providerApiKey: config.payments?.providerApiKey,
    fetchImpl: config.payments?.fetchImpl,
  };
}

async function rememberEvent(ctx: AppContext, provider: string, eventId: string, eventType: string, outcome: string, orderId: string | null): Promise<boolean> {
  // Insert-first idempotency gate (D-M10-2). Returns false when the event was
  // already processed. The UNIQUE(provider, event_id) PK is the lock.
  try {
    await ctx.db.run(
      "INSERT INTO payment_events (provider, event_id, event_type, outcome, order_id, created_at) VALUES (?, ?, ?, ?, ?, ?)",
      [provider, eventId, eventType, outcome, orderId, Math.floor(ctx.nowSec)],
    );
    return true;
  } catch {
    return false;
  }
}

async function discordBlacklistHash(pepper: string, discordId: string): Promise<string> {
  return sha256Hex(pepper + "|discord|" + discordId);
}

// ---------------------------------------------------------------------------
// POST /webhooks/payments/:provider — the webhook (doc §17)
// ---------------------------------------------------------------------------

export async function handlePaymentsWebhook(ctx: AppContext, config: ApiConfig, input: RequestInput, providerParam: string): Promise<Response> {
  await ensureSchema(ctx);
  const pay = paymentsConfig(config);
  const provider = providerParam as ProviderName;
  const verifier = verifierFor(provider);
  if (verifier === null || !(PROVIDERS as readonly string[]).includes(provider)) {
    return json({ error: "unknown_provider" }, 404);
  }

  const ipHash = await sha256Hex(config.pepper + "|ip|" + input.ip);
  const rate = await ctx.limiter.hit(`webhook:${provider}:${ipHash}`, pay.requestsPerIpPerMin, 60);
  if (!rate.ok) {
    await recordEvent(ctx, null, "payment_webhook", "rate-limited");
    return json({ error: "rate_limited" }, 429, { "retry-after": String(Math.max(1, rate.retryAfterSec)) });
  }

  const secrets = pay.webhookSecrets[provider] ?? [];
  if (secrets.length === 0) {
    // No secret configured: the provider is disabled rather than trusting
    // unsigned traffic (fail closed).
    return json({ error: "provider_disabled" }, 503);
  }

  const verdict = await verifier.verify(input.headers, input.bodyBytes, Math.floor(ctx.nowSec), secrets, pay.signatureToleranceSec);
  if (!verdict.ok) {
    await recordEvent(ctx, null, "payment_webhook", "bad-signature:" + verdict.reason);
    return json({ error: "invalid_signature" }, 400);
  }

  let body: Record<string, unknown>;
  try {
    const parsed = JSON.parse(new TextDecoder().decode(input.bodyBytes));
    if (typeof parsed !== "object" || parsed === null || Array.isArray(parsed)) throw new Error("not an object");
    body = parsed as Record<string, unknown>;
  } catch {
    await recordEvent(ctx, null, "payment_webhook", "malformed-body");
    return json({ error: "bad_request" }, 400);
  }

  const normalized = provider === "stripe" ? normalizeStripeEvent(body) : normalizeCustomEvent(body);
  if (normalized === null) {
    await recordEvent(ctx, null, "payment_webhook", "unmappable-event");
    return json({ error: "bad_request" }, 400);
  }
  if (verdict.eventId !== null && verdict.eventId !== normalized.eventId) {
    // Signed transport id and payload id disagree — treat as bad signature.
    await recordEvent(ctx, null, "payment_webhook", "event-id-mismatch");
    return json({ error: "invalid_signature" }, 400);
  }

  // Idempotency gate: same (provider, event_id) never processes twice.
  const eventId = normalized.eventId;
  const eventType = provider === "stripe" ? (str(body.type) ?? "unknown") : (str(body.type) ?? "unknown");
  const first = await rememberEvent(ctx, provider, eventId, eventType, "pending", null);
  if (!first) {
    const prior = await ctx.db.first<{ outcome: string; order_id: string | null }>(
      "SELECT outcome, order_id FROM payment_events WHERE provider = ? AND event_id = ?",
      [provider, eventId],
    );
    return json({ ok: true, duplicate: true, outcome: prior?.outcome ?? "unknown" });
  }

  const now = Math.floor(ctx.nowSec);

  if (normalized.type === "unknown") {
    // Unknown types are 200-ignored (D-M10-3): 4xx would trigger provider
    // retry storms for events we simply do not care about.
    await ctx.db.run("UPDATE payment_events SET outcome = 'ignored' WHERE provider = ? AND event_id = ?", [provider, eventId]);
    await recordEvent(ctx, null, "payment_webhook", "ignored-type:" + eventType);
    return json({ ok: true, outcome: "ignored" });
  }

  if (normalized.type === "payment_confirmed") {
    return issueForOrder(ctx, config, provider, normalized, eventId, now);
  }
  return refundOrDispute(ctx, config, provider, normalized, eventId, now);
}

async function issueForOrder(ctx: AppContext, config: ApiConfig, provider: string, ev: NormalizedEvent, eventId: string, now: number): Promise<Response> {
  if (ev.productRef === null) {
    await ctx.db.run("UPDATE payment_events SET outcome = 'ignored' WHERE provider = ? AND event_id = ?", [provider, eventId]);
    await recordEvent(ctx, null, "payment_webhook", "no-product-ref:" + ev.providerOrderId);
    return json({ ok: true, outcome: "ignored", reason: "no_product_ref" });
  }

  const product = await ctx.db.first<ProductRow>(
    "SELECT id, provider, product_ref, project_id, tier, days, scripts, refund_blacklists, active FROM payment_products WHERE provider = ? AND product_ref = ? AND active = 1",
    [provider, ev.productRef],
  );
  if (product === null) {
    await ctx.db.run("UPDATE payment_events SET outcome = 'ignored' WHERE provider = ? AND event_id = ?", [provider, eventId]);
    await recordEvent(ctx, null, "payment_webhook", "no-product-mapping:" + ev.productRef);
    return json({ ok: true, outcome: "ignored", reason: "no_product_mapping" });
  }

  // Defensive: two DIFFERENT events for the same order (providers sometimes
  // resend under new event ids) must not double-issue.
  const existing = await ctx.db.first<{ id: string; key_id: string | null }>(
    "SELECT id, key_id FROM orders WHERE provider = ? AND provider_order_id = ?",
    [provider, ev.providerOrderId],
  );
  if (existing !== null) {
    await ctx.db.run("UPDATE payment_events SET outcome = 'duplicate', order_id = ? WHERE provider = ? AND event_id = ?", [existing.id, provider, eventId]);
    return json({ ok: true, duplicate: true, outcome: "duplicate", order_id: existing.id });
  }

  const generated = generateKey();
  const keyHash = await hashKey(generated.plaintext, config.pepper);
  const keyId = "k" + generated.body.slice(0, 31).toLowerCase();
  const expiresAt = product.days !== null ? now + product.days * 86400 : null;

  let scriptIds: string[] = [];
  try {
    const parsed = JSON.parse(product.scripts);
    if (Array.isArray(parsed)) scriptIds = parsed.filter((s): s is string => typeof s === "string");
  } catch {
    scriptIds = [];
  }
  if (scriptIds.length === 0) {
    // Empty list = all of the project's key-gated scripts (M9 semantics).
    const rows = await ctx.db.all<{ id: string }>(
      "SELECT id FROM scripts WHERE project_id = ? AND keyless = 0",
      [product.project_id],
    );
    scriptIds = rows.map((r) => r.id);
  }

  const orderId = randomId();
  await ctx.db.run(
    "INSERT INTO orders (id, provider, provider_order_id, product_ref, project_id, key_id, discord_id, email, amount_minor, currency, status, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'paid', ?, ?)",
    [orderId, provider, ev.providerOrderId, ev.productRef, product.project_id, keyId, ev.discordId, ev.email, ev.amountMinor, ev.currency, now, now],
  );
  await ctx.db.run(
    "INSERT INTO keys (id, project_id, key_hash, tier, status, discord_id, note, total_executions, created_by, created_at, expires_at) VALUES (?, ?, ?, ?, 'active', ?, ?, 0, ?, ?, ?)",
    [keyId, product.project_id, keyHash, product.tier, ev.discordId, "order " + ev.providerOrderId, "m10:" + provider, now, expiresAt],
  );
  for (const scriptId of scriptIds) {
    await ctx.db.run("INSERT OR IGNORE INTO key_scripts (key_id, script_id) VALUES (?, ?)", [keyId, scriptId]);
  }
  await ctx.db.run("UPDATE payment_events SET outcome = 'issued', order_id = ? WHERE provider = ? AND event_id = ?", [orderId, provider, eventId]);
  await audit(ctx, "m10:" + provider, "payment.issue", keyId, provider + " order " + ev.providerOrderId + " product " + ev.productRef);
  await recordEvent(ctx, keyId, "payment", "issued:" + ev.providerOrderId);

  // Plaintext returned exactly once — the caller (bot DM / email pipeline)
  // delivers it; it is never stored.
  return json({ ok: true, outcome: "issued", order_id: orderId, key: generated.plaintext, expires_at: expiresAt, tier: product.tier });
}

async function refundOrDispute(ctx: AppContext, config: ApiConfig, provider: string, ev: NormalizedEvent, eventId: string, now: number): Promise<Response> {
  const order = await ctx.db.first<OrderRow>(
    "SELECT id, provider, provider_order_id, product_ref, project_id, key_id, discord_id, email, amount_minor, currency, status, created_at, updated_at FROM orders WHERE provider = ? AND provider_order_id = ?",
    [provider, ev.providerOrderId],
  );
  if (order === null) {
    await ctx.db.run("UPDATE payment_events SET outcome = 'ignored' WHERE provider = ? AND event_id = ?", [provider, eventId]);
    await recordEvent(ctx, null, "payment_webhook", (ev.type === "refund" ? "refund" : "dispute") + "-unknown-order:" + ev.providerOrderId);
    return json({ ok: true, outcome: "ignored", reason: "unknown_order" });
  }

  const newStatus = ev.type === "refund" ? "refunded" : "disputed";
  if (order.key_id !== null) {
    await ctx.db.run("UPDATE keys SET status = 'revoked' WHERE id = ?", [order.key_id]);
  }
  await ctx.db.run("UPDATE orders SET status = ?, updated_at = ? WHERE id = ?", [newStatus, now, order.id]);
  await ctx.db.run("UPDATE payment_events SET outcome = ?, order_id = ? WHERE provider = ? AND event_id = ?", [newStatus, order.id, provider, eventId]);

  // Blacklist policy (D-M10-5): refunds blacklist only when the product row
  // says so; disputes (chargebacks are fraud-shaped) always blacklist.
  let blacklisted = false;
  const product = await ctx.db.first<{ refund_blacklists: number }>(
    "SELECT refund_blacklists FROM payment_products WHERE provider = ? AND product_ref = ?",
    [provider, order.product_ref],
  );
  const shouldBlacklist = ev.type === "dispute" || (product?.refund_blacklists ?? 0) === 1;
  if (shouldBlacklist && order.discord_id !== null) {
    const valueHash = await discordBlacklistHash(config.pepper, order.discord_id);
    const existing = await ctx.db.first<{ id: string }>("SELECT id FROM blacklist WHERE kind = 'discord' AND value_hash = ?", [valueHash]);
    if (existing === null) {
      await ctx.db.run(
        "INSERT INTO blacklist (id, kind, value_hash, reason, created_by, created_at) VALUES (?, 'discord', ?, ?, ?, ?)",
        [randomId(), valueHash, ev.type === "dispute" ? "chargeback " + ev.providerOrderId : "refund " + ev.providerOrderId, "m10:" + provider, now],
      );
    }
    blacklisted = true;
  }

  await audit(ctx, "m10:" + provider, "payment." + (ev.type === "refund" ? "refund" : "dispute"), order.key_id ?? order.id, provider + " order " + ev.providerOrderId + (blacklisted ? " +blacklist" : ""));
  await recordEvent(ctx, order.key_id, "payment", newStatus + ":" + ev.providerOrderId);
  return json({ ok: true, outcome: newStatus, order_id: order.id, key_revoked: order.key_id !== null, blacklisted });
}

// ---------------------------------------------------------------------------
// Admin endpoints (dashboard + M8 bot reuse)
// ---------------------------------------------------------------------------

export async function handleAdminListOrders(ctx: AppContext, config: ApiConfig, input: RequestInput): Promise<Response> {
  await ensureSchema(ctx);
  const admin = await authenticate(ctx, config, input);
  if (!admin || (admin.role !== "owner" && admin.role !== "admin" && admin.role !== "reseller")) {
    return json({ error: admin ? "forbidden" : "unauthorized" }, admin ? 403 : 401);
  }
  const qIndex = input.path.indexOf("?");
  const q: Record<string, string> = {};
  if (qIndex >= 0) {
    for (const pair of input.path.slice(qIndex + 1).split("&")) {
      const eq = pair.indexOf("=");
      if (eq > 0) q[decodeURIComponent(pair.slice(0, eq))] = decodeURIComponent(pair.slice(eq + 1));
    }
  }
  const limit = Math.min(Math.max(parseInt(q.limit ?? "50", 10) || 50, 1), 200);
  const where: string[] = [];
  const params: unknown[] = [];
  if (q.provider && /^(stripe|custom)$/.test(q.provider)) {
    where.push("provider = ?");
    params.push(q.provider);
  }
  if (q.status && /^(paid|refunded|disputed)$/.test(q.status)) {
    where.push("status = ?");
    params.push(q.status);
  }
  const whereSql = where.length > 0 ? " WHERE " + where.join(" AND ") : "";
  const rows = await ctx.db.all<OrderRow>(
    `SELECT id, provider, provider_order_id, product_ref, project_id, key_id, discord_id, email, amount_minor, currency, status, created_at, updated_at FROM orders${whereSql} ORDER BY created_at DESC LIMIT ?`,
    [...params, limit],
  );
  const total = await ctx.db.first<{ n: number }>(`SELECT COUNT(*) AS n FROM orders${whereSql}`, params);
  return json({ rows, total: total?.n ?? 0, limit });
}

export async function handleAdminListProducts(ctx: AppContext, config: ApiConfig, input: RequestInput): Promise<Response> {
  await ensureSchema(ctx);
  const admin = await authenticate(ctx, config, input);
  if (!admin || (admin.role !== "owner" && admin.role !== "admin")) {
    return json({ error: admin ? "forbidden" : "unauthorized" }, admin ? 403 : 401);
  }
  const rows = await ctx.db.all<ProductRow & { project_name: string | null }>(
    `SELECT p.id, p.provider, p.product_ref, p.project_id, p.tier, p.days, p.scripts, p.refund_blacklists, p.active, p.created_at, pr.name AS project_name
     FROM payment_products p LEFT JOIN projects pr ON pr.id = p.project_id ORDER BY p.created_at DESC LIMIT 200`,
    [],
  );
  return json({
    rows: rows.map((r) => ({ ...r, active: r.active === 1, refund_blacklists: r.refund_blacklists === 1 })),
  });
}

export async function handleAdminUpsertProduct(ctx: AppContext, config: ApiConfig, input: RequestInput): Promise<Response> {
  await ensureSchema(ctx);
  const admin = await authenticate(ctx, config, input);
  if (!admin || (admin.role !== "owner" && admin.role !== "admin")) {
    return json({ error: admin ? "forbidden" : "unauthorized" }, admin ? 403 : 401);
  }
  let body: Record<string, unknown> | null = null;
  try {
    const parsed = JSON.parse(new TextDecoder().decode(input.bodyBytes));
    if (typeof parsed === "object" && parsed !== null && !Array.isArray(parsed)) body = parsed as Record<string, unknown>;
  } catch {
    body = null;
  }
  if (body === null) return json({ error: "bad_request" }, 400);
  const provider = typeof body.provider === "string" ? body.provider : "";
  const productRef = typeof body.product_ref === "string" ? body.product_ref : "";
  const projectId = typeof body.project_id === "string" ? body.project_id : "";
  const tier = typeof body.tier === "string" ? body.tier : "";
  const days = body.days === null || body.days === undefined ? null : body.days;
  const scripts = Array.isArray(body.scripts) ? body.scripts : [];
  const refundBlacklists = body.refund_blacklists === true || body.refund_blacklists === 1;
  const active = body.active === undefined ? true : body.active === true || body.active === 1;

  if (!(PROVIDERS as readonly string[]).includes(provider)) return json({ error: "bad_request", field: "provider" }, 400);
  if (productRef.length === 0 || productRef.length > 128) return json({ error: "bad_request", field: "product_ref" }, 400);
  if (!/^[0-9a-f]{32}$/.test(projectId)) return json({ error: "bad_request", field: "project_id" }, 400);
  if (!/^(paid|lifetime|reseller)$/.test(tier)) return json({ error: "bad_request", field: "tier" }, 400);
  if (days !== null && (!Number.isInteger(days) || (days as number) < 1 || (days as number) > 3650)) {
    return json({ error: "bad_request", field: "days" }, 400);
  }
  if (tier === "lifetime" && days !== null) return json({ error: "bad_request", field: "days" }, 400);
  if (scripts.length > 50 || scripts.some((s) => typeof s !== "string" || s.length > 64)) {
    return json({ error: "bad_request", field: "scripts" }, 400);
  }
  const project = await ctx.db.first<{ id: string }>("SELECT id FROM projects WHERE id = ?", [projectId]);
  if (project === null) return json({ error: "bad_request", field: "project_id" }, 400);
  for (const s of scripts) {
    if (typeof s !== "string") continue;
    const found = await ctx.db.first<{ id: string }>("SELECT id FROM scripts WHERE id = ? AND project_id = ?", [s, projectId]);
    if (found === null) return json({ error: "bad_request", field: "scripts" }, 400);
  }

  const now = Math.floor(ctx.nowSec);
  const existing = await ctx.db.first<{ id: string }>(
    "SELECT id FROM payment_products WHERE provider = ? AND product_ref = ?",
    [provider, productRef],
  );
  const scriptsJson = JSON.stringify(scripts);
  if (existing !== null) {
    await ctx.db.run(
      "UPDATE payment_products SET project_id = ?, tier = ?, days = ?, scripts = ?, refund_blacklists = ?, active = ? WHERE id = ?",
      [projectId, tier, days, scriptsJson, refundBlacklists ? 1 : 0, active ? 1 : 0, existing.id],
    );
    await audit(ctx, admin.id, "admin.payment.product", existing.id, "update " + provider + "/" + productRef);
    return json({ ok: true, id: existing.id, updated: true });
  }
  const id = randomId();
  await ctx.db.run(
    "INSERT INTO payment_products (id, provider, product_ref, project_id, tier, days, scripts, refund_blacklists, active, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
    [id, provider, productRef, projectId, tier, days, scriptsJson, refundBlacklists ? 1 : 0, active ? 1 : 0, now],
  );
  await audit(ctx, admin.id, "admin.payment.product", id, "create " + provider + "/" + productRef);
  return json({ ok: true, id }, 201);
}

// ---------------------------------------------------------------------------
// POST /admin/payments/reconcile — doc §17 reconciliation job
// ---------------------------------------------------------------------------

export async function handleAdminReconcile(ctx: AppContext, config: ApiConfig, input: RequestInput): Promise<Response> {
  await ensureSchema(ctx);
  const admin = await authenticate(ctx, config, input);
  if (!admin || (admin.role !== "owner" && admin.role !== "admin")) {
    return json({ error: admin ? "forbidden" : "unauthorized" }, admin ? 403 : 401);
  }
  const pay = paymentsConfig(config);

  const paidButBroken = await ctx.db.all<OrderRow>(
    `SELECT o.id, o.provider, o.provider_order_id, o.product_ref, o.project_id, o.key_id, o.discord_id, o.email, o.amount_minor, o.currency, o.status, o.created_at, o.updated_at
     FROM orders o LEFT JOIN keys k ON k.id = o.key_id
     WHERE o.status = 'paid' AND (o.key_id IS NULL OR k.id IS NULL OR k.status = 'revoked')`,
    [],
  );
  const refundedButActive = await ctx.db.all<OrderRow>(
    `SELECT o.id, o.provider, o.provider_order_id, o.product_ref, o.project_id, o.key_id, o.discord_id, o.email, o.amount_minor, o.currency, o.status, o.created_at, o.updated_at
     FROM orders o JOIN keys k ON k.id = o.key_id
     WHERE o.status IN ('refunded', 'disputed') AND k.status = 'active'`,
    [],
  );
  const keysWithoutOrder = await ctx.db.all<{ id: string; tier: string; status: string; created_by: string; created_at: number; expires_at: number | null }>(
    `SELECT k.id, k.tier, k.status, k.created_by, k.created_at, k.expires_at
     FROM keys k LEFT JOIN orders o ON o.key_id = k.id
     WHERE k.created_by LIKE 'm10:%' AND o.id IS NULL`,
    [],
  );

  // Provider-side cross-check (class A): only when a provider API is wired.
  // Without it the report covers local classes B/C honestly.
  let providerOrders: unknown[] | null = null;
  let providerError: string | null = null;
  if (pay.providerBase && pay.providerApiKey && pay.fetchImpl) {
    try {
      const res = await pay.fetchImpl(pay.providerBase + "/v1/orders?limit=100", {
        headers: { authorization: "Bearer " + pay.providerApiKey },
      });
      if (res.ok) {
        const j = (await res.json()) as { data?: unknown[] };
        providerOrders = Array.isArray(j.data) ? j.data : [];
      } else {
        providerError = "provider_http_" + res.status;
      }
    } catch {
      providerError = "provider_unreachable";
    }
  }

  await audit(ctx, admin.id, "admin.payment.reconcile", "payments", `broken=${paidButBroken.length} refundedActive=${refundedButActive.length} orphanKeys=${keysWithoutOrder.length}`);
  return json({
    report: {
      paid_key_missing_or_revoked: paidButBroken,
      refunded_or_disputed_but_active: refundedButActive,
      keys_without_order: keysWithoutOrder,
    },
    counts: {
      paid_key_missing_or_revoked: paidButBroken.length,
      refunded_or_disputed_but_active: refundedButActive.length,
      keys_without_order: keysWithoutOrder.length,
    },
    provider_cross_check: providerOrders === null ? "not-configured" : "fetched",
    provider_order_count: providerOrders?.length ?? 0,
    provider_error: providerError,
    generated_at: Math.floor(ctx.nowSec),
  });
}
