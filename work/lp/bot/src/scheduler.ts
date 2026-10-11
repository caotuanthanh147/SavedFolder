// M8 — scheduled job (doc §15: "Scheduled job for expiry reminders and role
// cleanup"). Hourly by default (D-M8-10); clock + channel post are injectable
// for tests. Reminders post to the configured channel, never DM users
// (D-M8-6, Developer Policy — RESEARCH-M8 row 10).
import { AdminApi, KeyRow } from "./adminapi";
import { BotConfig } from "./config";
import { maskKeyId } from "./format";
import { RoleSync } from "./roles";

export interface ReminderPost {
  content: string;
}

export interface ChannelPort {
  post(message: ReminderPost): Promise<void>;
}

export class NoopChannel implements ChannelPort {
  async post(): Promise<void> {}
}

export interface SchedulerDeps {
  api: AdminApi;
  sync: RoleSync;
  channel: ChannelPort;
  config: BotConfig;
  now: () => number;
}

export interface SchedulerRun {
  reconciled: { granted: string[]; removed: string[]; errors: number };
  reminders: number;
}

/** One scheduler pass: role reconciliation + expiry reminder post. */
export async function runOnce(deps: SchedulerDeps): Promise<SchedulerRun> {
  const reconciled = await deps.sync.reconcile();
  let reminders = 0;
  if (deps.config.reminderChannelId !== null && deps.config.reminderLeadDays > 0) {
    const leadSec = deps.config.reminderLeadDays * 86400;
    const now = deps.now();
    const expiring: KeyRow[] = [];
    for (let offset = 0; ; offset += 200) {
      const page = await deps.api.listKeys({ status: "active", limit: 200, offset });
      if (!page.ok) break;
      for (const key of page.rows) {
        if (key.discord_id === null || key.expires_at === null) continue;
        if (key.expires_at > now && key.expires_at <= now + leadSec) expiring.push(key);
      }
      if (page.rows.length < 200) break;
    }
    if (expiring.length > 0) {
      const lines = expiring
        .sort((a, b) => (a.expires_at ?? 0) - (b.expires_at ?? 0))
        .slice(0, 25)
        .map((k) => `- key \`${maskKeyId(k.id)}\` (tier ${k.tier}) for discord ${k.discord_id} expires <t:${k.expires_at}:R>`);
      const more = expiring.length > 25 ? `\n…and ${expiring.length - 25} more` : "";
      await deps.channel.post({
        content: `⏳ **Keys expiring within ${deps.config.reminderLeadDays} days** (${expiring.length}):\n${lines.join("\n")}${more}`,
      });
      reminders = expiring.length;
    }
  }
  return { reconciled, reminders };
}

export interface SchedulerHandle {
  stop(): void;
  runOnce(): Promise<SchedulerRun>;
}

export function startScheduler(deps: SchedulerDeps): SchedulerHandle {
  const timer = setInterval(() => {
    void runOnce(deps).catch(() => {
      // Keep debug output minimal (doc hard rule): one line, no payload data.
      console.error("scheduler pass failed");
    });
  }, deps.config.schedulerIntervalSec * 1000);
  return {
    stop: () => clearInterval(timer),
    runOnce: () => runOnce(deps),
  };
}
