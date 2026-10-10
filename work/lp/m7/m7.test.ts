// Module M7 tests — leak tracing (§12), tamper ingestion (§11), abuse
// correlation (D-M7-7), and the CCP-M6 per-fetch salt (D-M7-4).
//
// The leak chain runs through the REAL router end-to-end: create key →
// auth init (real handshake) → craft the leaked artifact from what the
// client holds → extract → lookup → revoke → verify every side effect.

import { beforeAll, describe, expect, test } from "bun:test";
import {
  ADMIN_TOKEN,
  BUILD_HASH,
  GAME_ID,
  INIT_BUILD,
  RESELLER_TOKEN,
  SCRIPT_ID,
  TestEnv,
  buildEnv,
  envelopeOf,
  makeSignedInput,
} from "./helpers";
import { buildRoutes, dispatch } from "../src/router";
import { b64urlDecode, b64urlEncode, fromHex, toHex } from "../src/contracts";
import { hkdfSha256, randomBytes, utf8 } from "../src/crypto";
import { aeadOpen, concatBytes } from "../src/chacha";
import { generateX25519KeyPair, x25519SharedSecret } from "../src/x25519";

interface ClientSession {
  sessionToken: string;
  payloadRef: string;
  sessionKey: Uint8Array;
  sessionIdRaw: Uint8Array;
}

async function clientInit(
  env: TestEnv,
  opts: { key: string; hwid?: string | null; ip?: string } = {},
): Promise<ClientSession> {
  const client = generateX25519KeyPair(randomBytes(32));
  const clientNonce = randomBytes(16);
  const hello = b64urlEncode(concatBytes(client.publicKey, clientNonce));
  const headers: Record<string, string> = {};
  if (opts.hwid) headers["Delta-User-Identifier"] = opts.hwid;
  const input = await makeSignedInput("POST", `/auth/${SCRIPT_ID}/init`, {
    v: 1,
    key: opts.key,
    build: INIT_BUILD,
    place_id: 12345,
    game_id: GAME_ID,
    user_id: 987654,
    hello,
  }, { headers, ip: opts.ip ?? "203.0.113.10" });
  const res = await dispatch(buildRoutes(), env.ctx, env.config, input);
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
  return {
    sessionToken: parsed.session_token,
    payloadRef: parsed.payload_ref,
    sessionKey,
    sessionIdRaw: b64urlDecode(parsed.session_token),
  };
}

async function sessionWatermark(env: TestEnv, session: ClientSession): Promise<Uint8Array> {
  const row = await env.ctx.db.first<{ watermark_id: string }>(
    "SELECT watermark_id FROM sessions WHERE id = ?",
    [toHex(session.sessionIdRaw)],
  );
  expect(row).not.toBeNull();
  return fromHex(row!.watermark_id);
}

async function postJson(env: TestEnv, path: string, body: Record<string, unknown>, token = ADMIN_TOKEN, ip = "192.0.2.1"): Promise<{ status: number; json: Record<string, unknown> }> {
  const input = await makeSignedInput("POST", path, body, { headers: { authorization: `Bearer ${token}` }, ip });
  const res = await dispatch(buildRoutes(), env.ctx, env.config, input);
  let parsed: Record<string, unknown> = {};
  try {
    parsed = JSON.parse(await res.text()) as Record<string, unknown>;
  } catch {
    /* envelope text */
  }
  return { status: res.status, json: parsed };
}

async function getJson(env: TestEnv, path: string, token = ADMIN_TOKEN): Promise<{ status: number; json: Record<string, unknown> }> {
  const input = await makeSignedInput("GET", path, null, { headers: { authorization: `Bearer ${token}` } });
  const res = await dispatch(buildRoutes(), env.ctx, env.config, input);
  let parsed: Record<string, unknown> = {};
  try {
    parsed = JSON.parse(await res.text()) as Record<string, unknown>;
  } catch {
    /* envelope text */
  }
  return { status: res.status, json: parsed };
}

// ---------------------------------------------------------------------------
// CCP-M6 — per-fetch `s` in the payload-key salt (D-M7-4).
// ---------------------------------------------------------------------------

