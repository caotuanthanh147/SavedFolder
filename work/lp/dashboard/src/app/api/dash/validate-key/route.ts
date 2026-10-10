// POST /api/dash/validate-key — demo utility that exercises the REAL
// /check_key endpoint (module M1) end to end: the browser cannot compute the
// SDK x-proof HMAC (the proof key is a server secret), so this route builds
// the signed request input server-side and returns the signed envelope.

import { NextRequest, NextResponse } from "next/server";
import { b64urlEncode, toHex } from "@api/src/contracts";
import { randomBytes, hmacSha256, sha256Hex, utf8 } from "@api/src/crypto";
import { proofPayload } from "@api/src/flow";
import { buildRoutes, dispatch } from "@api/src/router";
import { RequestInput } from "@api/src/flow";
import { DEMO_SCRIPT_ID, getStore } from "@/server/store";

export async function POST(request: NextRequest): Promise<Response> {
  const store = await getStore();
  let body: Record<string, unknown> | null = null;
  try {
    body = (await request.json()) as Record<string, unknown>;
  } catch {
    body = null;
  }
  const key = typeof body?.key === "string" ? body.key.trim() : "";
  if (key.length === 0 || key.length > 128) {
    return NextResponse.json({ error: "bad_request" }, { status: 400 });
  }

  const now = Math.floor(Date.now() / 1000);
  const nonce = b64urlEncode(randomBytes(16));
  const payloadBody = utf8(JSON.stringify({ key, script_id: DEMO_SCRIPT_ID, lv: "1.0.0" }));
  const proof = toHex(await hmacSha256(store.config.proofKey, proofPayload("POST", "/check_key", String(now), nonce, await sha256Hex(payloadBody))));
  const input: RequestInput = {
    method: "POST",
    path: "/check_key",
    headers: {
      "x-ts": String(now),
      "x-nonce": nonce,
      "x-lv": "1.0.0",
      "x-proof": proof,
    },
    bodyBytes: payloadBody,
    ip: request.headers.get("x-real-ip") ?? "127.0.0.1",
    colo: "DASH",
  };
  return dispatch(buildRoutes(), store.ctx, store.config, input);
}
