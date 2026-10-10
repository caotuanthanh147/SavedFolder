import { beforeAll, describe, expect, test } from "bun:test";
import {
  BUNDLE_REF,
  BUILD_HASH,
  GAME_ID,
  INIT_BUILD,
  PEPPER,
  PROJECT_ID,
  SCRIPT_ID,
  TestEnv,
  buildEnv,
  envelopeOf,
  makeSignedInput,
} from "./helpers";
import { buildRoutes, dispatch } from "../src/router";
import { b64urlDecode, b64urlEncode, fromHex, toHex } from "../src/contracts";
import { hkdfSha256, randomBytes, sha256Hex, utf8 } from "../src/crypto";
import { aeadOpen } from "../src/chacha";
import { concatBytes } from "../src/chacha";
import { generateX25519KeyPair, x25519SharedSecret } from "../src/x25519";
import { projectHwidSalt, hashHwid } from "../src/keys";

// A miniature second implementation of the client side (what M3's init does
// in Lua): derive the session key from the handshake, decrypt the response,
// derive the payload key, decrypt the payload, verify bundle_sig with the
// Ed25519 public key. This is the cross-implementation check doc.md §9
// requires (TS encrypts, an independent code path decrypts).

interface ClientSession {
  sessionToken: string;
  sessionExpiresAt: number;
  tier: string;
  authExpire: number;
  payloadRef: string;
  sessionKey: Uint8Array;
  sessionIdRaw: Uint8Array;
}

async function clientInit(
  env: TestEnv,
  opts: { key?: string; build?: string; gameId?: number; userId?: number; placeId?: number; hwidHeader?: [string, string] | null; ip?: string; fail?: boolean } = {},
): Promise<{ status: number; session?: ClientSession; envelope?: { code: string; data: Record<string, unknown> | null } }> {
  const client = generateX25519KeyPair(randomBytes(32));
  const clientNonce = randomBytes(16);
  const hello = b64urlEncode(concatBytes(client.publicKey, clientNonce));
  const body = {
    v: 1,
    key: opts.key ?? "",
    build: opts.build ?? INIT_BUILD,
    place_id: opts.placeId ?? 12345,
    game_id: opts.gameId ?? GAME_ID,
    user_id: opts.userId ?? 987654,
    hello,
  };
  const headers: Record<string, string> = {};
  if (opts.hwidHeader) headers[opts.hwidHeader[0]] = opts.hwidHeader[1];
  const input = await makeSignedInput("POST", `/auth/${SCRIPT_ID}/init`, body, {
    headers,
    ip: opts.ip ?? "203.0.113.10",
  });
  const res = await dispatch(buildRoutes(), env.ctx, env.config, input);
  if (res.headers.get("content-type") !== "text/plain") {
    return { status: res.status, envelope: await envelopeOf(res) };
  }
  const wire = b64urlDecode(await res.text());
  expect(wire.length).toBeGreaterThan(32 + 16 + 16);
  const serverPub = wire.subarray(0, 32);
  const serverNonce = wire.subarray(32, 48);
  const ct = wire.subarray(48, wire.length - 16);
  const tag = wire.subarray(wire.length - 16);
  const shared = x25519SharedSecret(client.privateKey, serverPub);
  const sessionKey = await hkdfSha256(shared, concatBytes(clientNonce, serverNonce), utf8("session-key"), 32);
  const aad = concatBytes(utf8(SCRIPT_ID), serverPub, serverNonce);
  const plain = aeadOpen(sessionKey, serverNonce.subarray(0, 12), aad, ct, tag);
  expect(plain).not.toBeNull();
  const parsed = JSON.parse(new TextDecoder().decode(plain!)) as {
    session_token: string;
    session_expires_at: number;
    tier: string;
    auth_expire: number;
    payload_ref: string;
  };
  return {
    status: res.status,
    session: {
      sessionToken: parsed.session_token,
      sessionExpiresAt: parsed.session_expires_at,
      tier: parsed.tier,
      authExpire: parsed.auth_expire,
      payloadRef: parsed.payload_ref,
      sessionKey,
      sessionIdRaw: b64urlDecode(parsed.session_token),
    },
  };
}

