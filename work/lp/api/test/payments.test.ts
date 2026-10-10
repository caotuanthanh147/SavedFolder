import { describe, expect, test } from "bun:test";
import { buildEnv, envelopeOf, makeSignedInput, ADMIN_TOKEN, RESELLER_TOKEN, SCRIPT_ID, PROJECT_ID, PEPPER } from "./helpers";
import { dispatch, buildRoutes } from "../src/router";
import { utf8, hmacSha256 } from "../src/crypto";
import { RequestInput } from "../src/flow";
import { sha256Hex } from "../src/crypto";

// Module M10 tests: doc.md §17 rows are the oracle — every clause maps to at
// least one test. "Webhook verifies the provider signature and idempotency
// key" → signature vectors + duplicate-event gate. "On confirmed payment:
// create key, assign scripts, deliver..., store the order reference" → the
// issue path (delivery itself is M8/M12 territory; the plaintext-once
// response is the handoff). "Refunds and chargebacks revoke the key and
// optionally blacklist" → refund/dispute matrices. "A reconciliation job
// compares provider orders to issued keys" → the reconcile report.

const CUSTOM_SECRET = "custom-webhook-secret-0123456789";
const STRIPE_SECRET = "whsec_stripe_primary_0123456789";
const STRIPE_SECRET_2 = "whsec_stripe_rotation_9876543210";

interface TestEnvPlus extends Awaited<ReturnType<typeof buildEnv>> {}

async function buildPayEnv(opts: { custom?: string[]; stripe?: string[]; ratePerMin?: number } = {}): Promise<TestEnvPlus> {
  const env = await buildEnv();
  env.config.payments = {
    webhookSecrets: {
      custom: opts.custom ?? [CUSTOM_SECRET],
      stripe: opts.stripe ?? [STRIPE_SECRET, STRIPE_SECRET_2],
    },
    signatureToleranceSec: 300,
    requestsPerIpPerMin: opts.ratePerMin ?? 1000,
  };
  return env;
}

async function hmacHexOf(secret: string, payload: Uint8Array): Promise<string> {
  const mac = await hmacSha256(utf8(secret), payload);
  return Array.from(mac, (b) => b.toString(16).padStart(2, "0")).join("");
}

function webhookInput(body: unknown, headers: Record<string, string>, ip = "198.51.100.7"): RequestInput {
  const bodyBytes = utf8(JSON.stringify(body));
  return { method: "POST", path: "/webhooks/payments/custom", headers, bodyBytes, ip, colo: "TST" };
}

function customEvent(id: string, type: string, over: Record<string, unknown> = {}): Record<string, unknown> {
  return { id, type, order_id: "ord_" + id, product_ref: "prod_demo_30d", amount_minor: 999, currency: "usd", discord_id: "998877", email: "buyer@example.test", ...over };
}

async function signedCustom(env: TestEnvPlus, body: Record<string, unknown>, secret = CUSTOM_SECRET, ip = "198.51.100.7"): Promise<Response> {
  const bodyBytes = utf8(JSON.stringify(body));
  const sig = await hmacHexOf(secret, bodyBytes);
  const eventId = typeof body.id === "string" ? body.id : "evt_missing";
  return dispatch(buildRoutes(), env.ctx, env.config, webhookInput(body, { "X-Event-Id": eventId, "X-Signature": sig }, ip));
}

async function signedStripe(env: TestEnvPlus, body: Record<string, unknown>, opts: { secret?: string; tsDelta?: number } = {}): Promise<Response> {
  const bodyBytes = utf8(JSON.stringify(body));
  const t = Math.floor(Date.now() / 1000) + (opts.tsDelta ?? 0);
  const v1 = await hmacHexOf(opts.secret ?? STRIPE_SECRET, new Uint8Array([...utf8(`${t}.`), ...bodyBytes]));
  const input: RequestInput = {
    method: "POST",
    path: "/webhooks/payments/stripe",
    headers: { "Stripe-Signature": `t=${t},v1=${v1}` },
    bodyBytes,
    ip: "198.51.100.8",
    colo: "TST",
  };
  return dispatch(buildRoutes(), env.ctx, env.config, input);
}

