// Module M12 chaos tests (doc §22 Ops row, D-M12-7): DB down, blob store
// down, signing key missing, node unreachable. Every fault is injected
// around the REAL dispatch (real router + real handlers) and asserts the
// three §22 properties:
//   1. fail-closed — the envelope denies service; no partial script load
//   2. generic errors — no stack traces, no internal detail, no SQL/driver
//      strings in the response body
//   3. no partial state — the faulting request leaves no half-committed
//      rows (row counts asserted around each request)
//
// These run in CI on every push (chaos is continuously asserted, not a
// one-off runbook step — D-M12-7).

import { beforeAll, describe, expect, test } from "bun:test";
import {
  ADMIN_TOKEN,
  GAME_ID,
  INIT_BUILD,
  SCRIPT_ID,
  TestEnv,
  buildEnv,
  envelopeOf,
  makeSignedInput,
} from "./helpers";
import { buildRoutes, dispatch } from "../src/router";
import { DbAdapter, DbResult } from "../src/db";
import { BlobStore } from "../src/blobs";
import { Signer } from "../src/crypto";
import { b64urlDecode, b64urlEncode } from "../src/contracts";
import { aeadOpen, concatBytes } from "../src/chacha";
import { generateX25519KeyPair, x25519SharedSecret } from "../src/x25519";
import { hkdfSha256, randomBytes, utf8 } from "../src/crypto";
import { AppContext, ApiConfig } from "../src/flow";

// ---------------------------------------------------------------------------
// Fault adapters
// ---------------------------------------------------------------------------

// DB down: every method rejects with a driver-shaped error whose message
// must NEVER reach a response body (asserted below).
class ThrowingDb implements DbAdapter {
  run(): Promise<DbResult> {
    return Promise.reject(new Error("D1 unavailable: SQLITE_IOERR (code 5898)"));
  }
  first<T>(): Promise<T | null> {
    return Promise.reject(new Error("D1 unavailable: SQLITE_IOERR (code 5898)"));
  }
  all<T>(): Promise<T[]> {
    return Promise.reject(new Error("D1 unavailable: SQLITE_IOERR (code 5898)"));
  }
  batch(): Promise<DbResult[]> {
    return Promise.reject(new Error("D1 unavailable: SQLITE_IOERR (code 5898)"));
  }
}

// Blob store down: get() rejects (vs. resolving null = bundle missing,
// which is a separate case below — the handler distinguishes them).
class ThrowingBlob implements BlobStore {
  get(): Promise<Uint8Array | null> {
    return Promise.reject(new Error("R2 GetObject 404 NoSuchKey"));
  }
}

// Blob store up but bundle absent (deleted / never uploaded).
class EmptyBlob implements BlobStore {
  get(): Promise<Uint8Array | null> {
    return Promise.resolve(null);
  }
}

// Signing key missing/broken: sign() rejects. The dispatch catch-block's
// own fallback must survive this (D-M12-9) — the SDK treats an unsigned
// response as a hard failure, which IS the fail-closed behavior.
class ThrowingSigner implements Signer {
  sign(): Promise<Uint8Array> {
    return Promise.reject(new Error("malformed private key DER"));
  }
}

function ctxWithDb(env: TestEnv, db: DbAdapter): AppContext {
  return { ...env.ctx, db };
}

function configWithSigner(env: TestEnv, signer: Signer): ApiConfig {
  return { ...env.config, signer };
}

function configWithBlobs(env: TestEnv, blobs: BlobStore): ApiConfig {
  return { ...env.config, bundleStore: blobs };
}

async function post(env: TestEnv, path: string, body: Record<string, unknown>, ctx?: AppContext, config?: ApiConfig): Promise<{ status: number; text: string; headers: Record<string, string> }> {
  const input = await makeSignedInput("POST", path, body);
  const res = await dispatch(buildRoutes(), ctx ?? env.ctx, config ?? env.config, input);
  const headers: Record<string, string> = {};
  res.headers.forEach((v, k) => (headers[k] = v));
  return { status: res.status, text: await res.text(), headers };
}