async function clientPayload(env: TestEnv, session: ClientSession): Promise<{ status: number; payload?: { buildHash: string; bundle: Uint8Array; bundleSig: Uint8Array }; envelope?: { code: string } }> {
  const body = { v: 1, session_token: session.sessionToken, payload_ref: session.payloadRef };
  const input = await makeSignedInput("POST", `/auth/${SCRIPT_ID}/payload`, body);
  const res = await dispatch(buildRoutes(), env.ctx, env.config, input);
  if (res.headers.get("content-type") !== "text/plain") {
    return { status: res.status, envelope: await envelopeOf(res) };
  }
  const wire = b64urlDecode(await res.text());
  const nonce = wire.subarray(0, 12);
  const ct = wire.subarray(12, wire.length - 16);
  const tag = wire.subarray(wire.length - 16);
  const buildHashRaw = fromHex(BUILD_HASH);
  const watermark = await lookupWatermark(env, session);
  const payloadKey = await hkdfSha256(session.sessionKey, buildHashRaw, concatBytes(utf8("payload-key"), watermark), 32);
  const aad = concatBytes(utf8(SCRIPT_ID), session.sessionIdRaw);
  const plain = aeadOpen(payloadKey, nonce, aad, ct, tag);
  expect(plain).not.toBeNull();
  const parsed = JSON.parse(new TextDecoder().decode(plain!)) as { build_hash: string; bundle: string; bundle_sig: string };
  return {
    status: res.status,
    payload: {
      buildHash: parsed.build_hash,
      bundle: b64urlDecode(parsed.bundle),
      bundleSig: b64urlDecode(parsed.bundle_sig),
    },
  };
}

async function lookupWatermark(env: TestEnv, session: ClientSession): Promise<Uint8Array> {
  const row = await env.ctx.db.first<{ watermark_id: string }>(
    "SELECT watermark_id FROM sessions WHERE id = ?",
    [toHex(session.sessionIdRaw)],
  );
  expect(row).not.toBeNull();
  return fromHex(row!.watermark_id);
}

async function heartbeat(env: TestEnv, session: ClientSession): Promise<{ code: string; data: Record<string, unknown> | null }> {
  const input = await makeSignedInput("POST", `/auth/${SCRIPT_ID}/heartbeat`, {
    v: 1,
    session_token: session.sessionToken,
  });
  const res = await dispatch(buildRoutes(), env.ctx, env.config, input);
  return envelopeOf(res);
}

let env: TestEnv;
let key: { plaintext: string; id: string };

beforeAll(async () => {
  env = await buildEnv();
  key = await env.createKey({ tier: "paid", days: 30, note: "hello key" });
});

describe("auth init happy path", () => {
  test("full handshake: key valid → session created, wire decryptable, fields correct", async () => {
    const result = await clientInit(env, { key: key.plaintext, hwidHeader: ["Delta-User-Identifier", "HWID-AAA"] });
    expect(result.status).toBe(200);
    expect(result.session).toBeDefined();
    const s = result.session!;
    expect(s.tier).toBe("paid");
    expect(s.authExpire).toBeGreaterThan(0);
    expect(s.sessionExpiresAt).toBeGreaterThan(Date.now() / 1000);
    expect(s.payloadRef.length).toBeGreaterThan(40);
    expect(s.sessionIdRaw.length).toBe(16);
    const row = await env.ctx.db.first<{ id: string; key_id: string; watermark_id: string; hwid_hash: string; roblox_user_id: number; script_id: string; version: number }>(
      "SELECT id, key_id, watermark_id, hwid_hash, roblox_user_id, script_id, version FROM sessions WHERE id = ?",
      [toHex(s.sessionIdRaw)],
    );
    expect(row).not.toBeNull();
    expect(row!.key_id).toBe(key.id);
    expect(row!.script_id).toBe(SCRIPT_ID);
    expect(row!.roblox_user_id).toBe(987654);
    expect(row!.version).toBe(1);
    expect(row!.watermark_id).toMatch(/^[0-9a-f]{32}$/);
    const salt = await projectHwidSalt(PEPPER, PROJECT_ID);
    expect(row!.hwid_hash).toBe(await hashHwid("HWID-AAA", salt));
  });

  test("session response header carries x-ts; body is base64url text", async () => {
    const input = await makeSignedInput("POST", `/auth/${SCRIPT_ID}/init`, {
      v: 1,
      key: key.plaintext,
      build: INIT_BUILD,
      place_id: 1,
      game_id: GAME_ID,
      user_id: 1,
      hello: b64urlEncode(concatBytes(generateX25519KeyPair(randomBytes(32)).publicKey, randomBytes(16))),
    });
    const res = await dispatch(buildRoutes(), env.ctx, env.config, input);
    expect(res.status).toBe(200);
    expect(res.headers.get("content-type")).toBe("text/plain");
    expect(res.headers.get("x-ts")).not.toBeNull();
    expect(/^[A-Za-z0-9_-]+$/.test(await res.text())).toBe(true);
  });
});

