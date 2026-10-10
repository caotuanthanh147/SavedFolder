// GET /api/dash/oauth/callback — exchanges the authorization code, reads the
// Discord user, and signs the dashboard in when the Discord ID is linked to
// an admins row (doc §16 auth). State cookie is compared first (CSRF per
// Discord OAuth2 docs). Runtime-gated on env like /start.

import { NextRequest, NextResponse } from "next/server";
import { OAUTH_STATE_COOKIE, SESSION_COOKIE, mintSession } from "@/server/session";
import { getStore } from "@/server/store";

interface DiscordUser {
  id: string;
  username: string;
}

export async function GET(request: NextRequest): Promise<Response> {
  const store = await getStore();
  if (!store.discordConfigured) {
    return NextResponse.json({ error: "discord_not_configured" }, { status: 503 });
  }
  const code = request.nextUrl.searchParams.get("code");
  const state = request.nextUrl.searchParams.get("state");
  const expectedState = request.cookies.get(OAUTH_STATE_COOKIE)?.value;
  if (!code || !state || !expectedState || state !== expectedState) {
    return NextResponse.json({ error: "invalid_state" }, { status: 400 });
  }

  const redirectUri = new URL("/api/dash/oauth/callback", request.nextUrl.origin).toString();
  const tokenRes = await fetch("https://discord.com/api/oauth2/token", {
    method: "POST",
    headers: { "content-type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      client_id: process.env.DASH_DISCORD_CLIENT_ID!,
      client_secret: process.env.DASH_DISCORD_CLIENT_SECRET!,
      grant_type: "authorization_code",
      code,
      redirect_uri: redirectUri,
    }),
  });
  if (!tokenRes.ok) {
    return NextResponse.json({ error: "token_exchange_failed" }, { status: 401 });
  }
  const token = (await tokenRes.json()) as { access_token?: string };
  if (!token.access_token) {
    return NextResponse.json({ error: "token_exchange_failed" }, { status: 401 });
  }
  const userRes = await fetch("https://discord.com/api/users/@me", {
    headers: { authorization: `Bearer ${token.access_token}` },
  });
  if (!userRes.ok) {
    return NextResponse.json({ error: "user_fetch_failed" }, { status: 401 });
  }
  const user = (await userRes.json()) as DiscordUser;

  const admin = store.raw.query("SELECT id, role FROM admins WHERE discord_id = ?", [user.id]) as { id: string; role: string }[];
  if (admin.length === 0) {
    return NextResponse.json({ error: "not_linked", hint: `link discord id ${user.id} to an admins row first` }, { status: 403 });
  }

  const cookie = await mintSession(admin[0].id, admin[0].role, store.dashboardSessionSecret, Date.now() / 1000);
  const res = NextResponse.redirect(new URL("/", request.nextUrl.origin).toString());
  res.cookies.set(SESSION_COOKIE, cookie, { httpOnly: true, sameSite: "lax", path: "/", maxAge: 3600 });
  res.cookies.set(OAUTH_STATE_COOKIE, "", { httpOnly: true, path: "/", maxAge: 0 });
  return res;
}
