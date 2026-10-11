// M8 — command surface (doc §15 command list, exact) + interaction
// dispatch. Handlers are pure over the AdminApi/RoleSync ports; the
// Discord-specific adapter lives in index.ts. Every command defers first
// (3 s deadline — RESEARCH-M8 row 3) then edits (D-M8-3); ephemeral-ness
// is a per-command constant (D-M8-4).
import { SlashCommandBuilder, PermissionFlagsBits } from "discord.js";
import { BotReply } from "./format";
import { AdminApi } from "./adminapi";
import { BotConfig } from "./config";
import { RoleSync } from "./roles";
import * as user from "./handlers-user";
import * as admin from "./handlers-admin";

export interface CommandInteractionSurface {
  commandName: string;
  subcommandName: string | null;
  userId: string;
  getString(name: string): string | null;
  getInteger(name: string): number | null;
  deferReply(ephemeral: boolean): Promise<void>;
  editReply(reply: { content?: string; embed?: BotReply["embed"] }): Promise<void>;
}

export interface BotDeps {
  api: AdminApi;
  sync: RoleSync;
  config: BotConfig;
  now: () => number;
}

type Handler = (deps: BotDeps, i: CommandInteractionSurface) => Promise<BotReply>;

interface CommandSpec {
  name: string;
  handler: Handler;
  /** Ephemeral per command; for subcommand commands, per subcommand (D-M8-4). */
  ephemeral: boolean | Record<string, boolean>;
}

function isEphemeral(spec: CommandSpec, sub: string | null): boolean {
  if (typeof spec.ephemeral === "boolean") return spec.ephemeral;
  return sub !== null && spec.ephemeral[sub] === true;
}

const SPECS: CommandSpec[] = [
  { name: "redeem", handler: user.redeem, ephemeral: true },
  { name: "getscript", handler: user.getscript, ephemeral: true },
  { name: "status", handler: user.status, ephemeral: true },
  { name: "resethwid", handler: user.resethwid, ephemeral: true },
  { name: "free", handler: user.free, ephemeral: true },
  { name: "mykeys", handler: user.mykeys, ephemeral: true },
  // /key create + /key info carry key material → ephemeral; revoke/extend acks do not (D-M8-4).
  { name: "key", handler: admin.key, ephemeral: { create: true, revoke: false, extend: false, info: true } },
  { name: "blacklist", handler: admin.blacklistAdd, ephemeral: false },
  { name: "whitelist", handler: admin.whitelist, ephemeral: false },
  { name: "stats", handler: admin.stats, ephemeral: false },
  { name: "leak", handler: admin.leakLookup, ephemeral: true },
];

const byName = new Map(SPECS.map((s) => [s.name, s]));

/** Dispatch one interaction: defer → run → edit. Never throws. */
export async function runCommand(deps: BotDeps, i: CommandInteractionSurface): Promise<void> {
  const spec = byName.get(i.commandName);
  if (spec === undefined) return;
  try {
    await i.deferReply(isEphemeral(spec, i.subcommandName));
  } catch {
    return; // interaction token dead (3 s window missed / Discord restart)
  }
  let reply: BotReply;
  try {
    reply = await spec.handler(deps, i);
  } catch {
    // Minimal, generic — no stack or payload data in user-visible output.
    reply = { content: "Something went wrong handling that command. Try again later.", ephemeral: true };
  }
  try {
    await i.editReply({ content: reply.content, embed: reply.embed });
  } catch {
    // Edit failures (15 min token expiry) are non-fatal by then.
  }
}

const TIERS = [
  { name: "free", value: "free" },
  { name: "paid", value: "paid" },
  { name: "lifetime", value: "lifetime" },
  { name: "reseller", value: "reseller" },
] as const;

const BLACKLIST_KINDS = [
  { name: "hwid", value: "hwid" },
  { name: "ip", value: "ip" },
  { name: "roblox_user", value: "roblox_user" },
  { name: "discord", value: "discord" },
] as const;