describe("auth init failure matrix", () => {
  test("missing key on a keyed script → KEY_INVALID", async () => {
    const r = await clientInit(env, {});
    expect(r.envelope?.code).toBe("KEY_INVALID");
  });

  test("unknown key → KEY_INVALID + lockout counting", async () => {
    const r = await clientInit(env, { key: "YURI-AAAAA-BBBBB-CCCCC-DDDDDE" });
    expect(r.envelope?.code).toBe("KEY_INVALID");
  });

  test("5 invalid keys in 10 min → RATE_LIMITED before lookup", async () => {
    const bad = "YURI-AAAAA-BBBBB-CCCCC-DDDDDE";
    for (let i = 0; i < 5; i++) {
      await clientInit(env, { key: bad, ip: "203.0.113.99" });
    }
    const r = await clientInit(env, { key: bad, ip: "203.0.113.99" });
    expect(r.envelope?.code).toBe("RATE_LIMITED");
  });

  test("wrong game (script routed) → SCRIPT_NOT_ALLOWED", async () => {
    const r = await clientInit(env, { key: key.plaintext, gameId: 999999 });
    expect(r.envelope?.code).toBe("SCRIPT_NOT_ALLOWED");
  });

  test("unknown script id → SCRIPT_NOT_ALLOWED envelope", async () => {
    const hello = b64urlEncode(concatBytes(generateX25519KeyPair(randomBytes(32)).publicKey, randomBytes(16)));
    const input = await makeSignedInput("POST", "/auth/99999999999999999999999999999999/init", {
      v: 1, key: key.plaintext, build: INIT_BUILD, place_id: 1, game_id: GAME_ID, user_id: 1, hello,
    });
    const res = await dispatch(buildRoutes(), env.ctx, env.config, input);
    expect((await envelopeOf(res)).code).toBe("SCRIPT_NOT_ALLOWED");
  });

  test("hello not 48 bytes → BAD_REQUEST", async () => {
    const input = await makeSignedInput("POST", `/auth/${SCRIPT_ID}/init`, {
      v: 1, key: key.plaintext, build: INIT_BUILD, place_id: 1, game_id: GAME_ID, user_id: 1, hello: b64urlEncode(randomBytes(10)),
    });
    const res = await dispatch(buildRoutes(), env.ctx, env.config, input);
    expect((await envelopeOf(res)).code).toBe("BAD_REQUEST");
  });

  test("all-zero client public key → BAD_REQUEST", async () => {
    const input = await makeSignedInput("POST", `/auth/${SCRIPT_ID}/init`, {
      v: 1, key: key.plaintext, build: INIT_BUILD, place_id: 1, game_id: GAME_ID, user_id: 1,
      hello: b64urlEncode(concatBytes(new Uint8Array(32), randomBytes(16))),
    });
    const res = await dispatch(buildRoutes(), env.ctx, env.config, input);
    expect((await envelopeOf(res)).code).toBe("BAD_REQUEST");
  });

  test("wrong init build → UPDATE_REQUIRED", async () => {
    const r = await clientInit(env, { key: key.plaintext, build: "init-OLD" });
    expect(r.envelope?.code).toBe("UPDATE_REQUIRED");
  });

  test("v != 1 → BAD_REQUEST", async () => {
    const hello = b64urlEncode(concatBytes(generateX25519KeyPair(randomBytes(32)).publicKey, randomBytes(16)));
    const input = await makeSignedInput("POST", `/auth/${SCRIPT_ID}/init`, {
      v: 2, key: key.plaintext, build: INIT_BUILD, place_id: 1, game_id: GAME_ID, user_id: 1, hello,
    });
    const res = await dispatch(buildRoutes(), env.ctx, env.config, input);
    expect((await envelopeOf(res)).code).toBe("BAD_REQUEST");
  });

  test("stale x-ts → BAD_REQUEST envelope", async () => {
    const hello = b64urlEncode(concatBytes(generateX25519KeyPair(randomBytes(32)).publicKey, randomBytes(16)));
    const input = await makeSignedInput("POST", `/auth/${SCRIPT_ID}/init`, {
      v: 1, key: key.plaintext, build: INIT_BUILD, place_id: 1, game_id: GAME_ID, user_id: 1, hello,
    }, { ts: Math.floor(Date.now() / 1000) - 3600 });
    const res = await dispatch(buildRoutes(), env.ctx, env.config, input);
    expect((await envelopeOf(res)).code).toBe("BAD_REQUEST");
  });

  test("replayed nonce → BAD_REQUEST", async () => {
    const hello = b64urlEncode(concatBytes(generateX25519KeyPair(randomBytes(32)).publicKey, randomBytes(16)));
    const body = { v: 1, key: key.plaintext, build: INIT_BUILD, place_id: 1, game_id: GAME_ID, user_id: 1, hello };
    const first = await makeSignedInput("POST", `/auth/${SCRIPT_ID}/init`, body);
    await dispatch(buildRoutes(), env.ctx, env.config, first);
    const replay = await makeSignedInput("POST", `/auth/${SCRIPT_ID}/init`, body, { nonce: first.headers["x-nonce"] });
    const res = await dispatch(buildRoutes(), env.ctx, env.config, replay);
    expect((await envelopeOf(res)).code).toBe("BAD_REQUEST");
  });

  test("blacklisted roblox user → KEY_BLACKLISTED", async () => {
    const userHash = await sha256Hex(PEPPER + "|roblox_user|55555");
    await env.db.prepare("INSERT INTO blacklist (id, kind, value_hash, reason, created_by, created_at) VALUES (?, 'roblox_user', ?, NULL, 'test', ?)").run("bl-user-1", userHash, Math.floor(Date.now() / 1000));
    const r = await clientInit(env, { key: key.plaintext, userId: 55555 });
    expect(r.envelope?.code).toBe("KEY_BLACKLISTED");
  });

  test("blacklisted hwid → KEY_BLACKLISTED", async () => {
    const salt = await projectHwidSalt(PEPPER, PROJECT_ID);
    const hwidHash = await hashHwid("EVIL-HWID", salt);
    await env.db.prepare("INSERT INTO blacklist (id, kind, value_hash, reason, created_by, created_at) VALUES (?, 'hwid', ?, NULL, 'test', ?)").run("bl-hwid-1", hwidHash, Math.floor(Date.now() / 1000));
    const r = await clientInit(env, { key: key.plaintext, hwidHeader: ["Delta-User-Identifier", "EVIL-HWID"] });
    expect(r.envelope?.code).toBe("KEY_BLACKLISTED");
  });

  test("hwid mismatch: key bound to another device → HWID_MISMATCH", async () => {
    const ownKey = await env.createKey({});
    const first = await clientInit(env, { key: ownKey.plaintext, hwidHeader: ["Delta-User-Identifier", "HWID-ONE"] });
    expect(first.session).toBeDefined();
    const second = await clientInit(env, { key: ownKey.plaintext, hwidHeader: ["Delta-User-Identifier", "HWID-TWO"] });
    expect(second.envelope?.code).toBe("HWID_MISMATCH");
  });
});

