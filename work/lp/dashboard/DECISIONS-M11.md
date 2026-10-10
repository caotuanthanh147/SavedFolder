# DECISIONS-M11 — Dashboard (Module M11)

Format per doc.md "Decision authority" (doc v4). Author: main-agent. Date: 2026-10-10.

| # | Decision | Options considered | Choice | Why (with evidence) | Tier | Reversibility | Affects modules |
|---|---|---|---|---|---|---|---|
| D-M11-1 | Framework | Next.js (doc §4) / SvelteKit | Next.js 16.4.0 + Tailwind 4 + shadcn/ui | doc §4 prescribes Next.js; current stable verified from registry 2026-10-10 | 1 (doc-prescribed) | High | none |
| D-M11-2 | Dev harness data source | mock data / in-process real router / remote Workers | In-process: the gateway route imports the REAL api/ router (M1+M9) and dispatches over node:sqlite; prod switches to the Workers deployment | Every dashboard action is a real, audited admin call — no fake states; the same router bytes run in prod | 1 | High (DASH_DEV_MODE flag) | M1 (no changes — imported as-is) |
| D-M11-3 | Dashboard session | server table / HMAC cookie | Stateless HMAC-SHA256 cookie {adminId, role, exp}, 1h TTL, httpOnly, sameSite=lax | No schema change; Discord's OAuth doc pattern for state binding; cookie forging requires the session secret | 2 | High | none |
| D-M11-4 | TOTP | otpauth v9.5.2 / own RFC 6238 impl | Own impl (api/src/totp.ts) + RFC 6238 Appendix B vectors as tests | Zero-dep consistency; external oracle satisfies §22.1; ~50 lines | 2 | High | M1 admin auth (optional use) |
| D-M11-5 | TOTP secret storage | api admins column (schema) / dashboard store | dashboard-owned `dash_totp` table; CCP-3 proposes admins.totp_secret as the server-side home | §6 schema is immutable without a proposal; interim is fully functional | 2 | Medium | CCP-3 |
| D-M11-6 | Discord OAuth | skip until creds / wire now env-gated | Full start+callback routes: state cookie (CSRF per Discord docs), code exchange, admins.discord_id lookup → session; 503 with a clear hint when env is absent | Spec-complete now; credentials are owner-only | 2 | High | admins.discord_id (§6, unchanged) |
| D-M11-7 | Dev-mode login | credential-free mock / token injection behind DASH_DEV_MODE | Gateway injects the seeded owner token when DASH_DEV_MODE=true (default in the local harness); production MUST set it false | Local demo usable; prod keeps real auth; flag is explicit and documented | 2 | High | none |
| D-M11-8 | Dashboard store | own DB / reuse §6 db | Runs the doc §6 schema (DOC_SCHEMA_SQL, single source from M1) + one dashboard-owned table (dash_totp); SQLite file under db/ (gitignored) | Same contract schema everywhere; the extra table is Tier-1 file layout inside the module folder | 1 | High | none |
| D-M11-9 | Read endpoints gap | fake listings / audit-derived views / additive GET endpoints | CCP-2 (7 read-only endpoints in api/src/adminread.ts, clearly marked additive) | The §16 pages cannot function without listings; "clearly broken" tier-3 carve-out with a proposal the owner may reject | 3 | Medium | M1, M8, M12 (documented in CCP) |
| D-M11-10 | Free-key page placement | separate route / tab in the dashboard shell | "Free-key flow" view in the shell (PUBLIC nav group) driving the real /free/* endpoints with a simulated provider card for the demo chain | The doc's free-key page is per-project public web; the shell view IS that page for the demo project (slug picker); production can mount the same component at /free/[slug] | 1 | High | none |
| D-M11-11 | Demo parameters | doc defaults (30s min, 6h cooldown) / demo values (8s/5s min, 90s cooldown) | Demo values in the harness seed; all env/config-overridable; documented in Settings | The doc defaults make the flow un-demoable in review sessions; server behavior is identical | 2 | High | none |
| D-M11-12 | Polling | websockets / interval refetch | 15-20s intervals on Overview/Audit via the shared useApiData hook (setState only in promise callbacks) | No extra infra; react-hooks purity rules satisfied | 1 | High | none |

## Contract Change Proposals
- CCP-2 + CCP-3: see `api/CCP-M9-M11.md` (filed by both M9 and M11).

## Mind changes
- none this session (first M11 build). Turbopack forced one implementation change (dynamic `import("node:sqlite")` → static import, since the dev server runs on Node): not a decision change, the runtime target was always Node.
