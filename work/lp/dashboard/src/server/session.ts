// Dashboard session layer (doc §16: Discord OAuth + optional TOTP; the
// admin API token path is the third supported login). Sessions are
// stateless HMAC cookies binding {adminId, expiry} — no server-side store
// needed, per D-M11-3.

import { b64urlEncode } from "@api/src/contracts";
import { hmacSha256, utf8 } from "@api/src/crypto";
import { randomBytes } from "@api/src/crypto";

export const SESSION_COOKIE = "dash_session";
export const SESSION_TTL_SEC = 3600;
export const OAUTH_STATE_COOKIE = "dash_oauth_state";

export interface DashSession {
  adminId: string;
  role: string;
  exp: number;
}

export async function mintSession(adminId: string, role: string, secret: Uint8Array, nowSec: number): Promise<string> {
  const exp = Math.floor(nowSec) + SESSION_TTL_SEC;
  const body = b64urlEncode(utf8(JSON.stringify({ adminId, role, exp })));
  const mac = b64urlEncode(await hmacSha256(secret, utf8(body)));
  return `${body}.${mac}`;
}

export async function readSession(cookie: string | undefined, secret: Uint8Array, nowSec: number): Promise<DashSession | null> {
  if (!cookie) return null;
  const dot = cookie.indexOf(".");
  if (dot < 1) return null;
  const body = cookie.slice(0, dot);
  const mac = cookie.slice(dot + 1);
  const expected = b64urlEncode(await hmacSha256(secret, utf8(body)));
  if (mac.length !== expected.length) return null;
  let same = true;
  for (let i = 0; i < mac.length; i++) {
    if (mac.charCodeAt(i) !== expected.charCodeAt(i)) same = false;
  }
  if (!same) return null;
  try {
    const parsed = JSON.parse(new TextDecoder().decode(
      Uint8Array.from(atob(body.replace(/-/g, "+").replace(/_/g, "/")), (c) => c.charCodeAt(0)),
    )) as DashSession;
    if (typeof parsed.adminId !== "string" || typeof parsed.exp !== "number") return null;
    if (parsed.exp < Math.floor(nowSec)) return null;
    return parsed;
  } catch {
    return null;
  }
}

export function oauthState(): string {
  return b64urlEncode(randomBytes(16));
}