describe("CCP-M6 per-fetch salt (D-M7-4)", () => {
  let env: TestEnv;
  let key: { plaintext: string; id: string };
  let session: ClientSession;
  let watermark: Uint8Array;

  beforeAll(async () => {
    env = await buildEnv();
    key = await env.createKey({ tier: "paid", days: 30 });
    session = await clientInit(env, { key: key.plaintext });
    watermark = await sessionWatermark(env, session);
  });

  async function fetchPayload(s?: string): Promise<{ status: number; wire: Uint8Array | null; envelope?: { code: string } }> {
    const body: Record<string, unknown> = { v: 1, session_token: session.sessionToken, payload_ref: session.payloadRef };
    if (s !== undefined) body.s = s;
    const input = await makeSignedInput("POST", `/auth/${SCRIPT_ID}/payload`, body);
    const res = await dispatch(buildRoutes(), env.ctx, env.config, input);
    if (res.headers.get("content-type") !== "text/plain") {
      return { status: res.status, wire: null, envelope: (await envelopeOf(res)) as { code: string } };
    }
    return { status: res.status, wire: b64urlDecode(await res.text()) };
  }

  async function openWith(fetchValue: Uint8Array, wire: Uint8Array): Promise<Uint8Array | null> {
    const nonce = wire.subarray(0, 12);
    const ct = wire.subarray(12, wire.length - 16);
    const tag = wire.subarray(wire.length - 16);
    const salt = concatBytes(fromHex(BUILD_HASH), fetchValue);
    const payloadKey = await hkdfSha256(session.sessionKey, salt, concatBytes(utf8("payload-key"), watermark), 32);
    const aad = concatBytes(utf8(SCRIPT_ID), session.sessionIdRaw);
    return aeadOpen(payloadKey, nonce, aad, ct, tag);
  }

  test("absent s → legacy salt (backward compatible: existing clients decrypt)", async () => {
    const r = await fetchPayload();
    expect(r.status).toBe(200);
    expect(r.wire).not.toBeNull();
    const plain = await openWith(new Uint8Array(0), r.wire!);
    expect(plain).not.toBeNull();
  });

  test("present s → new salt (buildHash || s), client that derives it decrypts", async () => {
    const s = randomBytes(24);
    const r = await fetchPayload(b64urlEncode(s));
    expect(r.status).toBe(200);
    expect(r.wire).not.toBeNull();
    const plain = await openWith(s, r.wire!);
    expect(plain).not.toBeNull();
    expect(JSON.parse(new TextDecoder().decode(plain!)).build_hash).toBe(BUILD_HASH);
  });

  test("wrong s → AEAD open fails (a captured bundle is per-fetch useless)", async () => {
    const r = await fetchPayload(b64urlEncode(randomBytes(24)));
    expect(r.status).toBe(200);
    const attacker = await openWith(randomBytes(24), r.wire!);
    expect(attacker).toBeNull();
  });

  test("s longer than 64 decoded bytes → BAD_REQUEST", async () => {
    const r = await fetchPayload(b64urlEncode(randomBytes(65)));
    expect(r.status).toBe(200); // envelope denial, signed
    expect(r.envelope?.code).toBe("BAD_REQUEST");
  });
});

// ---------------------------------------------------------------------------
// §11 tamper ingestion (D-M7-6).
// ---------------------------------------------------------------------------

