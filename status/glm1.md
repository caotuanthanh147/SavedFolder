# glm1 status

**Updated**: 2026-10-09 (session 16 — STC1 Smash the City DELIVERED Public 3e60f41)
**Doing**: idle-alert (watchers + Public polling; msgs/glm1 + TASKS).
**Last**: STC1 full pipeline in one session (claim a87e8ce → analysis 64a7837 → build → harness 40/40 → gates → Public 3e60f41 → wrap). PST1-QA closed moot (PST deleted upstream). Template 4f0e766 (945 lines, yielding TweenTo) re-synced + noted for all.
**Lanes**: STC1-H open for any glmN.

## Session 17 — 2026-10-10 (CS1 7 Days Cat-Sitting DELIVERED)
**Doing**: idle-alert (watchers on, poll + watch_public).
**Done this round**: CS1 full pipeline after 5th sandbox reset: re-clone+bootstrap
(guide 590 + Template 945 re-read head-to-toe, Rule 18), analysis
(catsitting-analysis.md: 26-remote wire table, 48-prompt world model, ESC census
— workspace-attr oracle headline), build SevenDaysCatSitting.lua (7 features,
inline resolution per the user's clean-code directive this round — no
EnsureModules/PopulateRemotes/ConnectListeners wrappers), REAL-LOAD harness
56/56 ×3 (caught 7 attachment-layer path bugs + the harness's own §15-class
mock bugs — all documented in lessons). DELIVERED Public 1d5c1b0 both folders.
Parallel CS1-B lane (main-agent, user-direct) delivered CatSitting.lua d82c55a —
FW1 both-land; their 2 cross-check corrections adopted + verified; reply msg'd.
**Stuck on**: nothing.
**Files**: work/lua/SevenDaysCatSitting.lua + catsitting_harness.lua +
catsitting-analysis.md (canonical); Public cat/ both folders (delivery).

## 2026-10-10 — LP1-M3 session (status repair: session ended context-exhausted before status update)
**Doing**: M3 follow-ups (queued: M1 wire adoption, D2 benchmarks, M13 entry assembly).
**Done**: LP1-M3 DELIVERED Public ed8d843 — loader/{crypto,sdk,init}/ (11
pure-Luau crypto modules 16-bit-limb <2^53, SDK sync/check_key x-proof+x-sig,
handshake client X25519+HKDF+AEAD+bundle_sig) + contracts/ (machine-extracted
RFC vectors, proof_spec C1-C6 + M1 cross-check incl. payload-key
client-feasibility flag) + tests/run.lua 88/88 x3 lua5.4. Canonical work/lp/.
**Bookkeeping gap**: that session never updated this status file, logs/glm1.md,
or the TASKS M3 row status — repaired 2026-10-10 PM.

## 2026-10-10 PM — session 18: force-push #3 response + obfuscator corpus run
**Doing**: idle-alert (watchers on; poll msgs/glm1 + TASKS + Public).
**Done this round**: user ask "test your obfuscator on work/lua files" —
M4 front-end reviewer-run: baseline 70/70 + tsc clean; work/lua 50/50
(2.24MB/424k tok); user's obfsucatortest 131-file corpus (Public 4e974c3,
deleted at 94e337d, git-retrievable) 129/130 — sole reject Dupe.lua 465:23
= corrupt file (raw \n in quoted string, od-verified), not a lexer bug;
luagrapheg.lua (1.1MB real Luraph sample at Public root) accepted 2,036
tok/75ms. Zero lexer defects ~12MB/1.95M tok. Force-push #3: all module
trees dropped from origin/main; M3 re-landed Public 53525bb (byte-identical
to ed8d843, no force-push); msgs to glm3/glm6/main-agent/glm4 (re-land
notices + corpus/Luraph intel + M13 entry ack); TASKS M3 row -> done,
M4 row reviewer note.
**Stuck on**: nothing. M1 init-plaintext fix (CCP-1) still pending on
main-agent side — blocks my handshake.lua wire adoption.
**Files**: TASKS.md rows (M3, M4), msgs/{glm3,glm6,main-agent,glm4}/,
logs/glm1.md, this status; Public 53525bb (M3 re-land).

## 2026-10-10 PM — session 19: M3 session 2 (M1 wire adoption) + M6 claim + research phase
**Doing**: idle-alert (watchers on; poll msgs/glm1 + TASKS + Public).
**Done this round**: (1) M3 s2 DELIVERED Public ee3b58f — handshake.lua
on M1's landed 617d386 wire formats (init serverPub|serverNonce|ct|tag,
AEAD nonce serverNonce[0..12), aad scriptId|serverPub|serverNonce;
payload nonce|ct|tag w/ payloadKey HKDF(sessionKey, fromHex(build_hash),
"payload-key"|fromHex(watermark_id)), aad scriptId|sessionId-raw; init
plaintext requires build_hash+watermark_id); mock server produces the
real shapes; contracts/test_vectors.json + x25519/ed25519 sections for
cross-m3 (gen_vectors_ext.lua: machine transfer, impl-verified before
write, zero drift); run.lua 95/95 x3 + fresh-run on delivered bytes; msg
to main-agent. proof_spec RESOLUTION section (C1/2/4/5/6 superseded).
(2) M6 CLAIMED + research phase DELIVERED Public 4f25733 — RESEARCH-M6
(opened: Luraph-v15 devirtualizer techniques + counters, Ironbrew2 pair,
Luraph sample dissection) + dispatch benchmark (lua5.4: chain linear
85-450ns, tree log 70-101, closure flat 95-98, str-fetch +15-28ns;
misaligned-branch bug caught by instruction-count parity) + DECISIONS-M6
(D-M6-1..5); container question msg'd to glm6.
**Stuck on**: nothing. M6 implementation waits on glm6's IR.md (by design,
D-M6-4).
**Files**: work/lp/{loader/init/handshake.lua, tests/*, contracts/*} +
work/lp/obfuscator/vm/* (canonical); Public ee3b58f + 4f25733.

## Session 20 (2026-10-10, M6 implementation — user signal: "glm 6 is done")

- LP1-M6 **DELIVERED** Public 7747a0a (+ CCP-M6 follow-up 98095c6 after
  two origin races vs glm3's M4 s4 printer 44f04bf and IR.md 26fa49d —
  fetch+rebase protocol, never force-push).
- M6 = VM runtime generator: per-build Lua 5.1-syntax-safe interpreter
  templates consuming the LPVB container. 63/63 tests; differential vs
  real lua5.4 AND M5-TS interpreter, all strategies; parity gate
  enforced; tamper never oracle-equal.
- Key design: entry.c per-session constKey (CCP-M6 + RUNTIME-M6 for the
  M1/M13 lanes); decoy-not-branch integrity (item 9); memoized chain
  keys (order-independent lazy pools); %*-aware wrapped env.
- Open: CCP-M6 ruling (main-agent), M7/M12 unclaimed, corpus end-to-end
  blocked on glm3 parser, D2 executor runs.
- Canonical work/lp/m6/. Next-in-lane candidates: M7 (anti-tamper) or
  M12 (repo pipeline) if unclaimed on next read; M3 follow-ups (D2
  benchmarks, M13 entry assembly) still open.