describe("auth payload", () => {
  test("full payload decrypt + bundle_sig verifies with the project Ed25519 public key", async () => {
    const s = (await clientInit(env, { key: key.plaintext, hwidHeader: ["Delta-User-Identifier", "HWID-AAA"] })).session!;
    const r = await clientPayload(env, s);
    expect(r.status).toBe(200);
    const p = r.payload!;
    expect(p.buildHash).toBe(BUILD_HASH);
    expect(new TextDecoder().decode(p.bundle)).toBe("-- protected script bundle bytes v1");
    const ok = await env.verifier.verify(concatBytes(fromHex(p.buildHash), p.bundle), p.bundleSig);
    expect(ok).toBe(true);
  });

  test("payload for session of another script token → KEY_INVALID (token/ref binding)", async () => {
    const s = (await clientInit(env, { key: key.plaintext })).session!;
    const input = await makeSignedInput("POST", `/auth/${SCRIPT_ID}/payload`, {
      v: 1,
      session_token: b64urlEncode(randomBytes(16)),
      payload_ref: s.payloadRef,
    });
    const res = await dispatch(buildRoutes(), env.ctx, env.config, input);
    expect((await envelopeOf(res)).code).toBe("KEY_INVALID");
  });

  test("tampered payload_ref byte → BAD_REQUEST", async () => {
    const s = (await clientInit(env, { key: key.plaintext })).session!;
    const refBytes = b64urlDecode(s.payloadRef);
    refBytes[refBytes.length - 1] ^= 0x01;
    const input = await makeSignedInput("POST", `/auth/${SCRIPT_ID}/payload`, {
      v: 1,
      session_token: s.sessionToken,
      payload_ref: b64urlEncode(refBytes),
    });
    const res = await dispatch(buildRoutes(), env.ctx, env.config, input);
    expect((await envelopeOf(res)).code).toBe("BAD_REQUEST");
  });

  test("revoked key kills the session at payload time", async () => {
    const revoked = await env.createKey({});
    const s = (await clientInit(env, { key: revoked.plaintext })).session!;
    await env.db.prepare("UPDATE keys SET status = 'revoked' WHERE id = ?").run(revoked.id);
    const input = await makeSignedInput("POST", `/auth/${SCRIPT_ID}/payload`, {
      v: 1, session_token: s.sessionToken, payload_ref: s.payloadRef,
    });
    const res = await dispatch(buildRoutes(), env.ctx, env.config, input);
    expect((await envelopeOf(res)).code).toBe("KEY_INVALID");
  });

  test("expired session (now past ref expiry) → KEY_EXPIRED", async () => {
    const s = (await clientInit(env, { key: key.plaintext })).session!;
    const future = Date.now() / 1000 + 7200;
    const saved = env.ctx.nowSec;
    env.ctx.nowSec = future;
    const input = await makeSignedInput("POST", `/auth/${SCRIPT_ID}/payload`, {
      v: 1, session_token: s.sessionToken, payload_ref: s.payloadRef,
    }, { ts: Math.floor(future) });
    const res = await dispatch(buildRoutes(), env.ctx, env.config, input);
    env.ctx.nowSec = saved;
    expect((await envelopeOf(res)).code).toBe("KEY_EXPIRED");
  });

  test("missing bundle in the store → SERVER_ERROR", async () => {
    const s = (await clientInit(env, { key: key.plaintext })).session!;
    env.blobs.delete(BUNDLE_REF);
    try {
      const input = await makeSignedInput("POST", `/auth/${SCRIPT_ID}/payload`, {
        v: 1, session_token: s.sessionToken, payload_ref: s.payloadRef,
      });
      const res = await dispatch(buildRoutes(), env.ctx, env.config, input);
      expect((await envelopeOf(res)).code).toBe("SERVER_ERROR");
    } finally {
      env.blobs.put(BUNDLE_REF, utf8("-- protected script bundle bytes v1"));
    }
  });

  test("6th payload fetch within a minute → RATE_LIMITED", async () => {
    const s = (await clientInit(env, { key: key.plaintext })).session!;
    for (let i = 0; i < 5; i++) {
      const r = await clientPayload(env, s);
      expect(r.status).toBe(200);
    }
    const input = await makeSignedInput("POST", `/auth/${SCRIPT_ID}/payload`, {
      v: 1, session_token: s.sessionToken, payload_ref: s.payloadRef,
    });
    const res = await dispatch(buildRoutes(), env.ctx, env.config, input);
    expect((await envelopeOf(res)).code).toBe("RATE_LIMITED");
  });
});