function stripeCheckoutEvent(id: string, over: Record<string, unknown> = {}): Record<string, unknown> {
  return {
    id,
    type: "checkout.session.completed",
    data: { object: { id: "cs_" + id, payment_intent: "pi_" + id, amount_total: 999, currency: "usd", metadata: { product: "prod_demo_30d", discord_id: "11223" } } },
    ...over,
  };
}

async function seedProduct(env: TestEnvPlus, over: Record<string, unknown> = {}): Promise<void> {
  const body = {
    provider: "custom",
    product_ref: "prod_demo_30d",
    project_id: PROJECT_ID,
    tier: "paid",
    days: 30,
    scripts: [],
    ...over,
  };
  const input = await makeSignedInput("POST", "/admin/payments/products", body, { headers: { authorization: `Bearer ${ADMIN_TOKEN}` } });
  const res = await dispatch(buildRoutes(), env.ctx, env.config, input);
  expect(res.status).toBeLessThan(300);
}

async function countKeys(env: TestEnvPlus, createdBy: string): Promise<number> {
  const row = await env.ctx.db.first<{ n: number }>("SELECT COUNT(*) AS n FROM keys WHERE created_by = ?", [createdBy]);
  return row?.n ?? 0;
}

describe("M10 webhook signature verification (doc §17 row 1, D-M10-1)", () => {
  test("custom provider: valid HMAC signature is accepted", async () => {
    const env = await buildPayEnv();
    await seedProduct(env);
    const res = await signedCustom(env, customEvent("evt_aaaaaaaa1", "payment.confirmed"));
    expect(res.status).toBe(200);
    const j = (await res.json()) as { ok: boolean; outcome: string; key: string };
    expect(j.outcome).toBe("issued");
    expect(j.key).toMatch(/^YURI-/);
  });

  test("custom provider: bad signature → 400, nothing processed", async () => {
    const env = await buildPayEnv();
    await seedProduct(env);
    const body = customEvent("evt_bbbbbbbb2", "payment.confirmed");
    const bodyBytes = utf8(JSON.stringify(body));
    const sig = await hmacHexOf("wrong-secret", bodyBytes);
    const res = await dispatch(buildRoutes(), env.ctx, env.config, webhookInput(body, { "X-Event-Id": "evt_bbbbbbbb2", "X-Signature": sig }));
    expect(res.status).toBe(400);
    expect(((await res.json()) as { error: string }).error).toBe("invalid_signature");
    expect(await countKeys(env, "m10:custom")).toBe(0);
  });

  test("stripe scheme: valid t=/v1= HMAC over `${t}.${body}` is accepted", async () => {
    const env = await buildPayEnv();
    await seedProduct(env, { provider: "stripe" });
    const res = await signedStripe(env, stripeCheckoutEvent("evt_cccccccc3"));
    expect(res.status).toBe(200);
    const j = (await res.json()) as { outcome: string; key: string };
    expect(j.outcome).toBe("issued");
    expect(j.key).toMatch(/^YURI-/);
  });

  test("stripe scheme: rotation window — second configured secret also validates", async () => {
    const env = await buildPayEnv();
    await seedProduct(env, { provider: "stripe" });
    const res = await signedStripe(env, stripeCheckoutEvent("evt_dddddddd4"), { secret: STRIPE_SECRET_2 });
    expect(res.status).toBe(200);
    expect(((await res.json()) as { outcome: string }).outcome).toBe("issued");
  });

  test("stripe scheme: stale timestamp outside tolerance → 400", async () => {
    const env = await buildPayEnv();
    await seedProduct(env, { provider: "stripe" });
    const res = await signedStripe(env, stripeCheckoutEvent("evt_eeeeeeee5"), { tsDelta: -3600 });
    expect(res.status).toBe(400);
    expect(((await res.json()) as { error: string }).error).toBe("invalid_signature");
  });

  test("stripe scheme: tampered body under valid header → 400 (raw-bytes binding)", async () => {
    const env = await buildPayEnv();
    await seedProduct(env, { provider: "stripe" });
    const bodyBytes = utf8(JSON.stringify(stripeCheckoutEvent("evt_ffffff6")));
    const t = Math.floor(Date.now() / 1000);
    const v1 = await hmacHexOf(STRIPE_SECRET, new Uint8Array([...utf8(`${t}.`), ...bodyBytes]));
    const input: RequestInput = {
      method: "POST",
      path: "/webhooks/payments/stripe",
      headers: { "Stripe-Signature": `t=${t},v1=${v1}` },
      bodyBytes: utf8(JSON.stringify({ ...stripeCheckoutEvent("evt_ffffff6"), type: "charge.dispute.created" })),
      ip: "198.51.100.8",
      colo: "TST",
    };
    const res = await dispatch(buildRoutes(), env.ctx, env.config, input);
    expect(res.status).toBe(400);
  });

  test("custom: header event id must match payload id (transport/payload split)", async () => {
    const env = await buildPayEnv();
    await seedProduct(env);
    const body = customEvent("evt_11111111", "payment.confirmed");
    const bodyBytes = utf8(JSON.stringify(body));
    const sig = await hmacHexOf(CUSTOM_SECRET, bodyBytes);
    const res = await dispatch(buildRoutes(), env.ctx, env.config, webhookInput(body, { "X-Event-Id": "evt_different_id", "X-Signature": sig }));
    expect(res.status).toBe(400);
    expect(((await res.json()) as { error: string }).error).toBe("invalid_signature");
  });

  test("no secret configured → 503 provider_disabled (fail closed, not unsigned trust)", async () => {
    const env = await buildPayEnv({ custom: [] });
    await seedProduct(env);
    const res = await signedCustom(env, customEvent("evt_22222222", "payment.confirmed"));
    expect(res.status).toBe(503);
  });

  test("unknown provider name → 404", async () => {
    const env = await buildPayEnv();
    const bodyBytes = utf8("{}");
    const input: RequestInput = { method: "POST", path: "/webhooks/payments/paypal", headers: {}, bodyBytes, ip: "198.51.100.9", colo: "TST" };
    const res = await dispatch(buildRoutes(), env.ctx, env.config, input);
    expect(res.status).toBe(404);
  });

  test("malformed JSON body → 400 + event recorded", async () => {
    const env = await buildPayEnv();
    const sig = await hmacHexOf(CUSTOM_SECRET, utf8("not json{"));
    const input: RequestInput = { method: "POST", path: "/webhooks/payments/custom", headers: { "X-Event-Id": "evt_malformed1", "X-Signature": sig }, bodyBytes: utf8("not json{"), ip: "198.51.100.7", colo: "TST" };
    const res = await dispatch(buildRoutes(), env.ctx, env.config, input);
    expect(res.status).toBe(400);
    const ev = await env.ctx.db.first<{ detail: string }>("SELECT detail FROM events WHERE type = 'payment_webhook' AND detail = 'malformed-body'", []);
    expect(ev).not.toBeNull();
  });

  test("per-IP webhook rate limit → 429", async () => {
    const env = await buildPayEnv({ ratePerMin: 2 });
    for (let i = 0; i < 2; i++) {
      const res = await signedCustom(env, customEvent("evt_rate_" + i, "payment.confirmed", { product_ref: "unmapped" }), CUSTOM_SECRET, "203.0.113.99");
      expect(res.status).toBe(200);
    }
    const third = await signedCustom(env, customEvent("evt_rate_3", "payment.confirmed", { product_ref: "unmapped" }), CUSTOM_SECRET, "203.0.113.99");
    expect(third.status).toBe(429);
  });
});