describe("heartbeat tamper reporting (D-M7-6)", () => {
  let env: TestEnv;
  let key: { plaintext: string; id: string };
  let session: ClientSession;

  beforeAll(async () => {
    env = await buildEnv();
    key = await env.createKey({ tier: "paid", days: 30 });
    session = await clientInit(env, { key: key.plaintext });
  });

  async function heartbeat(body: Record<string, unknown>): Promise<{ code: string; data: Record<string, unknown> | null }> {
    const input = await makeSignedInput("POST", `/auth/${SCRIPT_ID}/heartbeat`, body);
    const res = await dispatch(buildRoutes(), env.ctx, env.config, input);
    return envelopeOf(res);
  }

  test("tamper field records a client:<check> event and answers a normal envelope", async () => {
    const before = await env.ctx.db.first<{ n: number }>(
      "SELECT COUNT(*) AS n FROM events WHERE type = 'tamper'",
      [],
    );
    const out = await heartbeat({
      v: 1,
      session_token: session.sessionToken,
      tamper: { check: "native-request", detail: "identity-changed" },
    });
    expect(out.code).toBe("KEY_VALID");
    const after = await env.ctx.db.first<{ n: number; detail: string | null }>(
      "SELECT COUNT(*) AS n, MAX(detail) AS detail FROM events WHERE type = 'tamper'",
      [],
    );
    expect(after!.n).toBe((before?.n ?? 0) + 1);
    expect(after!.detail).toBe("client:native-request:identity-changed");
  });

  test("malformed tamper (no check) is silently ignored — still KEY_VALID, no event", async () => {
    const before = await env.ctx.db.first<{ n: number }>(
      "SELECT COUNT(*) AS n FROM events WHERE type = 'tamper'",
      [],
    );
    const out = await heartbeat({ v: 1, session_token: session.sessionToken, tamper: { detail: "x".repeat(10) } });
    expect(out.code).toBe("KEY_VALID");
    const after = await env.ctx.db.first<{ n: number }>(
      "SELECT COUNT(*) AS n FROM events WHERE type = 'tamper'",
      [],
    );
    expect(after!.n).toBe(before!.n);
  });

  test("tamper on a dying session (key revoked) still records before the kill check", async () => {
    const session2 = await clientInit(env, { key: key.plaintext });
    await env.ctx.db.run("UPDATE keys SET status = 'revoked' WHERE id = ?", [key.id]);
    const out = await heartbeat({
      v: 1,
      session_token: session2.sessionToken,
      tamper: { check: "timing", detail: "20x-baseline" },
    });
    expect(out.code).toBe("KEY_INVALID"); // kill check fires — but the event landed first
    const row = await env.ctx.db.first<{ detail: string | null }>(
      "SELECT detail FROM events WHERE type = 'tamper' AND detail = 'client:timing:20x-baseline'",
      [],
    );
    expect(row).not.toBeNull();
  });
});

// ---------------------------------------------------------------------------
// §12 leak workflow (D-M7-8).
// ---------------------------------------------------------------------------

