// M8 — user commands (doc §15): /redeem /getscript /status /resethwid
// /free /mykeys. All replies are ephemeral (D-M8-4). Key material never
// appears in non-ephemeral output (D-M8-11).
import { BotDeps, CommandInteractionSurface } from "./commands";
import { BotReply, errorText, fmtExpiry, maskKeyId } from "./format";
import { keyGrantsRole } from "./roles";
import { KeyRow } from "./adminapi";

/** Strict post-filter (D-M8-15): q= also matches note substrings + id prefixes. */
async function myKeys(deps: BotDeps, discordId: string): Promise<KeyRow[] | null> {
  const res = await deps.api.listKeys({ q: discordId, limit: 200 });
  if (!res.ok) return null;
  return res.rows.filter((k) => k.discord_id === discordId);
}

export async function redeem(deps: BotDeps, i: CommandInteractionSurface): Promise<BotReply> {
  const key = i.getString("key");
  if (key === null) return { content: "Missing key option.", ephemeral: true };
  const link = await deps.api.linkKey(key, i.userId);
  if (!link.ok) return { content: errorText(link), ephemeral: true };
  let roleNote = "";
  if (link.status === "active" && (link.expires_at === null || link.expires_at > deps.now())) {
    const roleOp = await deps.sync.grantIfActive(i.userId);
    if (roleOp === "granted") roleNote = " Active-key role granted.";
    else if (roleOp === "error") roleNote = " Role sync failed; it will retry on the next scheduled pass.";
  }
  const expiry = fmtExpiry(link.expires_at, deps.now());
  return {
    content: link.already
      ? `This key is already linked to your account. Tier **${link.tier}**, status **${link.status}**, expires ${expiry}.${roleNote}`
      : `✅ Key \`${maskKeyId(link.id)}\` linked to your Discord account. Tier **${link.tier}**, status **${link.status}**, expires ${expiry}.${roleNote}`,
    ephemeral: true,
  };
}

export async function getscript(deps: BotDeps, i: CommandInteractionSurface): Promise<BotReply> {
  const keys = await myKeys(deps, i.userId);
  if (keys === null) return { content: errorText({ status: 0, error: "network" }), ephemeral: true };
  if (keys.length === 0) {
    return { content: "No keys are linked to your account yet — use `/redeem` first.", ephemeral: true };
  }
  const fields = [];
  for (const key of keys) {
    const detail = await deps.api.keyDetail(key.id);
    const scripts = detail.ok && detail.scripts.length > 0
      ? detail.scripts.map((s) => `[${s.name}](${deps.config.loaderBase}/loaders/${s.script_id}.lua)`).join("\n")
      : "_no script entitlements_";
    fields.push({ name: `Key \`${maskKeyId(key.id)}\` — ${key.tier}`, value: scripts });
  }
  return {
    embed: {
      title: "Your script access",
      description: "Run the loader URL in your executor to fetch the latest build.",
      fields,
    },
    ephemeral: true,
  };
}

export async function status(deps: BotDeps, i: CommandInteractionSurface): Promise<BotReply> {
  const keys = await myKeys(deps, i.userId);
  if (keys === null) return { content: errorText({ status: 0, error: "network" }), ephemeral: true };
  if (keys.length === 0) {
    return { content: "No keys are linked to your account yet — use `/redeem` first.", ephemeral: true };
  }
  const summary = await deps.api.listUsers(i.userId);
  const header = summary.ok
    ? summary.rows.find((r) => r.kind === "discord" && r.identity === i.userId)
    : undefined;
  const fields = keys.slice(0, 10).map((k) => ({
    name: `\`${maskKeyId(k.id)}\` — ${k.tier}`,
    value: `status **${k.status}** · expires ${fmtExpiry(k.expires_at, deps.now())} · HWID ${k.hwid_bound ? "bound" : "unbound"} · ${k.total_executions} uses`,
  }));
  const more = keys.length > 10 ? `\n…and ${keys.length - 10} more` : "";
  return {
    embed: {
      title: "Your keys",
      description: (header !== undefined
        ? `${header.key_count} key(s), ${header.active_keys} active, ${header.total_executions} total executions\n`
        : "") + more,
      fields,
    },
    ephemeral: true,
  };
}

export async function resethwid(deps: BotDeps, i: CommandInteractionSurface): Promise<BotReply> {
  const keyId = i.getString("key_id");
  if (keyId === null) return { content: "Missing key_id option.", ephemeral: true };
  // Ownership check BEFORE the privileged call: the api's reset-hwid is
  // admin-gated (the bot calls it with the admin token on the user's
  // behalf), so the bot must scope it to the invoker's own keys.
  const detail = await deps.api.keyDetail(keyId);
  if (!detail.ok) return { content: errorText(detail), ephemeral: true };
  if (detail.discord_id !== i.userId) {
    return { content: "That key is not linked to your Discord account.", ephemeral: true };
  }
  const res = await deps.api.resetHwid(keyId);
  if (!res.ok) return { content: errorText(res), ephemeral: true };
  return { content: `HWID reset for key \`${maskKeyId(keyId)}\`. The next session binds a new device.`, ephemeral: true };
}

export async function free(deps: BotDeps): Promise<BotReply> {
  if (deps.config.freeUrl === null) {
    return { content: "Free keys are not configured for this deployment.", ephemeral: true };
  }
  return {
    content: `🎟️ Get a free key by completing the checkpoints on the free-key page:\n${deps.config.freeUrl}\n\nThe issued free key is time-limited — redeem it here with \`/redeem\`.`,
    ephemeral: true,
  };
}

export async function mykeys(deps: BotDeps, i: CommandInteractionSurface): Promise<BotReply> {
  const keys = await myKeys(deps, i.userId);
  if (keys === null) return { content: errorText({ status: 0, error: "network" }), ephemeral: true };
  if (keys.length === 0) {
    return { content: "No keys are linked to your account yet — use `/redeem`, or `/free` to get one.", ephemeral: true };
  }
  const active = keys.filter((k) => keyGrantsRole(k, deps.now())).length;
  const fields = keys.slice(0, 10).map((k) => ({
    name: `\`${maskKeyId(k.id)}\``,
    value: `${k.tier} · **${k.status}** · expires ${fmtExpiry(k.expires_at, deps.now())}`,
    inline: true,
  }));
  return {
    embed: {
      title: "Your keys",
      description: `${keys.length} key(s), ${active} currently active`,
      fields,
    },
    ephemeral: true,
  };
}
