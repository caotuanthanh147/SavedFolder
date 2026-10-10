// GET /api/dash/oauth/start — begins the Discord OAuth authorization-code
// flow (doc §16). Per Discord's official OAuth2 docs, the state parameter
// binds the request to this browser (CSRF defense): random value, stored in
// an httpOnly cookie, compared on callback. Runtime-gated on env
// (DASH_DISCORD_CLIENT_ID/SECRET); without env the route reports 503.

import { NextRequest, NextResponse } from "next/server";
import { OAUTH_STATE_COOKIE, oauthState } from "@/server/session";
import { getStore } from "@/server/store";

export async function GET(request: NextRequest): Promise<Response> {
  const store = await getStore();
  if (!store.discordConfigured) {
    return NextResponse.json({ error: "discord_not_configured", hint: "set DASH_DISCORD_CLIENT_ID and DASH_DISCORD_CLIENT_SECRET" }, { status: 503 });
  }
  const state = oauthState();
  const redirectUri = new URL("/api/dash/oauth/callback", request.nextUrl.origin).toString();
  const authorize = new URL("https://discord.com/api/oauth2/authorize");
  authorize.searchParams.set("client_id", process.env.DASH_DISCORD_CLIENT_ID!);
  authorize.searchParams.set("redirect_uri", redirectUri);
  authorize.searchParams.set("response_type", "code");
  authorize.searchParams.set("scope", "identify");
  authorize.searchParams.set("state", state);
  const res = NextResponse.redirect(authorize.toString());
  res.cookies.set(OAUTH_STATE_COOKIE, state, { httpOnly: true, sameSite: "lax", path: "/", maxAge: 600 });
  return res;
}
