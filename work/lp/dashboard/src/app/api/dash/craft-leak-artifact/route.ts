// POST /api/dash/craft-leak-artifact — DEV-ONLY (DASH_DEV_MODE) helper for
// the Leak tools view (module M7): mints a demo key through the REAL admin
// API, runs a REAL /auth/:id/init handshake server-side (a miniature client
// using the api's own crypto — X25519 + HKDF + AEAD open), and returns what
// a leaker would hold: the sealed payload_ref, wrapped in deliberately messy
// text so the tolerant extractor (D-M7-8) is proven end to end in-browser.
// The revoke chain then runs against the SAME session — everything on screen
// is production code.

import { NextRequest, NextResponse } from "next/server";
import { buildRoutes, dispatch } from "@api/src/router";
import { RequestInput, proofPayload } from "@api/src/flow";
import { aeadOpen, concatBytes } from "@api/src/chacha";
import { hkdfSha256, randomBytes, sha256Hex, hmacSha256, utf8 } from "@api/src/crypto";
import { b64urlDecode, b64urlEncode, toHex } from "@api/src/contracts";
import { generateX25519KeyPair, x25519SharedSecret } from "@api/src/x25519";
import { DASH_DEV_MODE, DEMO_PROJECT_ID, DEMO_SCRIPT_ID, getStore } from "@/server/store";

export async function POST(request: NextRequest): Promise<Response> {
  if (!DASH_DEV_MODE) {
    return NextResponse.json({ error: "dev_only" }, { status: 404 });
  }
  let body: Record<string, unknown> = {};
  try {
    body = (await request.json()) as Record<string, unknown>;
  } catch {
    /* no body — defaults */
  }
  void body;
  const store = await getStore();
  const { ctx, config } = store;

  // Fresh demo identity per invocation: a revoke-chain run blacklists this
  // run's hwid+ip hashes, and the next craft must start clean (TEST-NET-2
  // documentation range, so nothing real can collide).
  const demoIp = `198.51.100.${1 + Math.floor(Math.random() * 254)}`;
  const demoHwid = `HWID-LEAK-SIM-${toHex(randomBytes(4))}`;

  async function signed(method: string, path: string, body: Record<string, unknown> | null, headers: Record<string, string> = {}): Promise<Response> {
    const bodyBytes = body !== null ? utf8(JSON.stringify(body)) : new Uint8Array(0);
    const ts = String(Math.floor(ctx.nowSec));
    const nonce = b64urlEncode(randomBytes(16));
    const bodyHashHex = await sha256Hex(bodyBytes);
    const proof = toHex(await hmacSha256(config.proofKey, proofPayload(method, path, ts, nonce, bodyHashHex)));
    const input: RequestInput = {
      method,
      path,
      headers: {
        "x-ts": ts,
        "x-nonce": nonce,
        "x-lv": "1.0.0",
        "x-proof": proof,
        "x-real-ip": "127.0.0.1",
        ...headers,
      },
      bodyBytes,
      ip: demoIp,
      colo: "DASH",
    };
    return dispatch(buildRoutes(), ctx, config, input);
  }

  // 1) Mint a demo key through the REAL admin API.
  const createRes = await signed("POST", "/admin/keys", {
    project_id: DEMO_PROJECT_ID,
    tier: "paid",
    count: 1,
    days: 30,
    note: "leak sim " + new Date(Math.floor(ctx.nowSec) * 1000).toISOString().slice(0, 10),
    script_ids: [DEMO_SCRIPT_ID],
  }, { authorization: `Bearer ${store.devAdminToken}` });
  if (createRes.status !== 201) {
    return NextResponse.json({ error: "key_mint_failed", status: createRes.status }, { status: 500 });
  }
  const created = (await createRes.json()) as { keys: Array<{ id: string; key: string }> };
  const minted = created.keys[0];

  // 2) REAL auth-init handshake (server-side client, same shape as M3's init).
  const client = generateX25519KeyPair(randomBytes(32));
  const clientNonce = randomBytes(16);
  const hello = b64urlEncode(concatBytes(client.publicKey, clientNonce));
  // Bind a HWID so the revoke chain has both an hwid_hash and an ip_hash.
  const initRes = await signed("POST", `/auth/${DEMO_SCRIPT_ID}/init`, {
    v: 1,
    key: minted.key,
    build: "init-b1",
    place_id: 40961328,
    game_id: 40961328,
    user_id: 424242,
    hello,
  }, { "Delta-User-Identifier": demoHwid });
  if (initRes.headers.get("content-type") !== "text/plain") {
    return NextResponse.json({ error: "handshake_failed", status: initRes.status }, { status: 500 });
  }
  const wire = b64urlDecode(await initRes.text());
  const serverPub = wire.subarray(0, 32);
  const serverNonce = wire.subarray(32, 48);
  const ct = wire.subarray(48, wire.length - 16);
  const tag = wire.subarray(wire.length - 16);
  const shared = x25519SharedSecret(client.privateKey, serverPub);
  const sessionKey = await hkdfSha256(shared, concatBytes(clientNonce, serverNonce), utf8("session-key"), 32);
  const aad = concatBytes(utf8(DEMO_SCRIPT_ID), serverPub, serverNonce);
  const plain = aeadOpen(sessionKey, serverNonce.subarray(0, 12), aad, ct, tag);
  if (plain === null) {
    return NextResponse.json({ error: "handshake_decrypt_failed" }, { status: 500 });
  }
  const parsed = JSON.parse(new TextDecoder().decode(plain)) as {
    session_token: string;
    payload_ref: string;
    watermark_id: string;
  };

  // 3) Wrap the sealed ref in deliberately messy leaked-dump text so the
  // browser demo proves the free-text scan (D-M7-8 "survives reformatting").
  const stamp = new Date(Math.floor(ctx.nowSec) * 1000).toISOString();
  const artifact = [
    "-- dump begins --",
    `attacker-notes ${stamp} :: loader cache snapshot`,
    `{"v":2,"session":"${parsed.session_token}","ref":"${parsed.payload_ref}","wm":"${parsed.watermark_id}"}`,
    "garbage padding row that means nothing to the extractor",
    "-- dump ends --",
  ].join("\n");

  return NextResponse.json({
    key_id: minted.id,
    watermark_id: parsed.watermark_id,
    session_token: parsed.session_token,
    payload_ref: parsed.payload_ref,
    artifact,
  });
}
