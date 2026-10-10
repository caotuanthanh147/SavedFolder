// POST /api/dash/login — admin API token (+ TOTP when enrolled) → session
// cookie. Runs the REAL admin authenticate() (owner Q2 token scheme) against
// the same in-process api context the gateway uses.

import { NextRequest, NextResponse } from "next/server";
import { authenticate } from "@api/src/admin";
import { RequestInput } from "@api/src/flow";
import { base32Decode, totp, verifyWindow } from "@api/src/totp";
import { getStore } from "@/server/store";
import { mintSession, SESSION_COOKIE } from "@/server/session";

export async function POST(request: NextRequest): Promise<Response> {
  const store = await getStore();
  let body: Record<string, unknown> | null = null;
  try {
    body = (await request.json()) as Record<string, unknown>;
  } catch {
    body = null;
  }
  const token = typeof body?.token === "string" ? body.token : "";
  const totpCode = typeof body?.totp === "string" ? body.totp : "";
  if (token.length === 0 || token.length > 128) {
    return NextResponse.json({ error: "bad_request" }, { status: 400 });
  }

  const input: RequestInput = {
    method: "POST",
    path: "/admin/audit",
    headers: { authorization: `Bearer ${token}` },
    bodyBytes: new Uint8Array(),
    ip: request.headers.get("x-real-ip") ?? "127.0.0.1",
    colo: "DASH",
  };
  const admin = await authenticate(store.ctx, store.config, input);
  if (!admin) {
    return NextResponse.json({ error: "invalid_token" }, { status: 401 });
  }

  const enrolled = store.raw.query("SELECT secret_b32, enabled FROM dash_totp WHERE admin_id = ? AND enabled = 1", [admin.id]) as {
    secret_b32: string;
    enabled: number;
  }[];
  if (enrolled.length > 0) {
    if (totpCode.length !== 6) {
      return NextResponse.json({ error: "totp_required" }, { status: 401 });
    }
    const now = Date.now() / 1000;
    const expected = await totp(base32Decode(enrolled[0].secret_b32), now);
    const expectedPrev = await totp(base32Decode(enrolled[0].secret_b32), now - 30);
    const expectedNext = await totp(base32Decode(enrolled[0].secret_b32), now + 30);
    if (!verifyWindow(totpCode, expected) && !verifyWindow(totpCode, expectedPrev) && !verifyWindow(totpCode, expectedNext)) {
      return NextResponse.json({ error: "invalid_totp" }, { status: 401 });
    }
  }

  const cookie = await mintSession(admin.id, admin.role, store.dashboardSessionSecret, Date.now() / 1000);
  const res = NextResponse.json({ ok: true, role: admin.role, totp: enrolled.length > 0 });
  res.cookies.set(SESSION_COOKIE, cookie, { httpOnly: true, sameSite: "lax", path: "/", maxAge: 3600 });
  return res;
}
