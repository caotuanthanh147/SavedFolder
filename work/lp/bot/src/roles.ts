// M8 — role sync (doc §15: "Roles are granted for active keys and removed
// on expiry or revoke"). Discord REST surface is narrow + injectable so
// tests can fake it; the production adapter wraps discord.js REST calls
// (PUT/DELETE /guilds/:gid/members/:uid/roles/:rid — RESEARCH-M8 row 9).
import { AdminApi, KeyRow } from "./adminapi";
import { BotConfig } from "./config";

export type RoleOpResult = "granted" | "removed" | "noop" | "no_role_config" | "no_guild" | "error";

export interface GuildRolePort {
  addRole(userId: string): Promise<RoleOpResult>;
  removeRole(userId: string): Promise<RoleOpResult>;
}

export class NoopRolePort implements GuildRolePort {
  async addRole(): Promise<RoleOpResult> {
    return "noop";
  }
  async removeRole(): Promise<RoleOpResult> {
    return "noop";
  }
}

/** True when the key grants membership right now (status active AND not expired). */
export function keyGrantsRole(key: KeyRow, nowSec: number): boolean {
  return key.status === "active" && (key.expires_at === null || key.expires_at > nowSec);
}

export class RoleSync {
  constructor(
    private readonly api: AdminApi,
    private readonly roles: GuildRolePort,
    private readonly config: Pick<BotConfig, "activeRoleId" | "guildId">,
    private readonly now: () => number = () => Date.now() / 1000,
  ) {}

  /** Grant the active-key role if the user currently holds an active, unexpired key. */
  async grantIfActive(discordId: string): Promise<RoleOpResult> {
    if (this.config.activeRoleId === null) return "no_role_config";
    if (this.config.guildId === null) return "no_guild";
    const res = await this.api.listKeys({ status: "active", q: discordId, limit: 200 });
    if (!res.ok) return "error";
    // Strict post-filter (D-M8-15): q also matches note substrings and id prefixes.
    const mine = res.rows.filter((k) => k.discord_id === discordId);
    if (mine.some((k) => keyGrantsRole(k, this.now()))) return this.roles.addRole(discordId);
    return "noop";
  }

  /**
   * Full reconciliation over every known Discord identity: grant while any
   * active unexpired key exists, remove otherwise. Drives the scheduled
   * "role cleanup" (doc §15) and doubles as the fallback when the
   * GUILD_MEMBERS intent is off (D-M8-5).
   */
  async reconcile(): Promise<{ granted: string[]; removed: string[]; errors: number }> {
    if (this.config.activeRoleId === null || this.config.guildId === null) return { granted: [], removed: [], errors: 0 };
    const users = await this.api.listUsers();
    if (!users.ok) return { granted: [], removed: [], errors: 1 };
    // Page through active keys once; compute per-discord activeness from the
    // source rows (the users aggregate counts status only, not expiry).
    const activeByDiscord = new Map<string, boolean>();
    for (let offset = 0; ; offset += 200) {
      const page = await this.api.listKeys({ status: "active", limit: 200, offset });
      if (!page.ok) return { granted: [], removed: [], errors: 1 };
      for (const key of page.rows) {
        if (key.discord_id === null) continue;
        const grants = keyGrantsRole(key, this.now());
        if (activeByDiscord.get(key.discord_id) !== true) activeByDiscord.set(key.discord_id, grants);
      }
      if (page.rows.length < 200) break;
    }
    const granted: string[] = [];
    const removed: string[] = [];
    let errors = 0;
    for (const user of users.rows) {
      if (user.kind !== "discord") continue;
      const shouldHave = activeByDiscord.get(user.identity) === true;
      const op = shouldHave ? await this.roles.addRole(user.identity) : await this.roles.removeRole(user.identity);
      if (op === "error") errors++;
      else if (op === "granted") granted.push(user.identity);
      else if (op === "removed") removed.push(user.identity);
    }
    return { granted, removed, errors };
  }
}
