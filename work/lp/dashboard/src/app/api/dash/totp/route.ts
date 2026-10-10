// TOTP enrollment for the dashboard second factor (doc §16 "optional TOTP").
// Enrollment secrets live in the dashboard's own dash_totp table (CCP-3
// proposes moving them to admins.totp_secret server-side once accepted).
// GET  → status; POST action=enroll → new secret + otpauth URI;
// POST action=verify {code} → enable; POST action=disable {code} → disable.

import { connection, NextRequest, NextResponse } from "next/server";
import { randomBytes } from "@api/src/crypto";
import { base32Decode, base32Encode, otpauthUri, totp, verifyWindow } from "@api/src/totp";
import { DASH_DEV_MODE, getStore } from "@/server/store";

function adminIdOf(store: Awaited<ReturnType<typeof getStore>>, request: NextRequest): string {
  if (DASH_DEV_MODE) return store.devAdminId;
  const auth = request.headers.get("authorization");
  return auth?.startsWith("Bearer adm_") ? auth.slice(9).split(".")[0] : store.devAdminId;
}

export async function GET(request: NextRequest): Promise<Response> {
  await connection();
  const store = await getStore();
  const adminId = adminIdOf(store, request);
  const rows = store.raw.query("SELECT secret_b32, enabled, created_at FROM dash_totp WHERE admin_id = ?", [adminId]) as {
    secret_b32: string;
    enabled: number;
    created_at: number;
  }[];
  const row = rows[0];
  return NextResponse.json({
    enrolled: row !== undefined,
    enabled: row?.enabled === 1,
    created_at: row?.created_at ?? null,
  });
}

export async function POST(request: NextRequest): Promise<Response> {
  const store = await getStore();
  const adminId = adminIdOf(store, request);
  let body: Record<string, unknown> | null = null;
  try {
    body = (await request.json()) as Record<string, unknown>;
  } catch {
    body = null;
  }
  const action = typeof body?.action === "string" ? body.action : "";
  const code = typeof body?.code === "string" ? body.code : "";
  const now = Math.floor(Date.now() / 1000);

  if (action === "enroll") {
    const secret = base32Encode(randomBytes(20));
    store.raw.run("INSERT INTO dash_totp (admin_id, secret_b32, enabled, created_at) VALUES (?, ?, 0, ?) ON CONFLICT(admin_id) DO UPDATE SET secret_b32 = excluded.secret_b32, enabled = 0, created_at = excluded.created_at", [adminId, secret, now]);
    return NextResponse.json({ secret, otpauth_uri: otpauthUri(secret, "Yuri Licensing", "admin") });
  }

  if (action === "verify" || action === "disable") {
    const rows = store.raw.query("SELECT secret_b32, enabled FROM dash_totp WHERE admin_id = ?", [adminId]) as { secret_b32: string; enabled: number }[];
    if (rows.length === 0) return NextResponse.json({ error: "not_enrolled" }, { status: 400 });
    const secret = base32Decode(rows[0].secret_b32);
    const t = Date.now() / 1000;
    const expected = await totp(secret, t);
    const prev = await totp(secret, t - 30);
    const next = await totp(secret, t + 30);
    const ok = verifyWindow(code, expected) || verifyWindow(code, prev) || verifyWindow(code, next);
    if (!ok) return NextResponse.json({ error: "invalid_code" }, { status: 401 });
    if (action === "verify") {
      store.raw.run("UPDATE dash_totp SET enabled = 1 WHERE admin_id = ?", [adminId]);
      return NextResponse.json({ enabled: true });
    }
    store.raw.run("UPDATE dash_totp SET enabled = 0 WHERE admin_id = ?", [adminId]);
    return NextResponse.json({ enabled: false });
  }

  return NextResponse.json({ error: "bad_request" }, { status: 400 });
}
