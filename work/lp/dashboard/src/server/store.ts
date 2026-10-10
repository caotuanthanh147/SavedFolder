// Module M11 dashboard server harness: runs the REAL api/ router (module M1
// + M9 code) in-process over SQLite, with a persisted dev keystore and a
// deterministic demo seed. Every dashboard action goes through the actual
// admin API handlers — mutations produce real audit_log rows and events.
//
// Production deploy (per doc.md §4): the dashboard talks to the Workers
// deployment over HTTPS instead (DASH_API_BASE env switches the gateway);
// this in-process mode is the local/dev harness.

import { mkdirSync, readFileSync, writeFileSync, existsSync } from "node:fs";
import { join } from "node:path";
import { b64urlDecode, b64urlEncode } from "@api/src/contracts";
import { generateSigningKeys, makeSigner, randomBytes, sha256Hex, utf8 } from "@api/src/crypto";
import { refSealKey } from "@api/src/auth";
import { SqliteAdapter, DOC_SCHEMA_SQL } from "@api/src/db";
import { ApiConfig, AppContext } from "@api/src/flow";
import { MemoryBlobStore } from "@api/src/blobs";
import { MemoryNonceStore, MemoryRateLimiter } from "@api/src/state";
import { openRawSqlite, RawSqlite } from "./sqlite";
import { generateKey, hashKey } from "@api/src/keys";
import { PAYMENTS_SCHEMA_SQL } from "@api/src/payments";

export const DEMO_PROJECT_ID = "11111111111111111111111111111111";
export const DEMO_SCRIPT_ID = "22222222222222222222222222222222";
export const DEMO_GAME_ID = 40961328;
// Dev-only custom-provider webhook secret (M10 simulator). Never used in
// production mode: DASH_DEV_MODE=false disables the simulator route.
export const DEV_WEBHOOK_SECRET = "dev-payments-webhook-secret-0123456789";

export interface DevStore {
  raw: RawSqlite;
  ctx: AppContext;
  config: ApiConfig;
  devAdminToken: string;
  devAdminId: string;
  dashboardSessionSecret: Uint8Array;
  blobStore: MemoryBlobStore;
  discordConfigured: boolean;
}

interface KeystoreFile {
  signingPrivateKeyB64url: string;
  sessionSealSecret: string;
  freeSecretB64url: string;
  dashboardSessionSecretB64url: string;
  devAdminId: string;
  devAdminSecretB64url: string;
}

const DB_DIR = join(process.cwd(), "db");
const DB_PATH = join(DB_DIR, "dashboard.db");
const KEYSTORE_PATH = join(DB_DIR, "dashboard-keystore.json");
const PEPPER = "dev-pepper-yuri";
const PROOF_KEY = utf8("dev-proof-key-0123456789abcdef0123456789abcdef");

async function loadOrCreateKeystore(): Promise<KeystoreFile> {
  if (existsSync(KEYSTORE_PATH)) {
    return JSON.parse(readFileSync(KEYSTORE_PATH, "utf8")) as KeystoreFile;
  }
  const pair = await generateSigningKeys();
  const store: KeystoreFile = {
    signingPrivateKeyB64url: b64urlEncode(pair.privateKeyPkcs8),
    sessionSealSecret: "dev-session-seal-secret-0123456789",
    freeSecretB64url: b64urlEncode(utf8("dev-free-secret-0123456789abcdef0123456789")),
    dashboardSessionSecretB64url: b64urlEncode(randomBytes(32)),
    devAdminId: "44444444444444444444444444444441",
    devAdminSecretB64url: b64urlEncode(randomBytes(32)),
  };
  writeFileSync(KEYSTORE_PATH, JSON.stringify(store, null, 2) + "\n");
  return store;
}

