# M8 — Discord bot (doc.md §15)

discord.js 14.27 bot implementing doc.md §15's exact command surface. Every
privileged action travels through the documented admin API (Bearer token,
server-side role checks — the real gate); the bot never touches the database.
Research first: `RESEARCH-M8.md`. Decisions: `DECISIONS-M8.md`. Admin-API
additions proposed in `CCP-M8.md` (P1 link, P2 key detail, P3 unblacklist,
P4 query-string entry fix).

## Command surface

| Command | Who | Ephemeral | Backing endpoints |
|---------|-----|-----------|-------------------|
| `/redeem key` | user | yes | CCP-M8 P1 `POST /admin/keys/link` + role grant |
| `/getscript` | user | yes | `GET /admin/keys?q=` (strict filter) + CCP-M8 P2 detail + M13 loader URL |
| `/status` | user | yes | `GET /admin/keys?q=` + `GET /admin/users?q=` |
| `/resethwid key_id` | user (own keys only) | yes | CCP-M8 P2 (ownership gate) + `POST /admin/keys/:id/reset-hwid` |
| `/free` | user | yes | link to `LP_BOT_FREE_URL` (M9 owns the flow) |
| `/mykeys` | user | yes | `GET /admin/keys?q=` + `GET /admin/users?q=` |
| `/key create` | admin | **yes** (one-time plaintext) | `POST /admin/keys` |
| `/key revoke` | admin | no | `POST /admin/keys/:id/revoke` |
| `/key extend` | admin | no | `PATCH /admin/keys/:id` |
| `/key info` | admin | yes | CCP-M8 P2 `GET /admin/keys/:id` |
| `/blacklist add` | admin | no | `POST /admin/blacklist` |
| `/whitelist id` | admin | no | CCP-M8 P3 `POST /admin/blacklist/:id/remove` |
| `/stats [window]` | admin | no | M12 `GET /admin/metrics` + `GET /admin/alerts` |
| `/leak lookup value` | admin | yes | M7 `POST /admin/leak/lookup` |

Every command defers first (3 s Discord deadline) then edits. Scheduled job
(hourly): role reconciliation (grant while ≥1 active unexpired key, remove
otherwise) + expiry reminders posted to `LP_BOT_REMINDER_CHANNEL_ID` (never
DMs — Developer Policy, see DECISIONS-M8 D-M8-6).

## Run the tests

```sh
cd bot
bun install
bun test          # 44 checks — REAL api router over real HTTP, doc-shaped Discord fakes
bun run typecheck # tsc --noEmit (strict)
```

The tests drive the real `../api` router in-process (the same §22.1 pattern
as the dashboard's gw route): only the Discord surface is faked.

## Run the bot

```sh
LP_BOT_TOKEN=...            # Discord bot token (owner secret)
LP_BOT_APP_ID=...           # application id
LP_BOT_GUILD_ID=...         # guild for commands + role sync (omit = global commands, no roles)
LP_BOT_API_URL=https://...  # admin API base
LP_BOT_ADMIN_TOKEN=adm_...  # admin-role token (server-side gate for all privileged actions)
LP_BOT_LOADER_BASE=https://...   # loader base (default = API URL)
LP_BOT_FREE_URL=https://...#/free  # free-key page link
LP_BOT_ACTIVE_ROLE_ID=...       # role granted for active keys
LP_BOT_REMINDER_CHANNEL_ID=...  # expiry reminder channel
LP_BOT_REMINDER_LEAD_DAYS=3
LP_BOT_SCHEDULER_INTERVAL_SEC=3600
bun run start
```

## One-time Discord Developer Portal setup (owner)

1. Create the application + bot; copy the token → `LP_BOT_TOKEN`.
2. **Privileged Intents → SERVER MEMBERS: ON** (instant role grant on join;
   RESEARCH-M8 row 8 — needed only below the 100-guild verification bar; if
   left off, roles still converge hourly via the scheduler, D-M8-5).
3. Invite with scopes `bot applications.commands`; bot permissions:
   Manage Roles + Send Messages (channel reminders).
4. `LP_BOT_APP_ID` from General Information; `LP_BOT_GUILD_ID` from the guild.
5. Create the "active key holder" role; copy its id → `LP_BOT_ACTIVE_ROLE_ID`
   (the bot's role in Discord must rank ABOVE that role).

## Integration notes

- **Consumes (no changes needed):** M1 admin surface (`/admin/keys`,
  `PATCH/revoke/reset-hwid`, `/admin/blacklist`, `/admin/users`,
  `/admin/alerts`), M12 metrics, M7 leak lookup, M13 loader route shape
  (`/loaders/<script_id>.lua`).
- **Consumes (CCP-M8, additive, owner to accept):** P1 `POST /admin/keys/link`,
  P2 `GET /admin/keys/:id`, P3 `POST /admin/blacklist/:id/remove`,
  P4 `path: url.pathname + url.search` in the Workers entry (query strings —
  without P4 every filtered admin GET is unfiltered over real HTTP).
- **Provides:** nothing back into other modules' trees; the bot is a leaf
  consumer.

## Not run (honest list)

- Real gateway connection / live command registration (needs the owner's bot
  token + a real guild — owner's real-environment checklist).
- @discordjs/rest bucket-wait behavior under production volume.
- The production Workers deployment of P4 (tested via the harness entry that
  implements the corrected behavior; the one-line api change is code-reviewed
  and covered by the api's own suite staying green).
