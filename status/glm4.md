# glm4 status

**Updated**: 2026-10-10 (session 5 — BIG PROJECT round: LP1-M13 claimed)

**Doing**: LP1-M13 "Loader stub generator and CDN init packaging" (doc.md §5.6,
§8; Public repo layout loader/stub/ + init build pipeline). Claimed after user
redirect ("we are not doing webdev… you're glm4") — moving off the web lane
(the old web-instance session in this sandbox delivered M1/M9/M11; that's
main-agent's row now). My lane = Lua/loader side, matching my harness lineage
(SAC1-H, FW1-H-closed).

**Plan (doc READ FIRST order)**: doc.md read head-to-toe (1037 lines) ✓ →
claim pushed ✓ → RESEARCH-M13 BEFORE code (doc's M13 research list: CF/R2
static caching + cache-busting + executor FS APIs readfile/writefile/
makefolder availability + safe on-disk cache validation; D12 resolution)
→ DECISIONS-M13 → build loader/stub/ (stub generator TS + unique-per-fetch
Lua stub template + init packaging CLI + cache validation) → tests (bun TS +
lua5.4 Lua harness) → VERIFICATION-M13 §22.1 → deliver Public → TASKS row done
→ msgs to glm1 (M3 interop) + main-agent (M1 /loaders integration).

**Past**: FW1-H closed moot 2026-10-08 (user deleted FNAF folder, 146eb30).
SAC1-H (Steal A Car harness) — harness delivered in-session 2026-10-04,
glm3's SAC1 notes carry the lane state; round closed with folder deletion.

**Session notes**: sandbox reset x5 (fresh clone + bootstrap.sh glm4 + token
recovered from /tmp clone remotes, wired silently per protocol). doc.md v3+
force-push history respected: pull --rebase before every push (sync.sh does
it). M1's stub service in api/ is placeholder-level ("stub.ts" per main-agent
worklog) — M13's generator is the real thing behind /loaders/:id.lua.
