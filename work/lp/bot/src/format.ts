// M8 — shared formatting + the minimal reply shapes handlers produce.
// index.ts adapts these to discord.js payloads; tests assert them directly.
export interface BotField {
  name: string;
  value: string;
  inline?: boolean;
}

export interface BotEmbed {
  title?: string;
  description?: string;
  fields: BotField[];
}

export interface BotReply {
  content?: string;
  embed?: BotEmbed;
  /** Message flag bit 64 = EPHEMERAL (RESEARCH-M8 row 4). */
  ephemeral: boolean;
}

export function maskKeyId(id: string): string {
  return id.slice(0, 8);
}

export function fmtDate(unixSec: number, nowSec: number): string {
  const d = new Date(unixSec * 1000);
  const iso = d.toISOString().slice(0, 10);
  const days = Math.ceil((unixSec - nowSec) / 86400);
  return `${iso} (${days >= 0 ? `in ${days}d` : `${-days}d ago`})`;
}

export function fmtExpiry(expiresAt: number | null, nowSec: number): string {
  return expiresAt === null ? "lifetime" : fmtDate(expiresAt, nowSec);
}

export function errorText(err: { status: number; error: string | { error: string; field?: string; retry_after_sec?: number } }): string {
  const e = typeof err.error === "string" ? { error: err.error } : err.error;
  switch (e.error) {
    case "unauthorized":
      return "Admin API rejected the bot token (unauthorized).";
    case "forbidden":
      return "The bot's admin token lacks the required role (forbidden).";
    case "not_found":
      return "Not found.";
    case "already_linked":
      return "That key is already linked to a different Discord account.";
    case "blacklisted":
      return "This Discord account is blacklisted.";
    case "RATE_LIMITED":
      return `HWID reset cooldown active — retry in ${e.retry_after_sec ?? 0} seconds.`;
    case "monthly_cap_exceeded":
      return "Monthly HWID reset cap reached for this key.";
    case "quota_exceeded":
      return "Reseller quota exceeded.";
    case "network":
      return "Admin API unreachable.";
    default:
      return `Admin API error (${err.status}${e.field !== undefined ? `, field: ${e.field}` : ""}).`;
  }
}

export const GENERIC_FAILURE = "Something went wrong handling that command. Try again later.";