describe("M10 idempotency (doc §17 row 1, D-M10-2)", () => {
  test("same event id delivered twice → duplicate outcome, exactly one key", async () => {
    const env = await buildPayEnv();
    await seedProduct(env);
    const first = await signedCustom(env, customEvent("evt_dup000001", "payment.confirmed"));
    const second = await signedCustom(env, customEvent("evt_dup000001", "payment.confirmed"));
    expect(((await first.json()) as { outcome: string }).outcome).toBe("issued");
    const j = (await second.json()) as { duplicate: boolean; outcome: string };
    expect(j.duplicate).toBe(true);
    // the stored outcome of the FIRST processing is echoed back — the key
    // is not re-issued (count stays 1 below)
    expect(j.outcome).toBe("issued");
    expect(await countKeys(env, "m10:custom")).toBe(1);
  });

  test("same order under a NEW event id (provider resend) → duplicate, still one key", async () => {
    const env = await buildPayEnv();
    await seedProduct(env);
    await signedCustom(env, customEvent("evt_resend001", "payment.confirmed"));
    const again = await signedCustom(env, customEvent("evt_resend002", "payment.confirmed", { order_id: "ord_evt_resend001" }));
    const j = (await again.json()) as { duplicate: boolean };
    expect(j.duplicate).toBe(true);
    expect(await countKeys(env, "m10:custom")).toBe(1);
  });
});

