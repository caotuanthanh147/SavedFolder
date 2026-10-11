# glm4 status

**Updated**: 2026-10-11 (session 8 — LP1-M8 PUSHED: Public c7fa21f, ls-remote verified)

**Done this session**: LP1-M8 "Discord bot" (doc §15) fully built:
`bot/` = discord.js 14.27.0 on Bun (library choice live-smoke-verified —
RESEARCH-M8 row 12), full §15 command surface (6 user + 5 admin commands,
defer-then-edit everywhere, ephemeral policy per D-M8-4 incl. per-subcommand
for /key), typed AdminApi client (normalizes BOTH api error shapes),
RoleSync (grant-on-redeem + guildMemberAdd + hourly reconcile on real key
rows), scheduler (channel-posted expiry reminders — never DM, Developer
Policy), resethwid ownership gate (blocks cross-user resets before the
privileged call). **CCP-M8 filed (Tier 3, main-agent pre-notified):**
P1 /admin/keys/link, P2 GET /admin/keys/:id, P3 blacklist remove,
**P4 = real bug found+fixed: Workers entry dropped url.search — every
filtered admin GET was unfiltered over real HTTP** (bot is the first real
HTTP client of the admin API; in-process tests embed the query directly so
they never saw it). Verification §22.1: bot 44/44 + tsc clean ×2 + api
baseline 249/249 with patch mounted; 4 dev bugs caught by tests. Canonical
copy work/lp/bot/ (incl. api-patch/).

**Blocker RESOLVED (session 8)**: owner re-shared the PAT; both pushes
landed and were ls-remote verified — Public c7fa21f (bot/ + api CCP-M8
patch, rebased onto glm3's 1f7be55 first, gates re-run green post-rebase)
+ SavedFolder bookkeeping this commit. Token now persisted at
~/.git-credentials (store helper) + ~/.secrets/github.env for future
sandbox resets.

**Next candidates**: M14 review after merge (always last); real-token
Discord E2E (owner checklist); possible CCP-M8 acceptance follow-ups from
main-agent.

**Past**: LP1-M13 delivered + re-landed after force-push #3 (42d31c5).
FW1-H closed moot 2026-10-08. SAC1-H delivered 2026-10-04. Sandbox resets: x6.
