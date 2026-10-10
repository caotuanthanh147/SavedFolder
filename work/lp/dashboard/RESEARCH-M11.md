# RESEARCH-M11 — Dashboard (Module M11)

Research completed BEFORE code, per doc.md READ FIRST. Sources opened on 2026-10-10 (details in api/RESEARCH-M9.md for the shared rows).

## Research Log

| Topic | Source URL | Version / date | Key finding | Used for |
|---|---|---|---|---|
| Framework version | npm registry (`bun pm view next`) | next 16.4.0 (2026-10-10) | Current stable; sandbox runs it in dev | D-M11-1 framework |
| Discord OAuth2 + CSRF | https://discord.com/developers/docs/topics/oauth2 | opened 2026-10-10 | Authorization code grant; **state parameter** must bind the request to the user's session (generate per request, store same-origin, compare on callback) — Discord's own docs recommend it for CSRF + clickjacking defense | OAuth routes: state cookie, httpOnly, compared in callback |
| TOTP library option | https://www.npmjs.com/package/otpauth | v9.5.2 (~Sep 3, 2026) | RFC 4226/6238 OTP library for Node/Deno/Bun/browsers, actively maintained | Compared against own impl (D-M11-4) |
| TOTP spec | RFC 6238 Appendix B | RFC | Official 8-digit SHA-1 vectors for the 20-byte ASCII secret | Test oracle for api/src/totp.ts (§22.1 external source) |
| Session/CSRF handling | Discord OAuth2 doc (state) + doc.md §16 auth requirements | 2026-10-10 | HMAC-signed stateless session cookie binding {adminId, role, exp}; httpOnly; same-site lax | src/server/session.ts |
| Dashboard↔API shape | doc.md §16 endpoint table + §16 page list | doc v4 | The endpoint table is write-only while the pages need listings → CCP-2 additive read endpoints | adminread.ts + CCP-M9-M11.md |
| Next.js route caching | next dev runtime warnings (this session) | Next 16 | `cacheComponents` conflicts with `export const dynamic = "force-dynamic"`; dynamic GET handlers use `await connection()` instead | route handlers |

## Options compared

**In-process vs remote API (dev harness vs prod)**
- A) Dashboard ships with mock data: rejected — hides integration truth.
- B) Dashboard runs the REAL api/ router in-process over node:sqlite for local/dev (`DASH_DEV_MODE`), and points at the Workers deployment in prod: **chosen** — every rendered mutation is a real audited admin call; the same router code as production.
- C) Dev harness requires a running Workers instance: rejected — unusable in sandboxed dev environments.

**Auth (§16)**
- A) Token-only: workable but §16 prescribes Discord OAuth + optional TOTP.
- B) All three paths: admin token login (+TOTP when enrolled), Discord OAuth (env-gated, state-checked), dev-mode token injection for local demo: **chosen** — spec-complete, each path real.

**TOTP**
- A) otpauth v9.5.2 dependency: good library, adds a runtime dep.
- B) Own RFC 6238 implementation (~50 lines, HMAC-SHA1 via the existing WebCrypto layer) tested against Appendix B official vectors: **chosen** — zero-dep consistency with the api/ tree; the research-sourced vectors satisfy §22.1.

**Session state**
- A) Server-side session table: schema addition for no security gain.
- B) Stateless HMAC cookie (1h TTL): **chosen**.

## Prior art found
- Discord OAuth2 official docs (above) for the exact state/CSRF pattern.
- otpauth (above) studied for the TOTP API shape (otpauth URI params: issuer/secret/algorithm/digits/period).

## Unverified items
- Real Discord application credentials (owner-only: app id/secret) — OAuth routes are complete but runtime-gated until env vars are set.
- TOTP secret storage location: dashboard-side table today; CCP-3 proposes admins.totp_secret for server-side storage if the owner prefers.
