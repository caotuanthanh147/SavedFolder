// M8 test helpers — §22.1 discipline: the admin API side is the REAL api/
// router (from ../..) served over real HTTP through an entry that matches
// CCP-M8 P4's corrected behavior (pathname + search); only the Discord
// surface is faked, shaped exactly like the official interaction docs
// (RESEARCH-M8 rows 3–5): defer-then-edit, ephemeral = flag 64.
import { afterAll, beforeAll } from "bun:test";
import { buildEnv, ADMIN_TOKEN, PROJECT_ID, SCRIPT_ID, type TestEnv } from "../../api/test/helpers";
import { buildRoutes, dispatch } from "../../api/src/router";
import { AdminApi } from "../src/adminapi";
import { BotConfig } from "../src/config";
import { BotDeps, CommandInteractionSurface } from "../src/commands";
import { RoleSync, GuildRolePort, RoleOpResult } from "../src/roles";
import { ChannelPort } from "../src/scheduler";

export interface FakeInteractionOpts {
  command: string;
  sub?: string;
  user?: string;
  strings?: Record<string, string>;
  integers?: Record<string, number>;
}

export class FakeInteraction implements CommandInteractionSurface {
  commandName: string;
  subcommandName: string | null;
  userId: string;
  private readonly strings: Record<string, string>;
  private readonly integers: Record<string, number>;
  deferred: { ephemeral: boolean } | null = null;
  reply: { content?: string; embed?: { title?: string; description?: string; fields: { name: string; value: string; inline?: boolean }[] } } | null = null;

  constructor(opts: FakeInteractionOpts) {
    this.commandName = opts.command;
    this.subcommandName = opts.sub ?? null;
    this.userId = opts.user ?? "900000000000000001";
    this.strings = opts.strings ?? {};
    this.integers = opts.integers ?? {};
  }

  getString(name: string): string | null {
    return this.strings[name] ?? null;
  }

  getInteger(name: string): number | null {
    return this.integers[name] ?? null;
  }

  async deferReply(ephemeral: boolean): Promise<void> {
    this.deferred = { ephemeral };
  }

  async editReply(reply: { content?: string; embed?: { title?: string; description?: string; fields: { name: string; value: string; inline?: boolean }[] } }): Promise<void> {
    this.reply = reply;
  }
}

export class FakeRoles implements GuildRolePort {
  granted: string[] = [];
  removed: string[] = [];
  failNext = false;

  async addRole(userId: string): Promise<RoleOpResult> {
    if (this.failNext) return "error";
    this.granted.push(userId);
    return "granted";
  }

  async removeRole(userId: string): Promise<RoleOpResult> {
    if (this.failNext) return "error";
    this.removed.push(userId);
    return "removed";
  }
}

export class FakeChannel implements ChannelPort {
  posts: { content: string }[] = [];

  async post(message: { content: string }): Promise<void> {
    this.posts.push(message);
  }
}

export interface BotTestEnv {
  env: TestEnv;
  port: number;
  api: AdminApi;
  roles: FakeRoles;
  channel: FakeChannel;
  nowOverride: { value: number };
  makeDeps: (configOverrides?: Partial<BotConfig>) => BotDeps;
  adminHeaders: Record<string, string>;
}

export async function startBotTestEnv(): Promise<BotTestEnv> {
  const env = await buildEnv();
  const routes = buildRoutes();
  const server = Bun.serve({
    port: 0,
    fetch: async (request: Request): Promise<Response> => {
      const url = new URL(request.url);
      // CCP-M8 P4 behavior: the query string must reach RequestInput.path.
      const headers: Record<string, string> = {};
      request.headers.forEach((value, key) => {
        headers[key] = value;
      });
      const input = {
        method: request.method,
        path: url.pathname + url.search,
        headers,
        bodyBytes: new Uint8Array(await request.arrayBuffer()),
        ip: request.headers.get("x-test-ip") ?? "192.0.2.50",
        colo: "TST",
      };
      return dispatch(routes, env.ctx, env.config, input);
    },
  });
  const port = server.port;
  if (port === undefined) throw new Error("test server has no port");
  const api = new AdminApi(`http://127.0.0.1:${port}`, ADMIN_TOKEN);
  const roles = new FakeRoles();
  const channel = new FakeChannel();
  const nowOverride = { value: Math.floor(Date.now() / 1000) };
  const baseConfig: BotConfig = {
    token: "test-token",
    appId: "111111111111111111",
    guildId: "555555555555555555",
    apiBaseUrl: `http://127.0.0.1:${port}`,
    apiAdminToken: ADMIN_TOKEN,
    loaderBase: `http://127.0.0.1:${port}`,
    freeUrl: "https://dash.example.test/free",
    activeRoleId: "777777777777777777",
    reminderChannelId: "888888888888888888",
    reminderLeadDays: 3,
    schedulerIntervalSec: 3600,
  };
  const makeDeps = (configOverrides: Partial<BotConfig> = {}): BotDeps => {
    const config = { ...baseConfig, ...configOverrides };
    const sync = new RoleSync(api, roles, config, () => nowOverride.value);
    return { api, sync, config, now: () => nowOverride.value };
  };
  return { env, port, api, roles, channel, nowOverride, makeDeps, adminHeaders: { authorization: `Bearer ${ADMIN_TOKEN}` } };
}

// Convenience: create a key through the REAL admin API and link it to a
// Discord id through the REAL CCP-M8 link endpoint. Returns the row data.
export async function createLinkedKey(
  testEnv: BotTestEnv,
  discordId: string,
  opts: { days?: number | null; tier?: string; status?: string } = {},
): Promise<{ plaintext: string; id: string }> {
  const res = await testEnv.api.createKeys({
    project_id: PROJECT_ID,
    tier: opts.tier ?? "paid",
    script_ids: [SCRIPT_ID],
    ...(opts.days !== undefined && opts.days !== null ? { days: opts.days } : {}),
  });
  if (!res.ok) throw new Error("createLinkedKey: create failed");
  const created = res.keys[0];
  if (opts.status !== undefined && opts.status !== "active") {
    testEnv.env.db.prepare("UPDATE keys SET status = ? WHERE id = ?").run(opts.status, created.id);
  }
  const link = await testEnv.api.linkKey(created.key, discordId);
  if (!link.ok) throw new Error(`createLinkedKey: link failed (${JSON.stringify(link)})`);
  return { plaintext: created.key, id: created.id };
}
