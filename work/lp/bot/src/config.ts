// M8 — configuration (doc hard rule: no hardcoded secrets or URLs).
// Every value comes from the environment; parseConfig validates and fails
// loud on missing required values. Tests build partial configs directly.
export interface BotConfig {
  /** Discord bot token (owner-held secret). */
  token: string;
  /** Discord application id — needed for command registration. */
  appId: string;
  /** Guild id for guild-scoped command registration + role sync. Null = global commands, no role sync. */
  guildId: string | null;
  /** Admin API base URL (e.g. https://auth.example.net). */
  apiBaseUrl: string;
  /** Admin API bearer token (adm_<id>.<secret>, owner/admin role — doc §15 server-side checks). */
  apiAdminToken: string;
  /** Base URL for loader links (/loaders/<script_id>.lua per M13). Defaults to apiBaseUrl. */
  loaderBase: string;
  /** Free-key page URL (doc §14 flow surface; M9 owns the flow itself). */
  freeUrl: string | null;
  /** Role granted while a linked Discord id holds >= 1 active, unexpired key (D-M8-9). */
  activeRoleId: string | null;
  /** Channel that receives expiry reminders (D-M8-6: never DM). */
  reminderChannelId: string | null;
  /** Days before expiry to include in reminders. */
  reminderLeadDays: number;
  /** Scheduler interval in seconds (hourly per D-M8-10; tests shrink it). */
  schedulerIntervalSec: number;
}

function required(env: Record<string, string | undefined>, name: string): string {
  const v = env[name];
  if (v === undefined || v.length === 0) throw new Error(`missing required config ${name}`);
  return v;
}

function optional(env: Record<string, string | undefined>, name: string): string | null {
  const v = env[name];
  return v === undefined || v.length === 0 ? null : v;
}

function intOr(env: Record<string, string | undefined>, name: string, fallback: number): number {
  const v = env[name];
  if (v === undefined || v.length === 0) return fallback;
  const n = Number.parseInt(v, 10);
  return Number.isFinite(n) && n > 0 ? n : fallback;
}

export function parseConfig(env: Record<string, string | undefined> = process.env): BotConfig {
  const apiBaseUrl = required(env, "LP_BOT_API_URL").replace(/\/+$/, "");
  return {
    token: required(env, "LP_BOT_TOKEN"),
    appId: required(env, "LP_BOT_APP_ID"),
    guildId: optional(env, "LP_BOT_GUILD_ID"),
    apiBaseUrl,
    apiAdminToken: required(env, "LP_BOT_ADMIN_TOKEN"),
    loaderBase: (optional(env, "LP_BOT_LOADER_BASE") ?? apiBaseUrl).replace(/\/+$/, ""),
    freeUrl: optional(env, "LP_BOT_FREE_URL"),
    activeRoleId: optional(env, "LP_BOT_ACTIVE_ROLE_ID"),
    reminderChannelId: optional(env, "LP_BOT_REMINDER_CHANNEL_ID"),
    reminderLeadDays: intOr(env, "LP_BOT_REMINDER_LEAD_DAYS", 3),
    schedulerIntervalSec: intOr(env, "LP_BOT_SCHEDULER_INTERVAL_SEC", 3600),
  };
}
