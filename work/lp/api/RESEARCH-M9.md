# RESEARCH-M9 — Free-key flow (Module M9)

Research completed BEFORE code, per doc.md READ FIRST. All URLs below were opened (page_reader) or returned by live web_search with dates, on 2026-10-10.

## Research Log

| Topic | Source URL | Version / date | Key finding | Used for |
|---|---|---|---|---|
| LootLabs API surface | https://help.lootlabs.gg/en/ | opened 2026-10-10 | FAQ schema on the help index documents: API key generation (Profile → API Key), Content Locker API `POST https://creators.lootlabs.gg/api/public/content_locker` (older, "less versatile"), and the **Redirect API ("Anti-Bypass Link")** — redirects already-created links to new destinations via an `&data` parameter carrying an **AES-256 encrypted** string generated with the API key | D5: LootLabs side of the provider design; completion gate = encrypted redirect chain |
| LootLabs API keys | https://help.lootlabs.gg/en/article/how-do-i-get-a-lootlabs-api-key-1ccz7zy/ | (linked from index, opened via index capture) | API key created in panel (Profile → API Key → Generate); API checks creator's mandatory details | checkpoints.config operator fields |
| Linkvertise bypass landscape | web_search → multilogin.com "Linkvertise bypass" | result dated 2026 | "Most bypass methods rely on front-end manipulation; Linkvertise uses **server-side and behavioral validation**" | Anti-bypass: server-side checks are the primary gate |
| Linkvertise anti-bypass checks | web_search → undetectable.io "Linkvertise Bypass & Multi-Account Safety Guide for 2026" | Mar 30, 2026 | "Linkvertise setups include anti-bypass checks: **referrer validation, JS timer verification, location checks**" | Anti-bypass threat model |
| Bypass services exist today | web_search → github "bypass-linkvertise-lootlabs-lockr" README | Sep 16, 2026 | "sends the link to bypass-links.com, which **resolves it server-side and returns the real destination**" | Threat: destination leak via resolver services → step secrets are NOT secret from a determined attacker; timing + monitoring are the real gates (matches doc §14.5) |
| Bypass-services category | web_search → commandlinux.com, icon-era.com, blog.octobrowser.net, octobrowser/quantumrun results | 2026 | Bypass tools "claim to skip required steps like timers" (commandlinux Apr 27, 2026); "tries to reach the destination link without finishing" (icon-era Aug 26, 2026) | Corroborates threat model with ≥2 independent sources |
| Provider webhooks in general | web_search → docs.stripe.com / developer.bitlabs.ai callbacks | 2026 | Offer/callback networks signal completion via signed postbacks (BitLabs: "offer callbacks ... for each offer complete") — pattern: provider→server callback with a shared secret | checkpoints.config `postback_secret` field for providers that support it |
| TOTP (M9/M11 shared) | https://www.npmjs.com/package/otpauth | v9.5.2, published ~Sep 3, 2026 | One Time Password library (RFC 4226 HOTP / RFC 6238 TOTP) for Node/Deno/Bun/browsers; 112 versions, actively maintained | M11 TOTP option A |
| TOTP spec (authoritative) | RFC 6238 Appendix B test vectors | RFC 6238 | Official 8-digit SHA1 vectors for secret "12345678901234567890" | TOTP implementation test oracle (external source, §22.1) |
| Discord OAuth2 + CSRF | https://discord.com/developers/docs/topics/oauth2 | opened 2026-10-10 | Authorization code grant; **state parameter** binds the request to the user's session (CSRF + clickjacking defense): generate per-request state, store same-origin, compare on return | M11 dashboard OAuth session/CSRF handling |
| Next.js version | npm registry via `bun pm view next` | 16.4.0 (2026-10-10) | Current stable; sandbox runs it | M11 framework choice (doc §4 already prescribes Next.js) |
| D1/SQLite/Workers limits (inherited) | api/RESEARCH-M1.md (prior session) | 2026-10-10 | Workers CPU 10ms/30s/5min, D1 100 bound params/query, batch = transaction | freekey SQL chunking + no long transactions |

## Options compared

**D5 — checkpoint provider verification**
- A) Hardcode per-provider HTTP calls today (Linkvertise/Lootlabs): rejected — the exact server-side verification APIs require creator accounts + keys we do not have; writing guessed endpoints would violate "verify every API you call".
- B) Provider-agnostic verifier interface, per-checkpoint JSON `config`, three provider implementations (`custom`, `linkvertise`, `lootlabs`) where linkvertise/lootlabs validate via our embedded step-secret + timing (+ optional `postback_secret` HMAC when the operator configures one): **chosen** — matches LootLabs' own documented anti-bypass redirect model (their encrypted destination is the completion gate), matches Linkvertise's documented server-side/behavioral validation posture, and stays clean-room.
- C) Trust client-side redirect arrival only (no server checks): rejected — bypass resolver services (evidence above) defeat it in seconds.

**Free attempt token model**
- A) Long-lived stable token per attempt: weaker — replay window spans the whole flow.
- B) Rotating single-use token: every successful `/free/step` issues a new token and overwrites `token_hash`; `/free/claim` consumes it. **chosen** — satisfies §14.5 "single-use short-lived tokens" with zero schema additions.

**Step-secret generation**
- A) Random per step stored in a new column: schema change (Tier 3) for no security gain.
- B) Deterministic `HMAC(freeSecret, "free-step"|attemptId|step)` handed out inside the checkpoint destination URL, never stored: **chosen** — stateless, per-attempt random-seeming, verifiable.

**Fingerprint binding**
- A) Client-supplied fingerprint string: spoofable by script kids.
- B) Server-computed: HWID from executor-injected headers (D10 machinery, already in M1) when present, else body hwid (flagged), else IP-hash only; `fingerprint = sha256(pepper|"fp"|hwid_hash|ip_hash)`: **chosen** — §14.1 "bound to a fingerprint (HWID hash and IP hash)".

**TOTP implementation (M11)**
- A) `otpauth` v9.5.2 dependency: fine library, but adds a runtime dep to a zero-dep tree.
- B) Own ~50-line RFC 6238 impl (HMAC-SHA1 via the existing WebCrypto layer) tested against RFC 6238 Appendix B official vectors: **chosen** — external-source tests satisfy §22.1, no new dependency, works identically in Workers/Node/Bun.

## Prior art found
- Luarmor-style free-key gates (the captured reference service) use checkpoint links + per-IP cooldowns — behavior noted from the HTTPSpy capture in §1 terms only (user-facing); no code, constants, or endpoints copied (clean-room rule).
- BitLabs/LootLabs callback patterns (above) inform the `postback_secret` option.

## Unverified items (owner decisions)
- Exact Linkvertise server-side conversion API parameters: requires a Linkvertise creator account (owner-only: business credentials). Provisional default = timing + step-secret + optional postback HMAC, operator-configurable.
- Free key lifetime + attempt cooldown numbers: business choices. Provisional defaults: 3-day keys, 6h cooldown per fingerprint, 2h attempt TTL, 15 min claim window (env-overridable).
