// M8 — admin commands (doc §15): /key create|revoke|extend|info,
// /blacklist add, /whitelist, /stats, /leak lookup. Gated Discord-side via
// default_member_permissions (D-M8-7 UX layer) and server-side by the admin
// API role on the bot's token (the real gate). /key create + /key info +
// /leak lookup are ephemeral (key material — D-M8-4); the acks are not.
import { BotDeps, CommandInteractionSurface } from "./commands";
import { BotReply, errorText, fmtExpiry, fmtDate, maskKeyId } from "./format";

export async function key(deps: BotDeps, i: CommandInteractionSurface): Promise<BotReply> {
  const sub = i.subcommandName;
  if (sub === "create") return keyCreate(deps, i);
  if (sub === "revoke") return keyRevoke(deps, i);
  if (sub === "extend") return keyExtend(deps, i);
  if (sub === "info") return keyInfo(deps, i);
  return { content: "Unknown subcommand.", ephemeral: true };
}

async function keyCreate(deps: BotDeps, i: CommandInteractionSurface): Promise<BotReply> {
  const projectId = i.getString("project_id");
  const tier = i.getString("tier");
  const scriptsRaw = i.getString("scripts");
  if (projectId === null || tier === null || scriptsRaw === null) {
    return { content: "Missing options.", ephemeral: true };
  }
  const scriptIds = scriptsRaw.split(",").map((s) => s.trim()).filter((s) => s.length > 0);
  if (scriptIds.length === 0) return { content: "No script ids given.", ephemeral: true };
  const res = await deps.api.createKeys({
    project_id: projectId,
    tier,
    script_ids: scriptIds,
    ...(i.getInteger("days") !== null ? { days: i.getInteger("days") as number } : {}),
    ...(i.getInteger("count") !== null ? { count: i.getInteger("count") as number } : {}),
    ...(i.getString("note") !== null ? { note: i.getString("note") } : {}),
  });
  if (!res.ok) return { content: errorText(res), ephemeral: true };
  // Plaintext keys are shown ONCE (api returns them once) — ephemeral per doc §15.
  const lines = res.keys.map((k) => `\`${k.key}\` → id \`${k.id}\``);
  return { content: `Created ${res.keys.length} key(s) — **shown once, never again**:\n${lines.join("\n")}`, ephemeral: true };
}

async function keyRevoke(deps: BotDeps, i: CommandInteractionSurface): Promise<BotReply> {
  const id = i.getString("id");
  if (id === null) return { content: "Missing id option.", ephemeral: true };
  const res = await deps.api.revokeKey(id);
  if (!res.ok) return { content: errorText(res), ephemeral: true };
  return { content: `Revoked key \`${maskKeyId(id)}\`. Linked role will be removed on the next scheduled pass.`, ephemeral: false };
}

async function keyExtend(deps: BotDeps, i: CommandInteractionSurface): Promise<BotReply> {
  const id = i.getString("id");
  const days = i.getInteger("days");
  if (id === null || days === null) return { content: "Missing options.", ephemeral: true };
  const res = await deps.api.patchKey(id, { extend_days: days });
  if (!res.ok) return { content: errorText(res), ephemeral: true };
  return { content: `Extended key \`${maskKeyId(id)}\` by ${days} day(s).`, ephemeral: false };
}

async function keyInfo(deps: BotDeps, i: CommandInteractionSurface): Promise<BotReply> {
  const id = i.getString("id");
  if (id === null) return { content: "Missing id option.", ephemeral: true };
  const res = await deps.api.keyDetail(id);
  if (!res.ok) return { content: errorText(res), ephemeral: true };
  const scripts = res.scripts.length > 0 ? res.scripts.map((s) => `${s.name} (\`${s.script_id}\`)${s.keyless ? " — keyless" : ""}`).join("\n") : "_none_";
  return {
    embed: {
      title: `Key \`${res.id}\``,
      fields: [
        { name: "Tier / Status", value: `${res.tier} · **${res.status}**`, inline: true },
        { name: "Expires", value: fmtExpiry(res.expires_at, deps.now()), inline: true },
        { name: "HWID", value: res.hwid_bound ? `bound (${res.hwid_resets} resets)` : "unbound", inline: true },
        { name: "Discord", value: res.discord_id ?? "—", inline: true },
        { name: "Uses", value: String(res.total_executions), inline: true },
        { name: "Created", value: fmtDate(res.created_at, deps.now()), inline: true },
        { name: "Note", value: res.note ?? "—" },
        { name: "Scripts", value: scripts },
      ],
    },
    ephemeral: true,
  };
}