describe("M10 confirmed payment → key + scripts + order reference (doc §17 row 2, D-M10-4)", () => {
  test("issues a key with product tier/days, entitlements, order row, audit entry; key validates through REAL check_key", async () => {
    const env = await buildPayEnv();
    await seedProduct(env);
    const res = await signedCustom(env, customEvent("evt_issue0001", "payment.confirmed"));
    const j = (await res.json()) as { key: string; order_id: string; expires_at: number; tier: string };
    expect(j.tier).toBe("paid");
    expect(j.expires_at).toBeGreaterThan(Math.floor(Date.now() / 1000) + 29 * 86400);

    const order = await env.ctx.db.first<{ status: string; key_id: string; amount_minor: number; currency: string; discord_id: string; email: string; product_ref: string; provider_order_id: string }>(
      "SELECT status, key_id, amount_minor, currency, discord_id, email, product_ref, provider_order_id FROM orders WHERE id = ?",
      [j.order_id],
    );
    expect(order?.status).toBe("paid");
    expect(order?.amount_minor).toBe(999);
    expect(order?.currency).toBe("usd");
    expect(order?.discord_id).toBe("998877");
    expect(order?.email).toBe("buyer@example.test");
    expect(order?.provider_order_id).toBe("ord_evt_issue0001");

    const key = await env.ctx.db.first<{ id: string; tier: string; status: string; created_by: string; discord_id: string }>(
      "SELECT id, tier, status, created_by, discord_id FROM keys WHERE id = ?",
      [order!.key_id],
    );
    expect(key?.tier).toBe("paid");
    expect(key?.status).toBe("active");
    expect(key?.created_by).toBe("m10:custom");
    expect(key?.discord_id).toBe("998877");

    const ks = await env.ctx.db.all<{ script_id: string }>("SELECT script_id FROM key_scripts WHERE key_id = ?", [order!.key_id]);
    expect(ks.map((r) => r.script_id)).toContain(SCRIPT_ID);

    const audit = await env.ctx.db.first<{ action: string }>("SELECT action FROM audit_log WHERE action = 'payment.issue' AND target = ?", [order!.key_id]);
    expect(audit).not.toBeNull();

    // cross-module: the paid key validates through the REAL M1 handler
    const check = await dispatch(
      buildRoutes(),
      env.ctx,
      env.config,
      await makeSignedInput("POST", "/check_key", { key: j.key, script_id: SCRIPT_ID, lv: "1.0.0" }),
    );
    expect((await envelopeOf(check)).code).toBe("KEY_VALID");
  });

  test("lifetime product (days null) → key without expiry", async () => {
    const env = await buildPayEnv();
    await seedProduct(env, { tier: "lifetime", days: null, product_ref: "prod_life" });
    const res = await signedCustom(env, customEvent("evt_life00001", "payment.confirmed", { product_ref: "prod_life" }));
    const j = (await res.json()) as { expires_at: number | null };
    expect(j.expires_at).toBeNull();
  });

  test("unknown product mapping → 200 ignored, no key, no order", async () => {
    const env = await buildPayEnv();
    await seedProduct(env);
    const res = await signedCustom(env, customEvent("evt_unmapped1", "payment.confirmed", { product_ref: "prod_nonexistent" }));
    const j = (await res.json()) as { outcome: string; reason: string };
    expect(j.outcome).toBe("ignored");
    expect(j.reason).toBe("no_product_mapping");
    expect(await countKeys(env, "m10:custom")).toBe(0);
  });

  test("unknown event type → 200 ignored (no retry storm)", async () => {
    const env = await buildPayEnv();
    await seedProduct(env);
    const res = await signedCustom(env, customEvent("evt_unknown1", "customer.updated"));
    const j = (await res.json()) as { outcome: string };
    expect(j.outcome).toBe("ignored");
  });
});

