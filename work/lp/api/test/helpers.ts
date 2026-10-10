import { Database } from "bun:sqlite";
import { DOC_SCHEMA_SQL, SqliteAdapter } from "../src/db";
import { MemoryNonceStore, MemoryRateLimiter } from "../src/state";
import { utf8 } from "../src/crypto";
import { b64urlEncode } from "../src/contracts";
import { generateSigningKeys, makeSigner, makeVerifier, randomBytes, sha256Hex, hmacSha256 } from "../src/crypto";
import { ApiConfig, AppContext, RequestInput, proofPayload } from "../src/flow";
import { generateKey, hashKey, projectHwidSalt, hashHwid } from "../src/keys";
import { refSealKey } from "../src/auth";
import { MemoryBlobStore } from "../src/blobs";

export const PEPPER = "test-pepper-fixed";
export const PROOF_KEY = utf8("0123456789abcdef0123456789abcdef");
export const PROJECT_ID = "11111111111111111111111111111111";
export const SCRIPT_ID = "22222222222222222222222222222222";
export const OTHER_PROJECT_SCRIPT_ID = "33333333333333333333333333333333";
export const GAME_ID = 40961328;
export const SESSION_SEAL_SECRET = "session-seal-secret-for-tests";
export const ADMIN_ID = "44444444444444444444444444444441";
export const RESELLER_ID = "44444444444444444444444444444442";

const ADMIN_SECRET = randomBytes(32);
const RESELLER_SECRET = randomBytes(32);

export const ADMIN_TOKEN = `adm_${ADMIN_ID}.${b64urlEncode(ADMIN_SECRET)}`;
export const RESELLER_TOKEN = `adm_${RESELLER_ID}.${b64urlEncode(RESELLER_SECRET)}`;

export const INIT_BUILD = "init-b1";
export const BUNDLE_REF = "bundle/v1/test";
export const BUILD_HASH = "ab".repeat(32);

export interface TestEnv {
  db: Database;
  raw: { run: (sql: string, params: unknown[]) => { changes: number; lastInsertRowid: number | bigint }; query: (sql: string, params: unknown[]) => unknown[] };
  ctx: AppContext;
  config: ApiConfig;
  verifier: { verify: (payload: Uint8Array, signature: Uint8Array) => Promise<boolean> };
  blobs: MemoryBlobStore;
  createKey: (opts?: { tier?: string; days?: number | null; note?: string | null; scriptId?: string; status?: string }) => Promise<{ plaintext: string; id: string }>;
}

