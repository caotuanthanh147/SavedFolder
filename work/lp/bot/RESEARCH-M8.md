# RESEARCH-M8 — Discord bot (doc.md §15)

Research log per doc.md READ FIRST ("Mandatory research ... BEFORE writing any code").
All sources below were opened during this session (2026-10-11). The one claim that could
be tested locally was tested locally instead of trusted (row 12).

## Source table

| # | Topic | Source URL | Version / date | Key finding | Used for |
|---|-------|-----------|----------------|-------------|----------|
| 1 | discord.js current version | https://registry.npmjs.org/discord.js/latest | 14.27.0 (fetched 2026-10-11) | Latest stable; dep set includes @discordjs/rest, @discordjs/ws, discord-api-types, @discordjs/builders | Library choice, version pin |
| 2 | discord.js release cadence / breaking changes | https://github.com/discordjs/discord.js/releases (via API, per_page=10) | 14.27.0 published 2026-07-15; earlier 14.26.5/14.26.4/... back to 2026-04 | The v14 line is in active maintenance with patch/minor releases only — no v15 exists; recent changes are fixes, not breaking surface | Safe to pin ^14.27.0 |
| 3 | Interaction ack / token windows | https://discord.com/developers/docs/interactions/receiving-and-responding | opened 2026-10-11 | "Interaction tokens are valid for 15 minutes and can be used to send followup messages but you must send an initial response within 3 seconds of receiving the event. If the 3 second deadline is exceeded, the token will be invalidated." | Every command defers first, then edits (D-M8-3) |
| 4 | Ephemeral responses | same page as #3 | opened 2026-10-11 | Ephemeral is a message flag (bitfield); docs list EPHEMERAL among the only settable flags for interaction responses | `flags: MessageFlags.Ephemeral` (=64) on replies carrying key/script content |
| 5 | Interaction types | same page as #3 | opened 2026-10-11 | Interaction Type values: PING 1, APPLICATION_COMMAND 2, MESSAGE_COMPONENT 3, APPLICATION_COMMAND_AUTOCOMPLETE 4, MODAL_SUBMIT 5 | Handler dispatch (chat input only) |
| 6 | Slash command + permission model | https://discord.com/developers/docs/interactions/application-commands | opened 2026-10-11 | `default_member_permissions` = bit set controlling who can run a command in a guild; `dm_permission` is deprecated (use `contexts`); `integration_types`/`contexts` set install contexts; guild commands "update instantly" while global commands are for public use | Admin commands get `default_member_permissions` = MANAGE_GUILD (32); registration is guild-scoped for instant availability (D-M8-7) |
| 7 | Rate limits | https://discord.com/developers/docs/topics/rate-limits | opened 2026-10-11 | "All bots can make up to 50 requests per second to our API" (global, per-bot); per-route limits shared across endpoints via `X-RateLimit-Bucket`; exceeding returns 429 with retry_after; an Invalid Request limit exists above which Cloudflare bans apply | Role-sync batches sequential REST calls; scheduler spreads work (D-M8-10); @discordjs/rest handles bucket waits |
| 8 | Privileged intents | https://discord.com/developers/docs/topics/gateway (+ gateway-events page) | opened 2026-10-11 | Privileged intents = GUILD_PRESENCES, GUILD_MEMBERS, MESSAGE_CONTENT; must be enabled in the Developer Portal before IDENTIFY; verification (100+ guilds) additionally requires approval; connection closes with 4013 on invalid intents | Bot uses Guilds + GuildMembers; README documents the one-time portal toggle; scheduler reconciliation covers the case where the owner leaves the intent off (D-M8-5) |
| 9 | Guild member role endpoints | https://discord.com/developers/docs/resources/guild | opened 2026-10-11 | "Add Guild Member Role" (PUT) / "Remove Guild Member Role" (DELETE) at /guilds/{guild.id}/members/{user.id}/roles/{role.id}; MANAGE_ROLES permission required; routes verified locally via discord.js `Routes.guildMemberRole()` | Role grant/remove implementation (bot/src/roles.ts) |
| 10 | Developer Policy (contact rules) | https://discord.com/developers/docs/policies-and-agreements/developer-policy (extracted via page_reader) | opened 2026-10-11 | "Do not contact users on Discord without their explicit permission. This includes frequently sending unsolicited direct messages and/or sending direct messages not directly related to maintaining or improving an Application's functionality." | Expiry reminders post to a configured admin channel, never DM users (D-M8-6) |
| 11 | HTTP-interactions alternative | https://registry.npmjs.org/@discord-interactions/builders/latest | 0.3.18 (fetched 2026-10-11) | The HTTP-only ecosystem (no gateway) exists and is small; using it would still require a separate scheduler for doc §15's scheduled job and a public HTTPS endpoint | Compared and rejected (Options compared #1) |
| 12 | discord.js under Bun 1.3.14 | LIVE SMOKE TEST (this session, /tmp/djs-smoke) | discord.js 14.27.0 + Bun 1.3.14 | `new Client({intents})`, `SlashCommandBuilder` (incl. `setDefaultMemberPermissions`), `REST`, `Routes.guildMemberRole`, `EmbedBuilder`, `MessageFlags.Ephemeral === 64` all construct and produce correct values under Bun | Runtime choice (D-M8-2) — evidence is a runnable command, not a doc claim |