describe("leak workflow (D-M7-8)", () => {
  let env: TestEnv;
  let key: { plaintext: string; id: string };
  let session: ClientSession;
  let watermarkHex: string;

  beforeAll(async () => {
    env = await buildEnv();
    key = await env.createKey({ tier: "paid", days: 30, note: "leak-test" });
    session = await clientInit(env, { key: key.plaintext, hwid: "HWID-LEAK-1", ip: "203.0.113.77" });
    watermarkHex = toHex(await sessionWatermark(env, session));
  });

  test("extraction from the sealed payload_ref (clean artifact)", async () => {
    const r = await postJson(env, "/admin/leak/lookup", { artifact: session.payloadRef });
    expect(r.status).toBe(200);
    expect(r.json.watermark_id).toBe(watermarkHex);
    expect(r.json.extraction).toMatchObject({ source: "sealed_ref", script_id: SCRIPT_ID });
    expect((r.json.key as Record<string, unknown>).id).toBe(key.id);
    expect((r.json.key as Record<string, unknown>).note).toBe("leak-test");
    const sessions = r.json.sessions as Array<Record<string, unknown>>;
    expect(sessions.length).toBe(1);
    expect(sessions[0].hwid_hash).toBeTruthy();
    expect(sessions[0].ip_hash).toBeTruthy();
  });

  test("extraction survives reformatting: ref embedded in a messy leaked dump", async () => {
    const messy = `some-attacker-log 2026-10-10T22:14:03Z :: fetch done\n{"loader_version":"x","ref":"${session.payloadRef}","extra":[1,2,3]}\n-- end --`;
    const r = await postJson(env, "/admin/leak/lookup", { artifact: messy });
    expect(r.status).toBe(200);
    expect(r.json.watermark_id).toBe(watermarkHex);
  });

  test("extraction from a session token and from a raw watermark id", async () => {
    const byToken = await postJson(env, "/admin/leak/lookup", { artifact: session.sessionToken });
    expect(byToken.json.extraction).toMatchObject({ source: "session_token" });
    const byId = await postJson(env, "/admin/leak/lookup", { watermark_id: watermarkHex });
    expect(byId.json.watermark_id).toBe(watermarkHex);
  });

  test("no watermark in input → 404 no_watermark", async () => {
    const r = await postJson(env, "/admin/leak/lookup", { artifact: "nothing to see here, move along" });
    expect(r.status).toBe(404);
    expect(r.json.error).toBe("no_watermark");
  });

  test("reseller token cannot use the leak workflow", async () => {
    const r = await postJson(env, "/admin/leak/lookup", { watermark_id: watermarkHex }, RESELLER_TOKEN);
    expect(r.status).toBe(403);
  });

  test("revoke chain: key revoked, hwid+ip blacklisted, sessions killed, audit + leak event", async () => {
    const r = await postJson(env, "/admin/leak/revoke", { watermark_id: watermarkHex });
    expect(r.status).toBe(200);
    expect(r.json.already_revoked).toBe(false);
    expect(r.json.blacklisted).toEqual(["hwid", "ip"]);

    const keyRow = await env.ctx.db.first<{ status: string }>("SELECT status FROM keys WHERE id = ?", [key.id]);
    expect(keyRow!.status).toBe("revoked");

    const bl = await env.ctx.db.all<{ kind: string; reason: string | null }>(
      "SELECT kind, reason FROM blacklist WHERE reason = ?",
      ["leak:" + watermarkHex],
    );
    expect(bl.map((b) => b.kind).sort()).toEqual(["hwid", "ip"]);

    const sess = await env.ctx.db.first<{ expires_at: number }>(
      "SELECT expires_at FROM sessions WHERE id = ?",
      [toHex(session.sessionIdRaw)],
    );
    expect(sess!.expires_at).toBeLessThanOrEqual(Math.floor(Date.now() / 1000) + 1);

    const auditRow = await env.ctx.db.first<{ action: string; target: string | null }>(
      "SELECT action, target FROM audit_log WHERE action = 'admin.leak.revoke' AND target = ?",
      [key.id],
    );
    expect(auditRow).not.toBeNull();

    const leakEvent = await env.ctx.db.first<{ type: string; detail: string | null }>(
      "SELECT type, detail FROM events WHERE type = 'leak' AND key_id = ?",
      [key.id],
    );
    expect(leakEvent).not.toBeNull();
    expect(leakEvent!.detail).toBe("revoke:" + watermarkHex);
  });

  test("revoke is idempotent: second call reports already_revoked, no duplicate blacklist", async () => {
    const r = await postJson(env, "/admin/leak/revoke", { watermark_id: watermarkHex });
    expect(r.status).toBe(200);
    expect(r.json.already_revoked).toBe(true);
    const bl = await env.ctx.db.all<{ kind: string }>(
      "SELECT kind FROM blacklist WHERE reason = ?",
      ["leak:" + watermarkHex],
    );
    expect(bl.length).toBe(2);
  });

  test("revoke with blacklist_hwid=false skips the hwid row", async () => {
    const key2 = await env.createKey({ tier: "paid", days: 30 });
    const s2 = await clientInit(env, { key: key2.plaintext, hwid: "HWID-LEAK-2", ip: "203.0.113.78" });
    const wm2 = toHex(await sessionWatermark(env, s2));
    const r = await postJson(env, "/admin/leak/revoke", { watermark_id: wm2, blacklist_hwid: false });
    expect(r.json.blacklisted).toEqual(["ip"]);
    const bl = await env.ctx.db.all<{ kind: string }>("SELECT kind FROM blacklist WHERE reason = ?", ["leak:" + wm2]);
    expect(bl.map((b) => b.kind)).toEqual(["ip"]);
  });
});

