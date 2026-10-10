# CCP-M9-M11 — Contract Change Proposals from modules M9 and M11

Filed 2026-10-10 by main-agent (author of M1, M9, M11). Per doc.md "Decision
authority" Tier 3: the current contract stands in the main code; the patches
below are additive and clearly marked. The owner may accept or reject each.

---

## CCP-2 — Admin read endpoints for dashboard pages

**Contract and section affected:** doc.md §16 "Admin API" endpoint table.

**Problem:** The §16 endpoint table lists only mutating endpoints (create, patch, revoke, reset, blacklist, versions, activate, nodes, protocol-versions, analytics, audit), while the §16 "Dashboard pages" list requires rendering Keys (search, filter, bulk), Scripts (build status, versions), Users (HWID and session history), Blacklist, Resellers, Nodes and protocol versions. A dashboard over a write-only API cannot display anything — following the contract as written produces a clearly broken module.

**Proposed change:** add read-only endpoints to the §16 table (implemented in `api/src/adminread.ts`, gated by the same `authenticate()`):

| Endpoint | Returns |
|---|---|
| `GET /admin/keys` | paged key rows (never key_hash), filters tier/status/search, resellers see only their own |
| `GET /admin/scripts` | scripts + versions + game routing |
| `GET /admin/blacklist` | blacklist rows |
| `GET /admin/nodes` | node rows |
| `GET /admin/protocol-versions` | protocol rows |
| `GET /admin/sessions` | session rows (watermark, hwid/ip hashes), optional key_id filter |
| `GET /admin/admins` | admin rows without token hashes (owner only) |

**Impact:** M1 (one new file + router rows), M8 bot `/stats`-style commands can reuse them, M12 monitoring can scrape them. No existing endpoint changes.

**Migration:** none — additive.

**Risk if not changed:** the dashboard ships against the audit-log-derived fallback (worse UX, more queries), or module owners keep inventing private read endpoints that drift.

---

## CCP-3 — admins.totp_secret column for server-side optional TOTP

**Contract and section affected:** doc.md §6 `admins` table; §16 auth ("Discord OAuth plus optional TOTP").

**Problem:** §16 requires optional TOTP for dashboard auth, but the §6 admins table has no column to store an enrollment secret. The dashboard currently keeps enrollments in its own `dash_totp` table (Tier 1 file layout), which means the secret lives outside the API's security boundary and cannot protect admin API tokens themselves.

**Proposed change:** `ALTER TABLE admins ADD COLUMN totp_secret TEXT;` (nullable, base32, set only through an owner-gated enrollment flow) and an optional TOTP check inside `authenticate()` when the column is non-null.

**Impact:** M2 (one migration line), M1 (authenticate gains a check), M11 (enrollment UI posts to the admin API instead of its own table).

**Migration:** nullable column, zero backfill; dash_totp rows port on first enrollment.

**Risk if not changed:** TOTP protects only the dashboard cookie flow, not direct admin API token use; acceptable for launch, weaker long-term.

---

## CCP-1 (existing, unchanged) — §5.5 server-nonce wire position

Already filed in `api/DECISIONS-M1.md` during M1 session 2; standing, awaiting owner review. Not re-litigated here.