## Options compared

1. **Discord surface library**
   - discord.js 14.27.0 (gateway + REST + builders + interaction handling in one maintained
     package; live-verified under Bun; per-route rate-limit handling built into @discordjs/rest).
     Chosen.
   - @discord-interactions (HTTP interactions only): needs a public HTTPS endpoint, gives no
     gateway (no member-join role grants), and doc §15's scheduled job would still need a
     separate scheduler — two moving parts instead of one. Rejected.
   - Raw @discordjs/rest + hand-written gateway: that is re-implementing discord.js; violates
     "No unnecessary code". Rejected.

2. **Deployment model**
   - Long-running process (Bun) with in-process scheduler: single service, gateway + REST +
     scheduled jobs all in one; matches the repo's Bun standard (api/ pins Bun; CI pins
     bun 1.3.14). Chosen.
   - Cloudflare Worker with HTTP interactions + cron triggers: loses gateway events, requires a
     public endpoint, and the repo's Worker deployment (api/) is M1's tree — the bot would
     either grow M1's tree or become a second Worker. Rejected (also D11 is single-hostname for
     now, so a second public hostname is friction).

3. **Interaction response strategy**
   - Defer-then-edit on every command vs reply-inline-when-fast: the 3 s deadline is hard
     (invalidated token on miss, source #3) and admin API latency is not bounded by us
     (retries, cold D1). Uniform defer+edit chosen (D-M8-3).

## Prior art found

- discord.js official guide (discordjs.guide) — command-handler and ephemeral patterns; the
  site is a JS-rendered SPA so the concrete facts used here were taken from the official
  Discord developer docs instead (rows 3–9) and verified by the live smoke test (row 12).
- The dashboard module (M11) and the api module (M1) in this repo: their in-process
  real-router test pattern is reused for this module's tests (real admin API over real HTTP,
  mock only the Discord surface).

## Unverified items

- **A real gateway connection** (login with a real bot token, actual guild events): requires
  an owner-held secret (Discord bot token) and a real guild. NOT-RUN honestly; recorded for
  the owner's real-environment checklist. The Discord side is driven in tests through a
  doc-shaped interaction harness (source rows 3–5 shapes) and the REST routes are the ones
  verified in row 9.
- **Command registration against the live Discord API** (PUT /applications/:id/commands):
  same reason. The payload shapes come from row 6 and the builders were smoke-tested (row 12).
- **@discordjs/rest bucket-wait behavior under load** (429 retry pacing with many concurrent
  role calls): not exercised beyond unit-level; role sync is sequential per member and the
  50 rps global budget (row 7) dwarfs the expected volume (hundreds of members).

## Decisions made and why

See DECISIONS-M8.md (each row links back to a source here).