export async function buildEnv(): Promise<TestEnv> {
  const db = new Database(":memory:");
  for (const stmt of DOC_SCHEMA_SQL.split(";").map((s) => s.trim()).filter((s) => s.length > 0)) {
    db.exec(stmt + ";");
  }
  const raw = {
    run: (sql: string, params: unknown[]) => db.prepare(sql).run(...(params as never[])) as unknown as { changes: number; lastInsertRowid: number | bigint },
    query: (sql: string, params: unknown[]) => db.prepare(sql).all(...(params as never[])) as unknown[],
  };
  const adapter = new SqliteAdapter(raw);
  const now = Math.floor(Date.now() / 1000);

  db.prepare("INSERT INTO projects (id, name, slug, owner_id, signing_key_id, created_at) VALUES (?, ?, ?, ?, ?, ?)").run(PROJECT_ID, "Yuri Hub", "yuri", "owner-1", "signing-1", now);
  db.prepare("INSERT INTO scripts (id, project_id, name, keyless, active_version, created_at) VALUES (?, ?, ?, 0, 1, ?)").run(SCRIPT_ID, PROJECT_ID, "Homumado", now);
  db.prepare("INSERT INTO script_games (script_id, game_id) VALUES (?, ?)").run(SCRIPT_ID, GAME_ID);
  db.prepare("INSERT INTO script_versions (script_id, version, blob_ref, build_hash, init_build, notes, created_at) VALUES (?, 1, ?, ?, ?, NULL, ?)").run(SCRIPT_ID, BUNDLE_REF, BUILD_HASH, INIT_BUILD, now);
  db.prepare("INSERT INTO nodes (id, hostname, region, active) VALUES (?, ?, ?, 1)").run("node-1", "auth1.example.net", "eu");
  db.prepare("INSERT INTO nodes (id, hostname, region, active) VALUES (?, ?, ?, 1)").run("node-2", "auth2.example.net", "us");
  db.prepare("INSERT INTO protocol_versions (version, handler, min_loader, active) VALUES (?, ?, ?, 1)").run("1", "check_key", "1.0.0");
  db.prepare("INSERT INTO protocol_versions (version, handler, min_loader, active) VALUES (?, ?, ?, 1)").run("2", "auth", "1.0.0");

  // Owner answer Q2: store only SHA-256(secret) of the adm_<id>.<secret> token.
  const ownerHash = await sha256Hex(ADMIN_SECRET);
  db.prepare("INSERT INTO admins (id, discord_id, role, api_token_hash, quota_keys, created_at) VALUES (?, ?, ?, ?, NULL, ?)").run(ADMIN_ID, "1001", "owner", ownerHash, now);
  const resellerHash = await sha256Hex(RESELLER_SECRET);
  db.prepare("INSERT INTO admins (id, discord_id, role, api_token_hash, quota_keys, created_at) VALUES (?, NULL, ?, ?, 3, ?)").run(RESELLER_ID, "reseller", resellerHash, now);

  const pair = await generateSigningKeys();
  const signer = await makeSigner(b64urlEncode(pair.privateKeyPkcs8));
  const verifier = await makeVerifier(b64urlEncode(pair.publicKeyRaw));
  const blobs = new MemoryBlobStore();
  blobs.put(BUNDLE_REF, utf8("-- protected script bundle bytes v1"));

  const config: ApiConfig = {
    pepper: PEPPER,
    proofKey: PROOF_KEY,
    signer,
    executorHwidHeaders: ["Delta-User-Identifier", "Delta-Fingerprint"],
    statusActive: true,
    sessionTtlSec: 3600,
    refSealKey: await refSealKey(SESSION_SEAL_SECRET),
    bundleStore: blobs,
    bundleSignerFor: () => signer,
  };

  const ctx: AppContext = {
    db: adapter,
    limiter: new MemoryRateLimiter(),
    nonce: new MemoryNonceStore(),
    nowSec: Date.now() / 1000,
  };

  const createKey: TestEnv["createKey"] = async (opts) => {
    const generated = generateKey("YURI");
    const keyHash = await hashKey(generated.plaintext, PEPPER);
    const keyId = "k" + generated.body.slice(0, 31).toLowerCase();
    const expiresAt = opts?.days ? now + opts.days * 86400 : null;
    db.prepare(
      "INSERT INTO keys (id, project_id, key_hash, tier, status, note, total_executions, created_by, created_at, expires_at) VALUES (?, ?, ?, ?, ?, ?, 0, ?, ?, ?)",
    ).run(keyId, PROJECT_ID, keyHash, opts?.tier ?? "paid", opts?.status ?? "active", opts?.note ?? null, "seed", now, expiresAt);
    db.prepare("INSERT INTO key_scripts (key_id, script_id) VALUES (?, ?)").run(keyId, opts?.scriptId ?? SCRIPT_ID);
    return { plaintext: generated.plaintext, id: keyId };
  };

  return { db, raw, ctx, config, verifier, blobs, createKey };
}

export async function makeSignedInput(
  method: string,
  path: string,
  body: Record<string, unknown> | null,
  opts: { ip?: string; headers?: Record<string, string>; ts?: number; nonce?: string; bodyBytes?: Uint8Array } = {},
): Promise<RequestInput> {
  const ts = opts.ts !== undefined ? Math.floor(opts.ts) : Math.floor(Date.now() / 1000);
  const nonce = opts.nonce ?? b64urlEncode(randomBytes(16));
  const bodyBytes = opts.bodyBytes ?? (body !== null ? utf8(JSON.stringify(body)) : new Uint8Array(0));
  const bodyHashHex = await sha256Hex(bodyBytes);
  const proof = b64urlEncode(await hmacSha256(PROOF_KEY, proofPayload(method, path, String(ts), nonce, bodyHashHex)));
  const headers: Record<string, string> = {
    "x-ts": String(ts),
    "x-nonce": nonce,
    "x-lv": "1.0.0",
    "x-proof": proof,
    ...(opts.headers ?? {}),
  };
  return {
    method,
    path,
    headers,
    bodyBytes,
    ip: opts.ip ?? "203.0.113.10",
    colo: "TST",
  };
}

export async function hwidHashFor(hwid: string): Promise<string> {
  return hashHwid(hwid, await projectHwidSalt(PEPPER, PROJECT_ID));
}

export async function envelopeOf(res: Response): Promise<{ code: string; message: string; data: Record<string, unknown> | null }> {
  return (await res.json()) as { code: string; message: string; data: Record<string, unknown> | null };
}