// ---------------------------------------------------------------------------
// §11 abuse scores (D-M7-7).
// ---------------------------------------------------------------------------

describe("abuse scores (D-M7-7)", () => {
  let env: TestEnv;
  let cleanKey: { plaintext: string; id: string };
  let dirtyKey: { plaintext: string; id: string };

  beforeAll(async () => {
    env = await buildEnv();
    cleanKey = await env.createKey({ tier: "paid", days: 30 });
    dirtyKey = await env.createKey({ tier: "paid", days: 30 });

    // Dirty key: 2 client tamper reports (via real heartbeat) + HWID churn
    // (reset + rebind = 2 distinct session HWIDs) + 1 server-side lockout
    // tamper event.
    const s1 = await clientInit(env, { key: dirtyKey.plaintext, hwid: "HWID-DIRTY-A", ip: "198.51.100.1" });
    for (let i = 0; i < 2; i++) {
      const input = await makeSignedInput("POST", `/auth/${SCRIPT_ID}/heartbeat`, {
        v: 1,
        session_token: s1.sessionToken,
        tamper: { check: "env-consistency" },
      });
      await dispatch(buildRoutes(), env.ctx, env.config, input);
    }
    // HWID churn: admin reset, then the key rebinds to a different device —
    // the sessions table now holds 2 distinct hwid_hash values for one key.
    await env.ctx.db.run("UPDATE keys SET hwid_hash = NULL WHERE id = ?", [dirtyKey.id]);
    const s2 = await clientInit(env, { key: dirtyKey.plaintext, hwid: "HWID-DIRTY-B", ip: "198.51.100.2" });
    const hb2 = await makeSignedInput("POST", `/auth/${SCRIPT_ID}/heartbeat`, {
      v: 1,
      session_token: s2.sessionToken,
      tamper: { check: "native-request" },
    });
    await dispatch(buildRoutes(), env.ctx, env.config, hb2);
    // Server-side lockout tamper event.
    await env.ctx.db.run("INSERT INTO events (id, key_id, type, detail, created_at) VALUES (?, ?, 'tamper', 'invalid-key-lockout', ?)", [
      "evt-dirty-lockout", dirtyKey.id, Math.floor(Date.now() / 1000),
    ]);
    // One clean session for the clean key.
    await clientInit(env, { key: cleanKey.plaintext, hwid: "HWID-CLEAN", ip: "198.51.100.9" });
  });

  test("weights and computation: 5*tamper + 3*distinct_hwids + 1*lockout, capped, banded", async () => {
    const r = await getJson(env, "/admin/abuse-scores");
    expect(r.status).toBe(200);
    const scores = r.json.scores as Array<Record<string, unknown>>;
    const dirty = scores.find((s) => s.key_id === dirtyKey.id);
    const clean = scores.find((s) => s.key_id === cleanKey.id);
    expect(dirty).toBeDefined();
    expect(clean).toBeDefined();
    // 3 client tamper events → 15, hwid churn 2→1 extra device → 3, lockout → 1 ⇒ 19 (watch band)
    expect(dirty!.tamper_7d).toBe(3);
    expect(dirty!.distinct_hwids_30d).toBe(2);
    expect(dirty!.hwid_churn_30d).toBe(1);
    expect(dirty!.lockouts_7d).toBe(1);
    expect(dirty!.score).toBe(19);
    expect(dirty!.band).toBe("watch");
    // A key with a single (legitimate) binding scores zero.
    expect(clean!.distinct_hwids_30d).toBe(1);
    expect(clean!.score).toBe(0);
    expect(clean!.band).toBe("clean");
    // Highest score first.
    expect(scores[0].key_id).toBe(dirtyKey.id);
    expect(r.json.weights).toEqual({ tamper_7d: 5, hwid_mismatch_7d: 2, distinct_hwids_30d: 3, lockouts_7d: 1 });
  });

  test("reseller token forbidden", async () => {
    const r = await getJson(env, "/admin/abuse-scores", RESELLER_TOKEN);
    expect(r.status).toBe(403);
  });
});
