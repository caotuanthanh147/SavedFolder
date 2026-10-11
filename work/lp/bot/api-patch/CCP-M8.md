# CCP-M8 — Admin API additions required by the Discord bot (doc.md §15)

Status: **PROPOSAL** (Tier 3 per doc.md "Decision authority"). Current contract stands; the
implementation is shipped as a clearly marked additive patch (`api/src/botadmin.ts` + 3 route
rows in `api/src/router.ts`, tagged `// CCP-M8`) that the M1 owner can accept or reject as-is.
No existing M1 handler is modified. M1 owner (main-agent) pre-notified by msg at delivery.

Why Tier 3: these are new endpoints other modules depend on (doc merge checklist: "Bot and
dashboard only use documented admin endpoints" — so the bot's endpoints must BE documented).

## P1 — POST /admin/keys/link (redeem: link a Discord id to a key by plaintext)

- **Contract and section affected:** §16 Admin API (additive); §15 "Linking a Discord ID to a
  key on redeem".
- **Problem:** No documented endpoint sets `keys.discord_id`. The bot cannot use
  `POST /check_key` as a probe (it performs the atomic HWID bind-or-match, consuming the key's
  HWID slot with the bot's identity), and `GET /admin/keys?q=` does not match key plaintext
  (only id/note/discord prefixes over non-hash columns).
- **Proposed change (exact):**
  - Auth: `Authorization: Bearer adm_...`, roles owner/admin (same gate as PATCH /admin/keys/:id).
  - Body: `{ "key": "<plaintext YURI-XXXXX-...>", "discord_id": "<snowflake digits>" }`
    - `key` validated against the api's own `KEY_PATTERN` + checksum (`keyPassesChecksum`) —
      same normalization path as check_key.
    - `discord_id` validated `^\d{1,32}$` (same rule the resellers handler applies).
  - Flow: hash the plaintext (`hashKey(key, pepper)`) → look up the keys row → 404
    `{"error":"not_found"}` if absent (generic; no leak of which field failed) → reject
    blacklisted discord ids (kind `discord`, same value-hash formula as the auth flow:
    `sha256(pepper + "|discord|" + id)`) with 403 `{"error":"blacklisted"}` → if the row is
    already linked to a different discord id: 409 `{"error":"already_linked"}` → if linked to
    the same id: 200 idempotent → else UPDATE keys.discord_id, audit `admin.key.link`
    (target = key id, detail = discord id).
  - Response 200: `{ "ok": true, "id": "<key id>", "tier": "...", "status": "...",
    "expires_at": <unix sec | null>, "already": <bool> }` — the bot needs tier/status/expiry
    to decide the role grant and to answer the user without a second call.
  - Revoked/expired keys REMAIN linkable (status is relayed to the user; role is only granted
    for `status === "active"` and `expires_at === null || expires_at > now`). Rationale: the
    redeem link is identity bookkeeping, not validation — the runtime auth flow still gates
    everything.
- **Impact:** M1 gains one additive handler (~60 lines) + one route row. M8 builds /redeem on
  it. Dashboard could reuse it later (Users view actions).
- **Migration:** none (additive).
- **Risk if not changed:** /redeem cannot exist; Discord-ID↔key linking (doc §15 bullet 1)
  has no implementation path.

## P2 — GET /admin/keys/:id (key detail incl. entitlements)

- **Contract and section affected:** §16 Admin API (additive); §15 /key info, /getscript.
- **Problem:** `GET /admin/keys?q=<id-prefix>` returns the row but NOT the key_scripts
  entitlements, and prefix search can collide (id LIKE, note LIKE, discord LIKE).
- **Proposed change (exact):**
  - Auth: same as GET /admin/keys (owner/admin/reseller/support; reseller scoped to own keys).
  - Response 200: the KeyRow shape of GET /admin/keys (id, project_id, tier, status,
    hwid_bound, hwid_resets, discord_id, roblox_user_id, note, total_executions, created_by,
    created_at, expires_at, first_used_at, last_used_at) PLUS `"scripts": [ { "script_id":
    "...", "name": "...", "keyless": bool } ]` (INNER JOIN key_scripts × scripts).
  - 404 `{"error":"not_found"}` when the id does not exist or a reseller asks for a key they
    did not create.
- **Impact:** additive handler + route row; M8 /key info + /getscript consume it.
- **Migration:** none.
- **Risk if not changed:** /getscript entitlement listing would require N+1 hacks over the
  list endpoint and /key info would show no entitlement detail.

## P3 — POST /admin/blacklist/:id/remove (whitelist)

- **Contract and section affected:** §16 Admin API (additive); §15 /whitelist.
- **Problem:** Blacklist has add + list only. Removing an entry (e.g. false-positive HWID ban,
  resolved dispute) is impossible through the documented surface; `POST /admin/blacklist`
  is explicitly not idempotent-remove.
- **Proposed change (exact):**
  - Auth: owner/admin (same as POST /admin/blacklist).
  - Body: none.
  - Flow: DELETE row by id → 404 `{"error":"not_found"}` if absent → audit
    `admin.blacklist.remove` (target = removed entry id, detail = kind).
  - Response 200: `{ "ok": true }`.
  - Naming follows the existing mutation convention (`POST .../:id/revoke`,
    `POST .../:id/reset-hwid`) rather than REST DELETE, for surface consistency.
- **Impact:** additive handler + route row; M8 /whitelist consumes it.
- **Migration:** none.
- **Risk if not changed:** /whitelist command from doc §15 cannot exist; blacklist management
  requires direct DB access (audit-less).

## P4 — BUG: Workers entry drops query strings (blocks every filtered GET over real HTTP)

- **Contract and section affected:** §16 Admin API (all GET endpoints with filters), §5.3
  surface; `api/src/index.ts` request entry.
- **Problem (evidence):** `api/src/index.ts` line 82 builds `RequestInput.path` from
  `url.pathname` alone — `url.search` is discarded. Every read handler that filters
  (`queryOf(input.path)` in adminread.ts/ops.ts: `/admin/keys?status=...&q=...`,
  `/admin/metrics?window=...`, `/admin/blacklist?kind=...`, `/admin/audit?...`) works in the
  in-process tests only because those tests pass the query inside `input.path` directly.
  The bot is the first REAL HTTP client of the admin API: against a production Workers
  deployment, `GET /admin/keys?status=active&q=<discord_id>` would arrive as
  `GET /admin/keys` with no filters at all (and the default limit of 50). Verified by code
  reading of index.ts (the entry) vs router.ts's own comment ("handlers that need the query
  keep it in `input.path`") — the two disagree.
- **Proposed change (exact):** in `api/src/index.ts`, replace
  `path: url.pathname,` with `path: url.pathname + url.search,` — one line, tagged
  `// CCP-M8 P4`. Applied in-place with the tag (M12 precedent D-M12-9: cross-module fix,
  owner pre-notified, clearly marked, trivially revertible); the owner can revert by the tag.
- **Impact:** M1 only; no handler changes (queryOf already parses `input.path` with "?" split).
  All existing in-process tests are unaffected (they never relied on the entry).
- **Migration:** none.
- **Risk if not changed:** every query-filtered admin GET silently returns unfiltered data
  to real HTTP clients; the bot cannot filter by discord id, status, or window in production,
  and pagination (`limit`/`offset`) is ignored.
- Note: the bot's test harness (bot/test/helpers.ts) serves the router through a local HTTP
  entry that already passes `pathname + search` — i.e. it tests the corrected behavior this
  proposal pins; without P4 accepted, production behavior differs from the tested behavior.

## Reversibility / rollback

P1–P3 are additive: deleting `api/src/botadmin.ts`, the 3 router rows, and the CCP docs
restores M1 exactly (the patch is a new file — `git revert` of the single commit also works).
The bot degrades honestly without them: /redeem, /key info, /getscript and /whitelist reply
"admin API endpoint not available" (501 path) instead of failing silently. P4 is a one-line
entry fix; reverting it restores the (buggy) status quo.