async function seedDemoData(raw: RawSqlite, devAdminToken: { id: string; secretHash: string }, now: number): Promise<void> {
  const existing = raw.query("SELECT COUNT(*) AS n FROM projects", []) as { n: number }[];
  if ((existing[0]?.n ?? 0) > 0) {
    // re-land the dev admin (keystore may have rotated) even on re-runs
    raw.run("UPDATE admins SET api_token_hash = ?, role = 'owner' WHERE id = ?", [devAdminToken.secretHash, devAdminToken.id]);
    if ((raw.query("SELECT COUNT(*) AS n FROM admins WHERE id = ?", [devAdminToken.id]) as { n: number }[])[0]?.n === 0) {
      raw.run("INSERT INTO admins (id, discord_id, role, api_token_hash, quota_keys, created_at) VALUES (?, '1001', 'owner', ?, NULL, ?)", [devAdminToken.id, devAdminToken.secretHash, now]);
    }
    return;
  }

  raw.run("INSERT INTO projects (id, name, slug, owner_id, signing_key_id, created_at) VALUES (?, ?, ?, ?, ?, ?)", [
    DEMO_PROJECT_ID,
    "Yuri Hub",
    "yuri",
    "owner-1",
    "signing-1",
    now,
  ]);
  raw.run("INSERT INTO scripts (id, project_id, name, keyless, active_version, created_at) VALUES (?, ?, ?, 0, 2, ?)", [
    DEMO_SCRIPT_ID,
    DEMO_PROJECT_ID,
    "Homumado",
    now,
  ]);
  raw.run("INSERT INTO script_games (script_id, game_id) VALUES (?, ?)", [DEMO_SCRIPT_ID, DEMO_GAME_ID]);
  raw.run("INSERT INTO script_versions (script_id, version, blob_ref, build_hash, init_build, notes, created_at) VALUES (?, 1, ?, ?, 'init-b1', 'initial build', ?)", [
    DEMO_SCRIPT_ID,
    "bundle/v1/demo",
    "ab".repeat(32),
    now,
  ]);
  raw.run("INSERT INTO script_versions (script_id, version, blob_ref, build_hash, init_build, notes, created_at) VALUES (?, 2, ?, ?, 'init-b1', 'anti-cheat hardening', ?)", [
    DEMO_SCRIPT_ID,
    "bundle/v2/demo",
    "cd".repeat(32),
    now,
  ]);
  raw.run("INSERT INTO nodes (id, hostname, region, active) VALUES (?, ?, ?, 1)", ["node-1", "auth1.example.net", "eu"]);
  raw.run("INSERT INTO nodes (id, hostname, region, active) VALUES (?, ?, ?, 1)", ["node-2", "auth2.example.net", "us"]);
  raw.run("INSERT INTO protocol_versions (version, handler, min_loader, active) VALUES (?, ?, ?, 1)", ["1", "v1", "1.0.0"]);
  raw.run("INSERT INTO protocol_versions (version, handler, min_loader, active) VALUES (?, ?, ?, 1)", ["2", "v1", "1.1.0"]);

  // Free-key checkpoints (doc §14): custom provider demo chain — the URL
  // template carries the per-attempt step secret ({{SECRET}}).
  raw.run("INSERT INTO checkpoints (id, project_id, position, provider, config) VALUES (?, ?, 1, 'custom', ?)", [
    "cp1",
    DEMO_PROJECT_ID,
    JSON.stringify({
      url: "https://demo.checkpoint.local/step1?s={{SECRET}}",
      min_seconds: 8,
      cooldown_seconds: 90,
      verify: "secret",
    }),
  ]);
  raw.run("INSERT INTO checkpoints (id, project_id, position, provider, config) VALUES (?, ?, 2, 'custom', ?)", [
    "cp2",
    DEMO_PROJECT_ID,
    JSON.stringify({
      url: "https://demo.checkpoint.local/step2?s={{SECRET}}&a={{ATTEMPT}}",
      min_seconds: 5,
      cooldown_seconds: 90,
      verify: "secret",
    }),
  ]);

  // Demo keys so the dashboard renders real rows (hashes via the real
  // machinery — plaintext never stored). discord/roblox identities make the
  // Users view (§16) render data.
  const demoKeys: { note: string; tier: string; status: string; days: number | null; exec: number; discord: string | null; roblox: number | null }[] = [
    { note: "reseller batch sample", tier: "paid", status: "active", days: 30, exec: 42, discord: "203040", roblox: null },
    { note: "vip member", tier: "lifetime", status: "active", days: null, exec: 1337, discord: "203041", roblox: null },
    { note: "abused key — chargeback", tier: "paid", status: "revoked", days: 30, exec: 7, discord: "203042", roblox: null },
    { note: "free flow sample", tier: "free", status: "active", days: 3, exec: 2, discord: null, roblox: 5512345 },
  ];
  for (const k of demoKeys) {
    const generated = generateKey("YURI");
    const keyHash = await hashKey(generated.plaintext, PEPPER);
    const keyId = "k" + generated.body.slice(0, 31).toLowerCase();
    raw.run(
      "INSERT INTO keys (id, project_id, key_hash, tier, status, note, total_executions, created_by, created_at, expires_at, first_used_at, last_used_at, discord_id, roblox_user_id) VALUES (?, ?, ?, ?, ?, ?, ?, 'seed', ?, ?, ?, ?, ?, ?)",
      [keyId, DEMO_PROJECT_ID, keyHash, k.tier, k.status, k.note, k.exec, now - 86400 * 3, k.days ? now + k.days * 86400 : null, now - 86400 * 2, now - 3600, k.discord, k.roblox],
    );
    raw.run("INSERT INTO key_scripts (key_id, script_id) VALUES (?, ?)", [keyId, DEMO_SCRIPT_ID]);
  }

  // Demo sessions so the Sessions view renders rows (watermark ids unique).
  raw.run(
    "INSERT INTO sessions (id, key_id, script_id, version, hwid_hash, ip_hash, roblox_user_id, place_id, watermark_id, created_at, expires_at) VALUES (?, (SELECT id FROM keys WHERE note = 'vip member'), ?, 2, ?, ?, 203041, ?, ?, ?, ?)",
    ["s" + "3".repeat(31), DEMO_SCRIPT_ID, "ab".repeat(31), "cd".repeat(31), DEMO_GAME_ID, "wm-" + "7".repeat(12), now - 7200, now + 3600],
  );
  raw.run(
    "INSERT INTO sessions (id, key_id, script_id, version, hwid_hash, ip_hash, roblox_user_id, place_id, watermark_id, created_at, expires_at) VALUES (?, (SELECT id FROM keys WHERE note = 'free flow sample'), ?, 2, ?, ?, 5512345, ?, ?, ?, ?)",
    ["s" + "4".repeat(31), DEMO_SCRIPT_ID, "ef".repeat(31), "01".repeat(31), DEMO_GAME_ID, "wm-" + "8".repeat(12), now - 5400, now + 1800],
  );

  // Demo reseller admin row (display seed; live minting goes through the
  // real POST /admin/resellers with plaintext-once display).
  raw.run("INSERT INTO admins (id, discord_id, role, api_token_hash, quota_keys, created_at) VALUES (?, '998001', 'reseller', ?, 50, ?)", [
    "44444444444444444444444444444443",
    await sha256Hex("demo-reseller-secret-not-usable-" + now),
    now - 86400,
  ]);

  // M10 demo: payment products + one paid order (real key) + one refunded
  // order (key revoked) so the Payments view renders data on first load.
  raw.run("INSERT INTO payment_products (id, provider, product_ref, project_id, tier, days, scripts, refund_blacklists, active, created_at) VALUES (?, 'custom', 'prod_demo_30d', ?, 'paid', 30, '[]', 0, 1, ?)", ["pp" + "1".repeat(30), DEMO_PROJECT_ID, now - 86400]);
  raw.run("INSERT INTO payment_products (id, provider, product_ref, project_id, tier, days, scripts, refund_blacklists, active, created_at) VALUES (?, 'custom', 'prod_demo_life', ?, 'lifetime', NULL, '[]', 1, 1, ?)", ["pp" + "2".repeat(30), DEMO_PROJECT_ID, now - 86400]);
  const paidKey = generateKey("YURI");
  const paidKeyId = "k" + paidKey.body.slice(0, 31).toLowerCase();
  raw.run(
    "INSERT INTO keys (id, project_id, key_hash, tier, status, discord_id, note, total_executions, created_by, created_at, expires_at) VALUES (?, ?, ?, 'paid', 'active', '203040', 'order ord_demo_paid_1', 0, 'm10:custom', ?, ?)",
    [paidKeyId, DEMO_PROJECT_ID, await hashKey(paidKey.plaintext, PEPPER), now - 86400 * 2, now + 28 * 86400],
  );
  raw.run("INSERT INTO key_scripts (key_id, script_id) VALUES (?, ?)", [paidKeyId, DEMO_SCRIPT_ID]);
  raw.run(
    "INSERT INTO orders (id, provider, provider_order_id, product_ref, project_id, key_id, discord_id, email, amount_minor, currency, status, created_at, updated_at) VALUES (?, 'custom', 'ord_demo_paid_1', 'prod_demo_30d', ?, ?, '203040', 'buyer@example.test', 999, 'usd', 'paid', ?, ?)",
    ["o" + "1".repeat(31), DEMO_PROJECT_ID, paidKeyId, now - 86400 * 2, now - 86400 * 2],
  );
  const refundedKey = generateKey("YURI");
  const refundedKeyId = "k" + refundedKey.body.slice(0, 31).toLowerCase();
  raw.run(
    "INSERT INTO keys (id, project_id, key_hash, tier, status, discord_id, note, total_executions, created_by, created_at, expires_at) VALUES (?, ?, ?, 'paid', 'revoked', '203043', 'order ord_demo_refund_1 (refunded)', 12, 'm10:custom', ?, ?)",
    [refundedKeyId, DEMO_PROJECT_ID, await hashKey(refundedKey.plaintext, PEPPER), now - 86400 * 9, now - 86400 * 9 + 30 * 86400],
  );
  raw.run("INSERT INTO key_scripts (key_id, script_id) VALUES (?, ?)", [refundedKeyId, DEMO_SCRIPT_ID]);
  raw.run(
    "INSERT INTO orders (id, provider, provider_order_id, product_ref, project_id, key_id, discord_id, email, amount_minor, currency, status, created_at, updated_at) VALUES (?, 'custom', 'ord_demo_refund_1', 'prod_demo_life', ?, ?, '203043', 'refund@example.test', 1999, 'usd', 'refunded', ?, ?)",
    ["o" + "2".repeat(31), DEMO_PROJECT_ID, refundedKeyId, now - 86400 * 9, now - 86400 * 5],
  );
  raw.run("INSERT INTO payment_events (provider, event_id, event_type, outcome, order_id, created_at) VALUES ('custom', 'evt_seed_paid_1', 'payment.confirmed', 'issued', ?, ?)", ["o" + "1".repeat(31), now - 86400 * 2]);
  raw.run("INSERT INTO payment_events (provider, event_id, event_type, outcome, order_id, created_at) VALUES ('custom', 'evt_seed_refund_1', 'payment.refunded', 'refunded', ?, ?)", ["o" + "2".repeat(31), now - 86400 * 5]);

  // Demo audit + events
  raw.run("INSERT INTO audit_log (id, actor_id, action, target, detail, created_at) VALUES (?, ?, ?, ?, ?, ?)", [
    "a" + "1".repeat(31),
    "seed",
    "seed.bootstrap",
    DEMO_PROJECT_ID,
    "dashboard demo seed",
    now,
  ]);
  raw.run("INSERT INTO events (id, key_id, type, detail, created_at) VALUES (?, NULL, 'validate_ok', 'seed sample', ?)", ["e" + "1".repeat(31), now - 600]);
  raw.run("INSERT INTO events (id, key_id, type, detail, created_at) VALUES (?, NULL, 'validate_fail', 'proof', ?)", ["e" + "2".repeat(31), now - 300]);

  // Dev admin row: token format per owner Q2 (adm_<id>.<secret>)
  raw.run("INSERT INTO admins (id, discord_id, role, api_token_hash, quota_keys, created_at) VALUES (?, '1001', 'owner', ?, NULL, ?)", [
    devAdminToken.id,
    devAdminToken.secretHash,
    now,
  ]);
}