/** JSON payload for command registration (guild commands update instantly — RESEARCH-M8 row 6). */
export function commandPayloads(): unknown[] {
  return [
    new SlashCommandBuilder()
      .setName("redeem")
      .setDescription("Link a key to your Discord account")
      .addStringOption((o) => o.setName("key").setDescription("Your key (YURI-XXXXX-…)").setRequired(true).setMaxLength(64)),
    new SlashCommandBuilder().setName("getscript").setDescription("Get your script loader links"),
    new SlashCommandBuilder().setName("status").setDescription("Show the status of your keys"),
    new SlashCommandBuilder()
      .setName("resethwid")
      .setDescription("Reset the HWID bound to one of your keys")
      .addStringOption((o) => o.setName("key_id").setDescription("Key id shown by /mykeys").setRequired(true).setMaxLength(32)),
    new SlashCommandBuilder().setName("free").setDescription("How to get a free key"),
    new SlashCommandBuilder().setName("mykeys").setDescription("List your keys"),
    new SlashCommandBuilder()
      .setName("key")
      .setDescription("Key administration")
      .setDefaultMemberPermissions(PermissionFlagsBits.ManageGuild)
      .addSubcommand((s) =>
        s
          .setName("create")
          .setDescription("Create one or more keys")
          .addStringOption((o) => o.setName("project_id").setDescription("32-hex project id").setRequired(true)
            .setMaxLength(32))
          .addStringOption((o) => o.setName("tier").setDescription("Key tier").setRequired(true).addChoices(...TIERS))
          .addIntegerOption((o) => o.setName("days").setDescription("Validity in days (omit = lifetime)").setMinValue(1).setMaxValue(3650))
          .addIntegerOption((o) => o.setName("count").setDescription("How many keys (default 1)").setMinValue(1).setMaxValue(500))
          .addStringOption((o) => o.setName("note").setDescription("Note stored on the key").setMaxLength(256))
          .addStringOption((o) => o.setName("scripts").setDescription("Comma-separated script ids").setRequired(true)),
      )
      .addSubcommand((s) => s.setName("revoke").setDescription("Revoke a key").addStringOption((o) => o.setName("id").setDescription("Key id").setRequired(true).setMaxLength(32)))
      .addSubcommand((s) =>
        s
          .setName("extend")
          .setDescription("Extend a key")
          .addStringOption((o) => o.setName("id").setDescription("Key id").setRequired(true).setMaxLength(32))
          .addIntegerOption((o) => o.setName("days").setDescription("Days to add").setRequired(true).setMinValue(1).setMaxValue(3650)),
      )
      .addSubcommand((s) => s.setName("info").setDescription("Full key detail incl. entitlements").addStringOption((o) => o.setName("id").setDescription("Key id").setRequired(true).setMaxLength(32))),
    new SlashCommandBuilder()
      .setName("blacklist")
      .setDescription("Blacklist administration")
      .setDefaultMemberPermissions(PermissionFlagsBits.ManageGuild)
      .addSubcommand((s) =>
        s
          .setName("add")
          .setDescription("Add a blacklist entry")
          .addStringOption((o) => o.setName("kind").setDescription("Entry kind").setRequired(true).addChoices(...BLACKLIST_KINDS))
          .addStringOption((o) => o.setName("value").setDescription("Value (hwid/ip/user id)").setRequired(true).setMaxLength(256))
          .addStringOption((o) => o.setName("reason").setDescription("Reason").setMaxLength(256))
          .addStringOption((o) => o.setName("project_id").setDescription("Required for kind hwid").setMaxLength(32)),
      ),
    new SlashCommandBuilder()
      .setName("whitelist")
      .setDescription("Remove a blacklist entry")
      .setDefaultMemberPermissions(PermissionFlagsBits.ManageGuild)
      .addStringOption((o) => o.setName("id").setDescription("Blacklist entry id (see dashboard)").setRequired(true).setMaxLength(32)),
    new SlashCommandBuilder()
      .setName("stats")
      .setDescription("Platform stats snapshot")
      .setDefaultMemberPermissions(PermissionFlagsBits.ManageGuild)
      .addStringOption((o) =>
        o.setName("window").setDescription("Time window").addChoices(
          { name: "1 hour", value: "1h" },
          { name: "24 hours", value: "24h" },
          { name: "7 days", value: "7d" },
        ),
      ),
    new SlashCommandBuilder()
      .setName("leak")
      .setDescription("Leak tools")
      .setDefaultMemberPermissions(PermissionFlagsBits.ManageGuild)
      .addSubcommand((s) =>
        s
          .setName("lookup")
          .setDescription("Trace a leaked artifact, watermark id, or session token to its key")
          .addStringOption((o) => o.setName("value").setDescription("Artifact / watermark id / session token").setRequired(true).setMaxLength(4000)),
      ),
  ].map((b) => (b as { toJSON(): unknown }).toJSON());
}