async function get(env: TestEnv, path: string, ctx?: AppContext, config?: ApiConfig): Promise<{ status: number; text: string; headers: Record<string, string> }> {
  const input = await makeSignedInput("GET", path, null, { headers: { authorization: `Bearer ${ADMIN_TOKEN}` } });
  const res = await dispatch(buildRoutes(), ctx ?? env.ctx, config ?? env.config, input);
  const headers: Record<string, string> = {};
  res.headers.forEach((v, k) => (headers[k] = v));
  return { status: res.status, text: await res.text(), headers };
}

// The §22 generic-error property: no driver strings, no exception classes,
// no stack fragments in any response body.
function expectGeneric(text: string): void {
  const lower = text.toLowerCase();
  for (const leak of ["sqlite", "d1 unavailable", "r2 getobject", "nosuchkey", "malformed private key", "error:", "at /", "at file"]) {
    expect(lower.includes(leak)).toBe(false);
  }
}

function countRows(env: TestEnv, table: string): number {
  return (env.db.prepare(`SELECT COUNT(*) AS n FROM ${table}`).get() as { n: number }).n;
}

// ---------------------------------------------------------------------------
// Minimal auth client (compact version of test/auth.test.ts machinery —
// enough to drive init + payload through the real router).
// ---------------------------------------------------------------------------

interface ClientSession {
  sessionToken: string;
  payloadRef: string;
  sessionKey: Uint8Array;
  sessionIdRaw: Uint8Array;
}

async function clientInit(env: TestEnv, key: string, ctx?: AppContext, config?: ApiConfig): Promise<ClientSession> {
  const client = generateX25519KeyPair(randomBytes(32));
  const clientNonce = randomBytes(16);
  const hello = b64urlEncode(concatBytes(client.publicKey, clientNonce));
  const body = { v: 1, key, build: INIT_BUILD, place_id: 12345, game_id: GAME_ID, user_id: 987654, hello };
  const input = await makeSignedInput("POST", `/auth/${SCRIPT_ID}/init`, body);
  const res = await dispatch(buildRoutes(), ctx ?? env.ctx, config ?? env.config, input);
  expect(res.status).toBe(200);
  expect(res.headers.get("content-type")).toBe("text/plain");
  const wire = b64urlDecode(await res.text());
  const serverPub = wire.subarray(0, 32);
  const serverNonce = wire.subarray(32, 48);
  const ct = wire.subarray(48, wire.length - 16);
  const tag = wire.subarray(wire.length - 16);
  const shared = x25519SharedSecret(client.privateKey, serverPub);
  const sessionKey = await hkdfSha256(shared, concatBytes(clientNonce, serverNonce), utf8("session-key"), 32);
  const aad = concatBytes(utf8(SCRIPT_ID), serverPub, serverNonce);
  const plain = aeadOpen(sessionKey, serverNonce.subarray(0, 12), aad, ct, tag);
  expect(plain).not.toBeNull();
  const parsed = JSON.parse(new TextDecoder().decode(plain!)) as { session_token: string; payload_ref: string };
  return { sessionToken: parsed.session_token, payloadRef: parsed.payload_ref, sessionKey, sessionIdRaw: b64urlDecode(parsed.session_token) };
}