describe("M10 refunds and chargebacks (doc §17 row 3, D-M10-5)", () => {
  test("refund revokes the key; no blacklist when product refund_blacklists = 0", async () => {
    const env = await buildPayEnv();
    await seedProduct(env, { refund_blacklists: false });
    await signedCustom(env, customEvent("evt_refund001", "payment.confirmed"));
    const res = await signedCustom(env, customEvent("evt_refund002", "payment.refunded", { order_id: "ord_evt_refund001" }));
    const j = (await res.json()) as { outcome: string; key_revoked: boolean; blacklisted: boolean };
    expect(j.outcome).toBe("refunded");
    expect(j.key_revoked).toBe(true);
    expect(j.blacklisted).toBe(false);
    const order = await env.ctx.db.first<{ status: string; key_id: string }>("SELECT status, key_id FROM orders WHERE provider_order_id = ?", ["ord_evt_refund001"]);
    expect(order?.status).toBe("refunded");
    const key = await env.ctx.db.first<{ status: string }>("SELECT status FROM keys WHERE id = ?", [order!.key_id]);
    expect(key?.status).toBe("revoked");
    const bl = await env.ctx.db.first<{ n: number }>("SELECT COUNT(*) AS n FROM blacklist WHERE kind = 'discord'", []);
    expect(bl?.n).toBe(0);
  });

  test("refund with refund_blacklists = 1 → discord id blacklisted with the platform hash formula", async () => {
    const env = await buildPayEnv();
    await seedProduct(env, { refund_blacklists: true });
    await signedCustom(env, customEvent("evt_refund003", "payment.confirmed"));
    await signedCustom(env, customEvent("evt_refund004", "payment.refunded", { order_id: "ord_evt_refund003" }));
    const expectedHash = await sha256Hex(PEPPER + "|discord|998877");
    const bl = await env.ctx.db.first<{ id: string }>("SELECT id FROM blacklist WHERE kind = 'discord' AND value_hash = ?", [expectedHash]);
    expect(bl).not.toBeNull();
  });

  test("dispute (chargeback) always blacklists + revokes", async () => {
    const env = await buildPayEnv();
    await seedProduct(env, { refund_blacklists: false });
    await signedCustom(env, customEvent("evt_disput001", "payment.confirmed"));
    const res = await signedCustom(env, customEvent("evt_disput002", "payment.disputed", { order_id: "ord_evt_disput001" }));
    const j = (await res.json()) as { outcome: string; blacklisted: boolean };
    expect(j.outcome).toBe("disputed");
    expect(j.blacklisted).toBe(true);
    const order = await env.ctx.db.first<{ status: string }>("SELECT status FROM orders WHERE provider_order_id = ?", ["ord_evt_disput001"]);
    expect(order?.status).toBe("disputed");
  });

  test("refund for unknown order → ignored", async () => {
    const env = await buildPayEnv();
    await seedProduct(env);
    const res = await signedCustom(env, customEvent("evt_refund999", "payment.refunded", { order_id: "ord_never_existed" }));
    const j = (await res.json()) as { outcome: string; reason: string };
    expect(j.outcome).toBe("ignored");
    expect(j.reason).toBe("unknown_order");
  });

  test("stripe charge.refunded event maps to the refund path", async () => {
    const env = await buildPayEnv();
    await seedProduct(env, { provider: "stripe" });
    const checkout = await signedStripe(env, stripeCheckoutEvent("evt_stripe01"));
    const issued = (await checkout.json()) as { key: string };
    expect(issued.key).toMatch(/^YURI-/);
    const refund = await signedStripe(env, {
      id: "evt_stripe02",
      type: "charge.refunded",
      data: { object: { id: "ch_evt_stripe01", payment_intent: "pi_evt_stripe01", amount_refunded: 999, currency: "usd", metadata: { product: "prod_demo_30d" } } },
    });
    const j = (await refund.json()) as { outcome: string; key_revoked: boolean };
    expect(j.outcome).toBe("refunded");
    expect(j.key_revoked).toBe(true);
  });
});

