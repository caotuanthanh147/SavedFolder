# VERIFICATION-M8 — §22.1 transcript

Module: M8 Discord bot (`bot/`) + CCP-M8 additive api patch
(`api/src/botadmin.ts`, 3 router rows, 1-line entry fix in `api/src/index.ts`).
Every claim below has the exact command and its output. Ran on Bun 1.3.14,
TypeScript 5 (tsc strict), discord.js 14.27.0.

## Commands and outputs

```sh
cd Public/bot && bun install && bun test
```
```
 44 pass
 0 fail
 136 expect() calls
Ran 44 tests across 4 files. [340.00ms]
```

```sh
cd Public/bot && bun run typecheck   # tsc --noEmit (strict)
```
```
tsc: clean (0 errors)
```

```sh
cd Public/api && bun test            # baseline regression with the CCP patch mounted
```
```
 249 pass
 0 fail
 1208 expect() calls
Ran 249 tests across 18 files. [7.12s]
```

```sh
cd Public/api && bun run typecheck
```
```
tsc: clean (0 errors)
```

discord.js-under-Bun smoke evidence (RESEARCH-M8 row 12, run this session):
`new Client({intents})`, `SlashCommandBuilder` incl. `setDefaultMemberPermissions`,
`REST`, `Routes.guildMemberRole("g","u","r")` → `/guilds/g/members/u/roles/r`,
`MessageFlags.Ephemeral === 64`, `EmbedBuilder` — all construct/return under
Bun 1.3.14 with discord.js 14.27.0.

## What the 44 checks actually exercise

**Test harness shape (§22.1 "tests from outside sources"):** the admin API
side is the REAL `api/` router — same schema, same handlers, same route
table — served over real HTTP through an entry that implements CCP-M8 P4's
corrected behavior (`pathname + search`). The Discord side is a fake built to
the official interaction doc shapes (defer-then-edit, ephemeral flag 64,
subcommands, options). Assertions are on protocol outcomes (status codes,
envelope/error codes, db rows, audit rows), never on the bot's own
re-implementations.

- **ccp-endpoints.test.ts (11):** P1 link happy/idempotent/409-conflict/403
  blacklisted/404 unknown/400 malformed/403 reseller-role + pepper-hash
  storage proof + audit row; P2 detail incl. entitlements + 404 + reseller
  scoping; P3 remove + audit + 404; P4 query filtering over HTTP;
  in-process makeSignedInput dispatch regression.
- **commands-user.test.ts (14):** /redeem (link + role grant + ephemeral;
  self-idempotent; stranger 409; unknown 404; garbage 400; blacklisted 403;
  expired-key no role grant); /mykeys + /status (strict discord filter, D-M8-15
  note-collision negative); /getscript (loader links); /resethwid (own-key
  reset + real 7-day cooldown message; cross-user reset BLOCKED with the db
  counter proving the privileged call never fired); /free (with/without URL).
- **commands-admin.test.ts (11):** /key create (2 keys, one-time plaintext,
  ephemeral, plaintexts re-validated through the REAL signed check_key gate
  → KEY_VALID; unknown project 404; foreign script 400); /key revoke + extend
  (db row assertions); /key info (entitlements embed); /blacklist add +
  /whitelist round-trip + audit; hwid-requires-project 400; /stats (real M12
  metrics fields); /leak lookup (watermark → key trace through the real M7
  endpoint; no-watermark negative); reseller-vs-admin server-side role gate.
- **roles-scheduler.test.ts (8):** keyGrantsRole truth table (expiry/status
  edges); grantIfActive (grant → revoke → noop; no_role_config/no_guild
  degradation); full reconcile pass (grant actives, remove revoked, reminder
  post w/ masked ids + no plaintext); lead-window crossing (10d key absent →
  present after clock advance); no-channel no-post; expiry-past-now role
  removal.

## Not run (honest list)

- Real Discord gateway connection, live command registration, real guild role
  ops, real channel posting — require the owner's bot token and a guild;
  recorded for the owner's real-environment checklist (doc §22.1's
  real-environment table is executor-focused; the Discord equivalents are:
  login + READY, command appears after registration, role granted on redeem,
  reminder posted at the scheduled pass).
- Production Workers deployment of the P4 one-liner (the harness entry
  implements the corrected behavior; the api suite stays green with the
  change and the line is documented in CCP-M8.md for the owner's review).
- Load behavior of @discordjs/rest bucket waits (global 50 rps budget vs
  expected hundreds of role ops/hour — see RESEARCH-M8 "Unverified").

## Bugs found and fixed during development (evidence of the tests working)

1. **Envelope error shape missed:** the first test run failed /resethwid's
   cooldown path with "Admin API unreachable" — the api's 429 RATE_LIMITED
   answers the signed envelope `{code, data:{retry_after_sec}}`, not
   `{error}`. `AdminApi.call` now normalizes both shapes (src/adminapi.ts).
2. **Per-subcommand ephemeral:** /key create's defer was non-ephemeral (the
   spec table was per-command only) — the ephemeral assertion caught it;
   `isEphemeral(spec, sub)` added (D-M8-4).
3. **Test-side float-precision snowflakes:** fresh test users collided
   identically above 2^53 (`600…001 + 1 === 600…001`), which made every user
   "the same user" and reproduced as spurious already-linked/blacklisted.
   Counter moved below 2^53 with a comment (test/commands-user.test.ts).
4. **P4 discovery:** the api Workers entry dropped query strings for every
   filtered GET — found while designing the bot's HTTP client, filed as
   CCP-M8 P4 with the one-line marked fix (api/src/index.ts).