async function clientPayload(env: TestEnv, session: ClientSession, ctx?: AppContext, config?: ApiConfig): Promise<{ status: number; text: string; contentType: string }> {
  const body = { v: 1, session_token: session.sessionToken, payload_ref: session.payloadRef };
  const input = await makeSignedInput("POST", `/auth/${SCRIPT_ID}/payload`, body);
  const res = await dispatch(buildRoutes(), ctx ?? env.ctx, config ?? env.config, input);
  return { status: res.status, text: await res.text(), contentType: res.headers.get("content-type") ?? "" };
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

describe("M12 chaos — DB down (doc §22)", () => {
  let env: TestEnv;
  let goodKey: { plaintext: string; id: string };

  beforeAll(async () => {
    env = await buildEnv();
    goodKey = await env.createKey({ tier: "paid", days: 30 });
  });

  test("/check_key fails closed with a SIGNED generic SERVER_ERROR envelope", async () => {
    const broken = ctxWithDb(env, new ThrowingDb());
    const r = await post(env, "/check_key", { key: goodKey.plaintext, script_id: SCRIPT_ID, lv: "1.0.0" }, broken);
    expect(r.status).toBe(200);
    const envelope = JSON.parse(r.text) as { code: string; data: unknown };
    expect(envelope.code).toBe("SERVER_ERROR");
    expect(envelope.data).toBeNull();
    expectGeneric(r.text);
    // The signer still works during a DB outage → the envelope is signed
    // (SDKs can authenticate the failure itself).
    expect(r.headers["x-sig"]).toBeTruthy();
  });

  test("/sync fails closed with a generic envelope too", async () => {
    const broken = ctxWithDb(env, new ThrowingDb());
    const r = await get(env, "/sync", broken);
    expect(r.status).toBe(200);
    expect((JSON.parse(r.text) as { code: string }).code).toBe("SERVER_ERROR");
    expectGeneric(r.text);
  });

  test("/admin/metrics fails closed, no partial JSON", async () => {
    const broken = ctxWithDb(env, new ThrowingDb());
    const r = await get(env, "/admin/metrics?window=1h", broken);
    expect(r.status).toBe(200);
    expect((JSON.parse(r.text) as { code: string }).code).toBe("SERVER_ERROR");
    expectGeneric(r.text);
  });

  test("webhook path fails closed with generic 503-family JSON, no leak", async () => {
    const broken = ctxWithDb(env, new ThrowingDb());
    const r = await post(env, "/webhooks/payments/custom", { type: "payment_confirmed" }, broken);
    // Whatever the outcome (503/500/200-envelope), it must be generic JSON.
    expect(r.headers["content-type"]).toBe("application/json");
    expectGeneric(r.text);
    expect(r.text.length).toBeLessThan(400);
  });

  test("no partial state: a DB-down request leaves zero new rows anywhere", async () => {
    const before = { events: countRows(env, "events"), sessions: countRows(env, "sessions"), keys: countRows(env, "keys") };
    const broken = ctxWithDb(env, new ThrowingDb());
    await post(env, "/check_key", { key: goodKey.plaintext, script_id: SCRIPT_ID, lv: "1.0.0" }, broken);
    await get(env, "/admin/metrics", broken);
    const after = { events: countRows(env, "events"), sessions: countRows(env, "sessions"), keys: countRows(env, "keys") };
    expect(after).toEqual(before);
  });
});

describe("M12 chaos — signing key missing (doc §22, D-M12-9 fallback)", () => {
  let env: TestEnv;
  let goodKey: { plaintext: string; id: string };

  beforeAll(async () => {
    env = await buildEnv();
    goodKey = await env.createKey({ tier: "paid", days: 30 });
  });

  test("dispatch survives a broken signer: unsigned generic 500, no signature header", async () => {
    const broken = configWithSigner(env, new ThrowingSigner());
    const r = await post(env, "/check_key", { key: goodKey.plaintext, script_id: SCRIPT_ID, lv: "1.0.0" }, env.ctx, broken);
    // D-M12-9: the previously-CRASHING path (signedResponse itself rejects)
    // now answers an unsigned generic 500. SDKs reject unsigned responses —
    // fail-closed — instead of a Workers 1101 unhandled rejection.
    expect(r.status).toBe(500);
    expect(JSON.parse(r.text)).toEqual({ error: "server_error" });
    expect(r.headers["x-sig"]).toBeUndefined();
    expectGeneric(r.text);
  });

  test("the error path still records the server_error event (DB alive, signer broken)", async () => {
    const before = countRows(env, "events");
    const broken = configWithSigner(env, new ThrowingSigner());
    // check_key VALIDATES fine (DB alive) → one validate_ok row — then the
    // response signing fails → dispatch catch → one server_error row. The
    // client still gets nothing usable (unsigned 500 = fail-closed), but
    // the operator sees BOTH facts in the event stream.
    await post(env, "/check_key", { key: goodKey.plaintext, script_id: SCRIPT_ID, lv: "1.0.0" }, env.ctx, broken);
    const after = countRows(env, "events");
    expect(after).toBe(before + 2);
    const last = env.db.prepare("SELECT type FROM events ORDER BY rowid DESC LIMIT 1").get() as { type: string };
    expect(last.type).toBe("server_error");
  });
});

describe("M12 chaos — blob store down / bundle missing (doc §22)", () => {
  let env: TestEnv;
  let goodKey: { plaintext: string; id: string };
  let session: ClientSession;

  beforeAll(async () => {
    env = await buildEnv();
    goodKey = await env.createKey({ tier: "paid", days: 30 });
    // A healthy init (session created, state committed) before the fault.
    session = await clientInit(env, goodKey.plaintext);
  });

  test("bundle ABSENT (get → null): generic SERVER_ERROR + bundle-missing event, session state untouched", async () => {
    const eventsBefore = countRows(env, "events");
    const sessionsBefore = countRows(env, "sessions");
    const broken = configWithBlobs(env, new EmptyBlob());
    const r = await clientPayload(env, session, env.ctx, broken);
    expect(r.status).toBe(200);
    expect(r.contentType).toBe("application/json");
    const envelope = JSON.parse(r.text) as { code: string; data: unknown };
    expect(envelope.code).toBe("SERVER_ERROR");
    expectGeneric(r.text);
    // The handler recorded exactly one diagnostic event; no other state moved.
    expect(countRows(env, "events")).toBe(eventsBefore + 1);
    expect(countRows(env, "sessions")).toBe(sessionsBefore);
    const last = env.db.prepare("SELECT type, detail FROM events ORDER BY rowid DESC LIMIT 1").get() as { type: string; detail: string };
    expect(last.type).toBe("server_error");
    expect(last.detail).toBe("bundle-missing");
  });

  test("blob store ERRORING (get → reject): dispatch catch → signed generic envelope", async () => {
    const broken = configWithBlobs(env, new ThrowingBlob());
    const r = await clientPayload(env, session, env.ctx, broken);
    expect(r.status).toBe(200);
    const envelope = JSON.parse(r.text) as { code: string };
    expect(envelope.code).toBe("SERVER_ERROR");
    expectGeneric(r.text);
  });

  test("fail-closed end-to-end: no payload bytes ever reach the client under either fault", async () => {
    const bundleBytes = "-- protected script bundle bytes v1";
    for (const blobs of [new EmptyBlob(), new ThrowingBlob()]) {
      const broken = configWithBlobs(env, blobs);
      const r = await clientPayload(env, session, env.ctx, broken);
      expect(r.text.includes(bundleBytes)).toBe(false);
      expect(r.contentType).not.toBe("application/octet-stream");
    }
  });
});

describe("M12 chaos — node unreachable / node table drained (doc §22)", () => {
  let env: TestEnv;
  let goodKey: { plaintext: string; id: string };

  beforeAll(async () => {
    env = await buildEnv();
    goodKey = await env.createKey({ tier: "paid", days: 30 });
  });

  test("one node deactivated: /sync still serves the survivor, service unaffected", async () => {
    env.db.prepare("UPDATE nodes SET active = 0 WHERE id = 'node-1'").run();
    const r = await get(env, "/sync");
    expect(r.status).toBe(200);
    const body = JSON.parse(r.text) as { nodes: string[]; st: number };
    expect(body.nodes).toEqual(["https://auth2.example.net"]);
    // check_key still fully functional with a node down (nodes are
    // bootstrap redundancy, not a runtime dependency).
    const ck = await post(env, "/check_key", { key: goodKey.plaintext, script_id: SCRIPT_ID, lv: "1.0.0" });
    const envelope = await envelopeOf(new Response(ck.text, { headers: ck.headers }));
    expect(envelope.code).toBe("KEY_VALID");
  });

  test("all nodes deactivated: /sync answers (empty list), /admin/alerts fires nodes-degraded critical", async () => {
    env.db.prepare("UPDATE nodes SET active = 0").run();
    const sync = await get(env, "/sync");
    expect(sync.status).toBe(200);
    expect((JSON.parse(sync.text) as { nodes: string[] }).nodes).toEqual([]);
    const alerts = await get(env, "/admin/alerts");
    expect(alerts.status).toBe(200);
    const body = JSON.parse(alerts.text) as { alerts: { id: string; severity: string }[] };
    const nodeAlert = body.alerts.find((a) => a.id === "nodes-degraded");
    expect(nodeAlert).toBeDefined();
    expect(nodeAlert!.severity).toBe("critical");
    // Core auth still works — node loss never takes the API itself down.
    const ck = await post(env, "/check_key", { key: goodKey.plaintext, script_id: SCRIPT_ID, lv: "1.0.0" });
    const envelope = await envelopeOf(new Response(ck.text, { headers: ck.headers }));
    expect(envelope.code).toBe("KEY_VALID");
  });
});