export async function blacklistAdd(deps: BotDeps, i: CommandInteractionSurface): Promise<BotReply> {
  const sub = i.subcommandName;
  if (sub !== "add") return { content: "Unknown subcommand.", ephemeral: true };
  const kind = i.getString("kind");
  const value = i.getString("value");
  if (kind === null || value === null) return { content: "Missing options.", ephemeral: true };
  const res = await deps.api.blacklistAdd({
    kind,
    value,
    ...(i.getString("reason") !== null ? { reason: i.getString("reason") } : {}),
    ...(i.getString("project_id") !== null ? { project_id: i.getString("project_id") } : {}),
  });
  if (!res.ok) return { content: errorText(res), ephemeral: true };
  return { content: `Blacklisted ${kind} \`${value}\` (entry \`${res.id}\`).`, ephemeral: false };
}

export async function whitelist(deps: BotDeps, i: CommandInteractionSurface): Promise<BotReply> {
  const id = i.getString("id");
  if (id === null) return { content: "Missing id option.", ephemeral: true };
  const res = await deps.api.blacklistRemove(id);
  if (!res.ok) return { content: errorText(res), ephemeral: true };
  return { content: `Removed blacklist entry \`${id}\`.`, ephemeral: false };
}

export async function stats(deps: BotDeps, i: CommandInteractionSurface): Promise<BotReply> {
  const window = i.getString("window") ?? "24h";
  const [metrics, alerts] = await Promise.all([deps.api.metrics(window), deps.api.alerts()]);
  if (!metrics.ok) return { content: errorText(metrics), ephemeral: true };
  const alertLine = alerts.ok
    ? alerts.alerts.length === 0
      ? "no active alerts"
      : `${alerts.alerts.length} active (${alerts.alerts.filter((a) => a.severity === "critical").length} critical)`
    : "alerts unavailable";
  const rate = metrics.auth.success_rate === null ? "—" : `${(metrics.auth.success_rate * 100).toFixed(1)}%`;
  const conv = metrics.free_flow.conversion === null ? "—" : `${(metrics.free_flow.conversion * 100).toFixed(1)}%`;
  return {
    embed: {
      title: `Platform stats — ${window} window`,
      fields: [
        { name: "Keys", value: `${metrics.keys.active} active · ${metrics.keys.revoked} revoked · ${metrics.keys.expiring_7d} expiring ≤7d`, inline: true },
        { name: "Auth", value: `${metrics.auth.total_ok} ok · ${metrics.auth.total_fail} fail · ${rate}`, inline: true },
        { name: "Sessions", value: `${metrics.sessions.created} created · ${metrics.sessions.live_now} live`, inline: true },
        { name: "Free flow", value: `${metrics.free_flow.starts} starts · ${metrics.free_flow.claims} claims · ${conv} conversion`, inline: true },
        { name: "Tamper", value: String(metrics.tamper.total), inline: true },
        { name: "Nodes", value: `${metrics.nodes.active} active · ${metrics.nodes.inactive} inactive`, inline: true },
        { name: "Alerts", value: alertLine },
      ],
    },
    ephemeral: false,
  };
}

export async function leakLookup(deps: BotDeps, i: CommandInteractionSurface): Promise<BotReply> {
  const sub = i.subcommandName;
  if (sub !== "lookup") return { content: "Unknown subcommand.", ephemeral: true };
  const value = i.getString("value");
  if (value === null) return { content: "Missing value option.", ephemeral: true };
  const res = await deps.api.leakLookup(value);
  if (!res.ok) {
    const detail = typeof res.error === "object" && res.error.error === "no_watermark" ? "No watermark-bearing artifact found in the input." : errorText(res);
    return { content: detail, ephemeral: true };
  }
  const keyLine = res.key !== null
    ? `\`${res.key.id}\` (${res.key.tier}, **${res.key.status}**${res.key.discord_id !== null ? `, discord ${res.key.discord_id}` : ""})`
    : "_no key linked_";
  const lastSession = res.sessions[0] ?? null;
  return {
    embed: {
      title: `Leak trace — watermark \`${res.watermark_id.slice(0, 8)}…\``,
      fields: [
        { name: "Key", value: keyLine },
        { name: "Sessions", value: `${res.sessions.length} watermarked session(s)${lastSession !== null ? `, last ${fmtDate(lastSession.created_at, deps.now())}` : ""}` },
        { name: "Recent events", value: res.events.slice(0, 5).map((e) => `${e.type}${e.detail !== null ? ` (${e.detail})` : ""}`).join("\n") || "_none_" },
        { name: "Next step", value: "Run the leak revoke from the dashboard's Leak tools view (auto-revokes the key and blacklists the identity)." },
      ],
    },
    ephemeral: true,
  };
}