describe("auth heartbeat", () => {
  test("live session → KEY_VALID with session_expires_at", async () => {
    const s = (await clientInit(env, { key: key.plaintext })).session!;
    const r = await heartbeat(env, s);
    expect(r.code).toBe("KEY_VALID");
    expect(r.data?.session_expires_at).toBe(s.sessionExpiresAt);
  });

  test("revoked key → kill code at heartbeat", async () => {
    const revoked = await env.createKey({});
    const s = (await clientInit(env, { key: revoked.plaintext })).session!;
    await env.db.prepare("UPDATE keys SET status = 'revoked' WHERE id = ?").run(revoked.id);
    const r = await heartbeat(env, s);
    expect(r.code).toBe("KEY_INVALID");
  });

  test("unknown session token → KEY_INVALID", async () => {
    const input = await makeSignedInput("POST", `/auth/${SCRIPT_ID}/heartbeat`, {
      v: 1, session_token: b64urlEncode(randomBytes(16)),
    });
    const res = await dispatch(buildRoutes(), env.ctx, env.config, input);
    expect((await envelopeOf(res)).code).toBe("KEY_INVALID");
  });
});

describe("keyless script auth", () => {
  test("keyless init + payload without any key", async () => {
    await env.db.prepare("INSERT INTO scripts (id, project_id, name, keyless, active_version, created_at) VALUES (?, ?, 'FreeTool', 1, 1, ?)").run("55555555555555555555555555555555", PROJECT_ID, Math.floor(Date.now() / 1000));
    await env.db.prepare("INSERT INTO script_versions (script_id, version, blob_ref, build_hash, init_build, notes, created_at) VALUES (?, 1, ?, ?, ?, NULL, ?)").run("55555555555555555555555555555555", "bundle/v1/keyless", "cd".repeat(32), "init-k1", Math.floor(Date.now() / 1000));
    env.blobs.put("bundle/v1/keyless", utf8("-- keyless bundle"));
    const client = generateX25519KeyPair(randomBytes(32));
    const hello = b64urlEncode(concatBytes(client.publicKey, randomBytes(16)));
    const input = await makeSignedInput("POST", "/auth/55555555555555555555555555555555/init", {
      v: 1, key: "", build: "init-k1", place_id: 1, game_id: 1, user_id: 1, hello,
    });
    const res = await dispatch(buildRoutes(), env.ctx, env.config, input);
    expect(res.headers.get("content-type")).toBe("text/plain");
    const wire = b64urlDecode(await res.text());
    const serverPub = wire.subarray(0, 32);
    const serverNonce = wire.subarray(32, 48);
    const shared = x25519SharedSecret(client.privateKey, serverPub);
    const sessionKey = await hkdfSha256(shared, concatBytes(b64urlDecode(hello).subarray(32, 48), serverNonce), utf8("session-key"), 32);
    const plain = aeadOpen(sessionKey, serverNonce.subarray(0, 12), concatBytes(utf8("55555555555555555555555555555555"), serverPub, serverNonce), wire.subarray(48, wire.length - 16), wire.subarray(wire.length - 16));
    expect(plain).not.toBeNull();
    const parsed = JSON.parse(new TextDecoder().decode(plain!));
    expect(parsed.tier).toBe("free");
    expect(parsed.auth_expire).toBe(0);
  });
});


