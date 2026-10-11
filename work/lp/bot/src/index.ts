// M8 — entry point. Wires discord.js (gateway client + REST) to the
// command dispatch, role sync, and scheduler. Intents: Guilds +
// GuildMembers (privileged — one-time Developer Portal toggle, RESEARCH-M8
// row 8; the scheduler reconciliation covers the intent-off case, D-M8-5).
//
// Environment (no hardcoded secrets/URLs — doc hard rule):
//   LP_BOT_TOKEN            Discord bot token            (required)
//   LP_BOT_APP_ID           Discord application id        (required)
//   LP_BOT_GUILD_ID         guild for commands + roles    (optional)
//   LP_BOT_API_URL          admin API base URL            (required)
//   LP_BOT_ADMIN_TOKEN      admin API bearer token        (required)
//   LP_BOT_LOADER_BASE      loader URL base               (optional, default = API URL)
//   LP_BOT_FREE_URL         free-key page URL             (optional)
//   LP_BOT_ACTIVE_ROLE_ID   active-key holder role        (optional)
//   LP_BOT_REMINDER_CHANNEL_ID  expiry reminder channel   (optional)
//   LP_BOT_REMINDER_LEAD_DAYS   reminder lead days        (default 3)
//   LP_BOT_SCHEDULER_INTERVAL_SEC  scheduler cadence       (default 3600)
import { Client, Events, GatewayIntentBits, MessageFlags, REST, Routes, EmbedBuilder, type ChatInputCommandInteraction } from "discord.js";
import { parseConfig } from "./config";
import { AdminApi } from "./adminapi";
import { RoleSync } from "./roles";
import { startScheduler } from "./scheduler";
import { commandPayloads, runCommand, BotDeps, CommandInteractionSurface } from "./commands";
import { BotReply } from "./format";

function adaptInteraction(interaction: ChatInputCommandInteraction): CommandInteractionSurface {
  const sub = interaction.options.getSubcommand(false);
  return {
    commandName: interaction.commandName,
    subcommandName: sub === "" ? null : sub,
    userId: interaction.user.id,
    getString: (name) => interaction.options.getString(name, false),
    getInteger: (name) => interaction.options.getInteger(name, false),
    deferReply: async (ephemeral: boolean) => {
      await interaction.deferReply(ephemeral ? { flags: MessageFlags.Ephemeral } : {});
    },
    editReply: async (reply: { content?: string; embed?: BotReply["embed"] }) => {
      const embed = reply.embed !== undefined
        ? [new EmbedBuilder()
          .setTitle(reply.embed.title ?? null)
          .setDescription(reply.embed.description ?? null)
          .addFields(...reply.embed.fields.map((f) => ({ name: f.name, value: f.value, inline: f.inline })))
          .setColor(0x2f8f6f)]
        : undefined;
      await interaction.editReply({ content: reply.content ?? null, embeds: embed });
    },
  };
}

async function registerCommands(appId: string, guildId: string | null, token: string): Promise<void> {
  const rest = new REST({ version: "10" }).setToken(token);
  const body = commandPayloads();
  // Guild commands update instantly (RESEARCH-M8 row 6); global would be
  // the public-release shape. Guild-less deployments still register global.
  if (guildId !== null) {
    await rest.put(Routes.applicationGuildCommands(appId, guildId), { body });
  } else {
    await rest.put(Routes.applicationCommands(appId), { body });
  }
}

async function main(): Promise<void> {
  const config = parseConfig();
  const api = new AdminApi(config.apiBaseUrl, config.apiAdminToken);
  const client = new Client({ intents: [GatewayIntentBits.Guilds, GatewayIntentBits.GuildMembers] });

  // Role port over discord.js REST (PUT/DELETE member-role routes,
  // RESEARCH-M8 row 9). 204 = ok; 4xx UNKNOWN_MEMBER = already gone/noop.
  const rest = new REST({ version: "10" }).setToken(config.token);
  const roles = {
    async addRole(userId: string): Promise<"granted" | "error"> {
      if (config.guildId === null || config.activeRoleId === null) return "error";
      try {
        await rest.put(Routes.guildMemberRole(config.guildId, userId, config.activeRoleId));
        return "granted";
      } catch {
        return "error";
      }
    },
    async removeRole(userId: string): Promise<"removed" | "error"> {
      if (config.guildId === null || config.activeRoleId === null) return "error";
      try {
        await rest.delete(Routes.guildMemberRole(config.guildId, userId, config.activeRoleId));
        return "removed";
      } catch {
        return "error";
      }
    },
  };
  const sync = new RoleSync(api, roles, config);

  const channel = {
    async post(message: { content: string }): Promise<void> {
      if (config.reminderChannelId === null) return;
      try {
        await rest.post(Routes.channelMessages(config.reminderChannelId), { body: { content: message.content } });
      } catch {
        console.error("reminder post failed");
      }
    },
  };

  const deps: BotDeps = { api, sync, config, now: () => Date.now() / 1000 };

  client.once(Events.ClientReady, async () => {
    try {
      await registerCommands(config.appId, config.guildId, config.token);
    } catch {
      console.error("command registration failed");
    }
    startScheduler({ api, sync, channel, config, now: deps.now });
  });

  client.on(Events.InteractionCreate, async (interaction) => {
    if (!interaction.isChatInputCommand()) return;
    await runCommand(deps, adaptInteraction(interaction));
  });

  // Instant role grant on join (GUILD_MEMBERS intent, D-M8-5).
  client.on(Events.GuildMemberAdd, async (member) => {
    const op = await sync.grantIfActive(member.id);
    if (op === "error") console.error("role grant on join failed");
  });

  await client.login(config.token);
}

await main();