// 14-day analytics history (M11 s3 Overview charts). Idempotent via its own
// actor marker so already-seeded demo DBs are enriched in place. Deterministic
// LCG keeps the generated history stable across restarts.
async function seedAnalyticsHistory(raw: RawSqlite, now: number): Promise<void> {
  const marker = raw.query("SELECT COUNT(*) AS n FROM audit_log WHERE actor_id = 'seed-history'", []) as { n: number }[];
  if ((marker[0]?.n ?? 0) > 0) return;

  let s = 42;
  const rnd = (): number => {
    s = (s * 1103515245 + 12345) % 2147483648;
    return s / 2147483648;
  };
  const pick = <T,>(arr: T[]): T => arr[Math.floor(rnd() * arr.length)]!;

  const actions: { action: string; detail: string }[] = [
    { action: "key.create", detail: "batch mint (reseller)" },
    { action: "key.extend", detail: "support extension +14d" },
    { action: "key.revoke", detail: "chargeback" },
    { action: "hwid.reset", detail: "new machine" },
    { action: "blacklist.add", detail: "hwid abuse" },
    { action: "payment.issue", detail: "webhook confirmed" },
    { action: "payment.refund", detail: "refund processed" },
    { action: "free.claim", detail: "checkpoint flow complete" },
    { action: "script.activate", detail: "version rollout" },
  ];

  let n = 0;
  for (let d = 13; d >= 0; d--) {
    const dayStart = now - (d + 1) * 86400;
    const rows = 3 + Math.floor(rnd() * 6); // 3–8 audit rows per day
    for (let i = 0; i < rows; i++) {
      const a = pick(actions);
      n += 1;
      raw.run(
        "INSERT INTO audit_log (id, actor_id, action, target, detail, created_at) VALUES (?, 'seed-history', ?, NULL, ?, ?)",
        ["h" + String(n).padStart(7, "0") + "a".repeat(24), a.action, a.detail, dayStart + Math.floor(rnd() * 86400)],
      );
    }
  }

  // Validation events inside the live 24h window (drives the overview stats)
  for (let i = 0; i < 41; i++) {
    raw.run("INSERT INTO events (id, key_id, type, detail, created_at) VALUES (?, NULL, 'validate_ok', 'history sample', ?)", [
      "vh" + String(i).padStart(4, "0") + "b".repeat(27),
      now - Math.floor(rnd() * 86400),
    ]);
  }
  for (let i = 0; i < 5; i++) {
    raw.run("INSERT INTO events (id, key_id, type, detail, created_at) VALUES (?, NULL, 'validate_fail', 'proof', ?)", [
      "vf" + String(i).padStart(4, "0") + "c".repeat(27),
      now - Math.floor(rnd() * 86400),
    ]);
  }
  raw.run("INSERT INTO events (id, key_id, type, detail, created_at) VALUES (?, NULL, 'tamper', 'history sample', ?)", [
    "vt" + "d".repeat(30),
    now - 3600,
  ]);

  // Extra demo keys spread over the last 14 days (tier variety for the donut
  // + keys-created/day series). Hashes via the real machinery.
  const extraKeys: { tier: string; days: number | null; exec: number; d: number; note: string }[] = [
    { tier: "paid", days: 30, exec: 15, d: 13, note: "launch batch" },
    { tier: "free", days: 3, exec: 4, d: 11, note: "free flow" },
    { tier: "paid", days: 30, exec: 87, d: 10, note: "weekly batch" },
    { tier: "lifetime", days: null, exec: 210, d: 8, note: "vip" },
    { tier: "reseller", days: 30, exec: 9, d: 7, note: "reseller batch" },
    { tier: "paid", days: 30, exec: 56, d: 5, note: "weekly batch" },
    { tier: "free", days: 3, exec: 6, d: 4, note: "free flow" },
    { tier: "paid", days: 90, exec: 33, d: 2, note: "quarterly" },
  ];
  for (const k of extraKeys) {
    const generated = generateKey("YURI");
    const keyId = "k" + generated.body.slice(0, 31).toLowerCase();
    raw.run(
      "INSERT INTO keys (id, project_id, key_hash, tier, status, note, total_executions, created_by, created_at, expires_at, first_used_at, last_used_at, discord_id, roblox_user_id) VALUES (?, ?, ?, ?, 'active', ?, ?, 'seed', ?, ?, ?, ?, ?, ?)",
      [keyId, DEMO_PROJECT_ID, await hashKey(generated.plaintext, PEPPER), k.tier, k.note, k.exec, now - k.d * 86400, k.days ? now + (k.days - k.d) * 86400 : null, now - k.d * 86400 + 600, now - k.d * 43200, k.tier === "free" ? null : String(203040 + k.d), k.tier === "free" ? 5512345 + k.d : null],
    );
    raw.run("INSERT INTO key_scripts (key_id, script_id) VALUES (?, ?)", [keyId, DEMO_SCRIPT_ID]);
  }
}