describe("protocol version gate (owner Q1 semantics)", () => {
  test("retiring the client's protocol version kills auth init → UPDATE_REQUIRED", async () => {
    await env.db.prepare("UPDATE protocol_versions SET active = 0 WHERE version = '1'").run();
    const r = await clientInit(env, { key: key.plaintext });
    expect(r.envelope?.code).toBe("UPDATE_REQUIRED");
    await env.db.prepare("UPDATE protocol_versions SET active = 1 WHERE version = '1'").run();
  });

  test("raising min_loader above the client loader version → UPDATE_REQUIRED", async () => {
    await env.db.prepare("UPDATE protocol_versions SET min_loader = '9.9.9' WHERE version = '1'").run();
    const r = await clientInit(env, { key: key.plaintext });
    expect(r.envelope?.code).toBe("UPDATE_REQUIRED");
    await env.db.prepare("UPDATE protocol_versions SET min_loader = '1.0.0' WHERE version = '1'").run();
  });

  test("retiring every protocol row kills check_key → UPDATE_REQUIRED", async () => {
    const created = await env.createKey({});
    await env.db.prepare("UPDATE protocol_versions SET active = 0").run();
    const input = await makeSignedInput("POST", "/check_key", {
      key: created.plaintext, script_id: SCRIPT_ID, lv: "1.0.0",
    });
    const res = await dispatch(buildRoutes(), env.ctx, env.config, input);
    expect((await envelopeOf(res)).code).toBe("UPDATE_REQUIRED");
    await env.db.prepare("UPDATE protocol_versions SET active = 1").run();
  });

  test("raising one row's min_loader gates check_key to the least-strict active row", async () => {
    const created = await env.createKey({});
    await env.db.prepare("INSERT INTO protocol_versions (version, handler, min_loader, active) VALUES ('5', 'v5', '9.9.9', 1)").run();
    const input = await makeSignedInput("POST", "/check_key", {
      key: created.plaintext, script_id: SCRIPT_ID, lv: "1.0.0",
    });
    const res = await dispatch(buildRoutes(), env.ctx, env.config, input);
    expect((await envelopeOf(res)).code).toBe("KEY_VALID");
    await env.db.prepare("DELETE FROM protocol_versions WHERE version = '5'").run();
  });
});

describe("watermark uniqueness (doc §12)", () => {
  test("two sessions get distinct watermark ids mapping to the same key", async () => {
    const s1 = (await clientInit(env, { key: key.plaintext })).session!;
    const s2 = (await clientInit(env, { key: key.plaintext })).session!;
    const w1 = await lookupWatermark(env, s1);
    const w2 = await lookupWatermark(env, s2);
    expect(Buffer.from(w1).toString("hex")).not.toBe(Buffer.from(w2).toString("hex"));
  });
});