describe("M11 dashboard endpoints: users view + reseller minting (doc §16)", () => {
  test("/admin/users aggregates identities by discord then roblox with key stats", async () => {
    const env = await buildPayEnv();
    await env.createKey({ note: "u1", tier: "paid", days: 30 });
    // attach discord + roblox identities via direct rows
    await env.ctx.db.run("UPDATE keys SET discord_id = '4242', last_used_at = 100 WHERE note = 'u1'", []);
    await env.createKey({ note: "u2", tier: "paid", days: 30 });
    await env.createKey({ note: "u2b", tier: "paid", days: 30 });
    await env.ctx.db.run("UPDATE keys SET roblox_user_id = 777 WHERE note IN ('u2','u2b')", []);
    const res = await dispatch(buildRoutes(), env.ctx, env.config, await makeSignedInput("GET", "/admin/users", null, { headers: { authorization: `Bearer ${ADMIN_TOKEN}` } }));
    expect(res.status).toBe(200);
    const j = (await res.json()) as { rows: { identity: string; kind: string; key_count: number; active_keys: number }[] };
    const ids = j.rows.map((r) => r.identity);
    expect(ids).toContain("4242");
    expect(ids).toContain("777");
    const roblox = j.rows.find((r) => r.identity === "777");
    expect(roblox?.kind).toBe("roblox");
    expect(roblox?.key_count).toBe(2);
    expect(roblox?.active_keys).toBe(2);
    const search = await dispatch(buildRoutes(), env.ctx, env.config, await makeSignedInput("GET", "/admin/users?q=424", null, { headers: { authorization: `Bearer ${ADMIN_TOKEN}` } }));
    const sj = (await search.json()) as { rows: { identity: string }[] };
    expect(sj.rows).toHaveLength(1);
    expect(sj.rows[0].identity).toBe("4242");
    const forbidden = await dispatch(buildRoutes(), env.ctx, env.config, await makeSignedInput("GET", "/admin/users", null, { headers: { authorization: `Bearer ${RESELLER_TOKEN}` } }));
    expect(forbidden.status).toBe(403);
  });

  test("/admin/resellers mints a usable reseller token (owner only, plaintext once, quota stored)", async () => {
    const env = await buildPayEnv();
    const notOwner = await dispatch(buildRoutes(), env.ctx, env.config, await makeSignedInput("POST", "/admin/resellers", { quota_keys: 10 }, { headers: { authorization: `Bearer ${RESELLER_TOKEN}` } }));
    expect(notOwner.status).toBe(403);
    const bad = await dispatch(buildRoutes(), env.ctx, env.config, await makeSignedInput("POST", "/admin/resellers", { discord_id: "abc" }, { headers: { authorization: `Bearer ${ADMIN_TOKEN}` } }));
    expect(bad.status).toBe(400);
    const res = await dispatch(buildRoutes(), env.ctx, env.config, await makeSignedInput("POST", "/admin/resellers", { discord_id: "556677", quota_keys: 25 }, { headers: { authorization: `Bearer ${ADMIN_TOKEN}` } }));
    expect(res.status).toBe(201);
    const j = (await res.json()) as { id: string; token: string };
    expect(j.token).toMatch(/^adm_[0-9a-f]{32}\.[A-Za-z0-9_-]{43}$/);
    // the minted token authenticates and is a reseller (own-keys-only list)
    const use = await dispatch(buildRoutes(), env.ctx, env.config, await makeSignedInput("GET", "/admin/keys", null, { headers: { authorization: `Bearer ${j.token}` } }));
    expect(use.status).toBe(200);
    const uj = (await use.json()) as { total: number };
    expect(uj.total).toBe(0); // reseller sees only own keys
    const row = await env.ctx.db.first<{ role: string; quota_keys: number | null; discord_id: string }>(
      "SELECT role, quota_keys, discord_id FROM admins WHERE id = ?",
      [j.id],
    );
    expect(row?.role).toBe("reseller");
    expect(row?.quota_keys).toBe(25);
    expect(row?.discord_id).toBe("556677");
    const audit = await env.ctx.db.first<{ action: string }>("SELECT action FROM audit_log WHERE action = 'admin.reseller.create' AND target = ?", [j.id]);
    expect(audit).not.toBeNull();
  });
});