async function buildStore(): Promise<DevStore> {
  mkdirSync(DB_DIR, { recursive: true });
  const keys = await loadOrCreateKeystore();
  const raw = openRawSqlite(DB_PATH);
  for (const stmt of DOC_SCHEMA_SQL.split(";").map((s) => s.trim()).filter((s) => s.length > 0)) {
    raw.exec(stmt + ";");
  }
  // M10 additive tables (CCP-4) — same source the payments module applies
  // lazily; applying here too so the demo seed can insert rows.
  for (const stmt of PAYMENTS_SCHEMA_SQL.split(";").map((s) => s.trim()).filter((s) => s.length > 0)) {
    raw.exec(stmt + ";");
  }
  // dashboard-owned state (D-M11-2): TOTP enrollment only; the rest of the
  // schema is the doc §6 contract.
  raw.exec("CREATE TABLE IF NOT EXISTS dash_totp (admin_id TEXT PRIMARY KEY, secret_b32 TEXT NOT NULL, enabled INTEGER NOT NULL DEFAULT 0, created_at INTEGER NOT NULL)");

  const now = Math.floor(Date.now() / 1000);
  const devAdminToken = `adm_${keys.devAdminId}.${keys.devAdminSecretB64url}`;
  const secretHash = await sha256Hex(b64urlDecode(keys.devAdminSecretB64url));
  await seedDemoData(raw, { id: keys.devAdminId, secretHash }, now);
  await seedAnalyticsHistory(raw, now);

  const signer = await makeSigner(keys.signingPrivateKeyB64url);
  const blobs = new MemoryBlobStore();
  blobs.put("bundle/v1/demo", utf8("-- Homumado protected bundle v1 (demo bytes)"));
  blobs.put("bundle/v2/demo", utf8("-- Homumado protected bundle v2 (demo bytes, hardened)"));

  const config: ApiConfig = {
    pepper: PEPPER,
    proofKey: PROOF_KEY,
    signer,
    executorHwidHeaders: ["Delta-User-Identifier", "Delta-Fingerprint"],
    statusActive: true,
    sessionTtlSec: 3600,
    refSealKey: await refSealKey(keys.sessionSealSecret),
    bundleStore: blobs,
    bundleSignerFor: () => signer,
    free: {
      requestsPerIpPerMin: 30,
      startsPerIpPerMin: 5,
      attemptsPerIpPerHour: 10,
      attemptTtlSec: 7200,
      claimWindowSec: 900,
      keyDays: 3,
    },
    freeSecret: b64urlDecode(keys.freeSecretB64url),
    payments: {
      webhookSecrets: { custom: [DEV_WEBHOOK_SECRET] },
      signatureToleranceSec: 300,
      requestsPerIpPerMin: 30,
    },
  };

  let nowOverride: number | null = null;
  const ctx: AppContext = {
    db: new SqliteAdapter(raw),
    limiter: new MemoryRateLimiter(),
    nonce: new MemoryNonceStore(),
    get nowSec() {
      return nowOverride ?? Date.now() / 1000;
    },
    set nowSec(v: number) {
      nowOverride = v;
    },
  };

  const discordConfigured = Boolean(process.env.DASH_DISCORD_CLIENT_ID && process.env.DASH_DISCORD_CLIENT_SECRET);

  return {
    raw,
    ctx,
    config,
    devAdminToken,
    devAdminId: keys.devAdminId,
    dashboardSessionSecret: b64urlDecode(keys.dashboardSessionSecretB64url),
    blobStore: blobs,
    discordConfigured,
  };
}

const globalStore = globalThis as unknown as { __dashStore?: Promise<DevStore> };

export function getStore(): Promise<DevStore> {
  if (!globalStore.__dashStore) {
    globalStore.__dashStore = buildStore();
  }
  return globalStore.__dashStore;
}

export const DASH_DEV_MODE = (process.env.DASH_DEV_MODE ?? "true") !== "false";