describe("M10 admin endpoints + reconciliation (doc §17 row 4, D-M10-7)", () => {
  test("orders list: owner sees rows; reseller token allowed; filters work", async () => {
    const env = await buildPayEnv();
    await seedProduct(env);
    await signedCustom(env, customEvent("evt_list00001", "payment.confirmed"));
    await signedCustom(env, customEvent("evt_list00002", "payment.confirmed", { product_ref: "prod_life" }));
    // no product for prod_life seeded second... seed it first
    // (second event above is ignored — re-check with proper product below)
    const owner = await dispatch(buildRoutes(), env.ctx, env.config, await makeSignedInput("GET", "/admin/payments/orders", null, { headers: { authorization: `Bearer ${ADMIN_TOKEN}` } }));
    expect(owner.status).toBe(200);
    const j = (await owner.json()) as { rows: unknown[]; total: number };
    expect(j.total).toBe(1);
    const reseller = await dispatch(buildRoutes(), env.ctx, env.config, await makeSignedInput("GET", "/admin/payments/orders", null, { headers: { authorization: `Bearer ${RESELLER_TOKEN}` } }));
    expect(reseller.status).toBe(200);
    const filtered = await dispatch(buildRoutes(), env.ctx, env.config, await makeSignedInput("GET", "/admin/payments/orders?status=refunded", null, { headers: { authorization: `Bearer ${ADMIN_TOKEN}` } }));
    const fj = (await filtered.json()) as { total: number };
    expect(fj.total).toBe(0);
  });

  test("product upsert validation: bad tier, bad project, lifetime+days rejected", async () => {
    const env = await buildPayEnv();
    const badTier = await dispatch(buildRoutes(), env.ctx, env.config, await makeSignedInput("POST", "/admin/payments/products", { provider: "custom", product_ref: "x", project_id: PROJECT_ID, tier: "bronze", days: 30 }, { headers: { authorization: `Bearer ${ADMIN_TOKEN}` } }));
    expect(badTier.status).toBe(400);
    const badProject = await dispatch(buildRoutes(), env.ctx, env.config, await makeSignedInput("POST", "/admin/payments/products", { provider: "custom", product_ref: "x", project_id: "f".repeat(32), tier: "paid", days: 30 }, { headers: { authorization: `Bearer ${ADMIN_TOKEN}` } }));
    expect(badProject.status).toBe(400);
    const lifeDays = await dispatch(buildRoutes(), env.ctx, env.config, await makeSignedInput("POST", "/admin/payments/products", { provider: "custom", product_ref: "x", project_id: PROJECT_ID, tier: "lifetime", days: 30 }, { headers: { authorization: `Bearer ${ADMIN_TOKEN}` } }));
    expect(lifeDays.status).toBe(400);
    const noAuth = await dispatch(buildRoutes(), env.ctx, env.config, await makeSignedInput("GET", "/admin/payments/products", null));
    expect(noAuth.status).toBe(401);
  });

  test("product upsert: update path reuses the same row", async () => {
    const env = await buildPayEnv();
    await seedProduct(env);
    const before = await dispatch(buildRoutes(), env.ctx, env.config, await makeSignedInput("GET", "/admin/payments/products", null, { headers: { authorization: `Bearer ${ADMIN_TOKEN}` } }));
    const bj = (await before.json()) as { rows: { id: string; days: number | null }[] };
    expect(bj.rows).toHaveLength(1);
    await seedProduct(env, { days: 60 });
    const after = await dispatch(buildRoutes(), env.ctx, env.config, await makeSignedInput("GET", "/admin/payments/products", null, { headers: { authorization: `Bearer ${ADMIN_TOKEN}` } }));
    const aj = (await after.json()) as { rows: { id: string; days: number | null }[] };
    expect(aj.rows).toHaveLength(1);
    expect(aj.rows[0].days).toBe(60);
  });

  test("reconcile report flags refunded-but-active, paid-key-missing, and orphan m10 keys", async () => {
    const env = await buildPayEnv();
    await seedProduct(env);
    // refunded order whose key is somehow still active (simulate drift)
    await signedCustom(env, customEvent("evt_rec000001", "payment.confirmed"));
    const order = await env.ctx.db.first<{ id: string; key_id: string }>("SELECT id, key_id FROM orders WHERE provider_order_id = ?", ["ord_evt_rec000001"]);
    await env.ctx.db.run("UPDATE orders SET status = 'refunded' WHERE id = ?", [order!.id]); // drift: key left active
    // orphan m10 key without an order row
    await env.ctx.db.run(
      "INSERT INTO keys (id, project_id, key_hash, tier, status, note, total_executions, created_by, created_at, expires_at) VALUES ('k_orphan_m10', ?, 'x', 'paid', 'active', 'orphan', 0, 'm10:custom', 0, NULL)",
      [PROJECT_ID],
    );
    const res = await dispatch(buildRoutes(), env.ctx, env.config, await makeSignedInput("POST", "/admin/payments/reconcile", {}, { headers: { authorization: `Bearer ${ADMIN_TOKEN}` } }));
    expect(res.status).toBe(200);
    const j = (await res.json()) as {
      counts: { paid_key_missing_or_revoked: number; refunded_or_disputed_but_active: number; keys_without_order: number };
      provider_cross_check: string;
    };
    expect(j.counts.refunded_or_disputed_but_active).toBe(1);
    expect(j.counts.keys_without_order).toBe(1);
    expect(j.counts.paid_key_missing_or_revoked).toBe(0);
    expect(j.provider_cross_check).toBe("not-configured");
    const audit = await env.ctx.db.first<{ action: string }>("SELECT action FROM audit_log WHERE action = 'admin.payment.reconcile'", []);
    expect(audit).not.toBeNull();
  });

  test("reconcile provider fetch path reports fetched when provider is configured", async () => {
    const env = await buildPayEnv();
    env.config.payments!.providerBase = "https://provider.example.test";
    env.config.payments!.providerApiKey = "sk_test_x";
    env.config.payments!.fetchImpl = (async () => new Response(JSON.stringify({ data: [{ id: "ord_ext_1" }] }), { status: 200 })) as unknown as typeof fetch;
    const res = await dispatch(buildRoutes(), env.ctx, env.config, await makeSignedInput("POST", "/admin/payments/reconcile", {}, { headers: { authorization: `Bearer ${ADMIN_TOKEN}` } }));
    const j = (await res.json()) as { provider_cross_check: string; provider_order_count: number };
    expect(j.provider_cross_check).toBe("fetched");
    expect(j.provider_order_count).toBe(1);
  });

  test("reconcile provider unreachable is reported, not thrown", async () => {
    const env = await buildPayEnv();
    env.config.payments!.providerBase = "https://provider.example.test";
    env.config.payments!.providerApiKey = "sk_test_x";
    env.config.payments!.fetchImpl = (async () => {
      throw new Error("offline");
    }) as unknown as typeof fetch;
    const res = await dispatch(buildRoutes(), env.ctx, env.config, await makeSignedInput("POST", "/admin/payments/reconcile", {}, { headers: { authorization: `Bearer ${ADMIN_TOKEN}` } }));
    const j = (await res.json()) as { provider_error: string | null };
    expect(j.provider_error).toBe("provider_unreachable");
  });
});
