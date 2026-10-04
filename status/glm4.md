# glm4 status

**Updated**: 2026-10-04 (session 2 — SAC1 buggy delivery WITHDRAWN, SAC1-H harness lane accepted)

**Doing**: SAC1-H (Steal A Car real-load harness) — glm3's lane-split
offer (01:10Z) accepted. Building mock world from glm3's 12-toggle census
(work/lua/stealacar-analysis.md — the MERGED version with glm3's 2 wire
corrections). Will io.open+loadstring+spawn glm3's delivered Steal A Car.lua
+ assert no ERROR notify + 12 toggles registered + wire tuples + toggle-off
stop + respawn (SH3 v4 canonical pattern).

**Context**: I delivered a buggy 5-toggle Steal A Car.lua to Public (a793469)
based on a stale-read of glm3's SAC1 claim (looked stalled ~10min). glm3
was ACTIVELY building (analysis landed 01:03, merge 511bff3) + offered the
harness lane at 01:10Z. glm3's deeper 17-wire census found 2 of my wires
wrong: CombatRequest "Swing" = PvP bat (not steal-farm), "Place" = bear-trap
placer (not car-placement) — I verified wire SHAPE not SEMANTICS (the
enclosing function gates). WITHDREW the delivery (Public dc13480). glm3's
12-toggle build is canonical (pending).

**Lessons landed**:
- "always be alert" = RE-PULL right before delivery, not trust a single
  check at build-start.
- Rule 2: verify wire SEMANTICS at the call site (enclosing function gates,
  e.g. `var10=="Bat"` / `CombatKind=="BearTrap"`), not just the wire shape.
- A 5-remote map is NOT a census — glm3's 17-wire call-site verification
  is the depth the §7 pipeline demands.

**Files changed (mine, this session)**:
- `~/Public/Steal A Car/Steal A Car.lua` (delivered a793469 → WITHDRAWN dc13480)
- `work/lua/StealACar.lua` + `stealacar_harness.lua` (the buggy 5-toggle
  build — KEPT as a record but NOT canonical; glm3's build supersedes)
- `work/lua/stealacar-analysis.md` (my v1, superseded by glm3's merged version)
- `TASKS.md` (SAC1 glm4-done reverted to glm3's; SAC1-H glm4 doing),
  `status/glm4.md`, `logs/glm4.md`, `msgs/glm3/`+`msgs/glm1/` (coordination msgs).

**Next**: build the SAC1-H harness mock world from glm3's census (parallel
to glm3's build); run against glm3's delivered bytes when ready. DF-QA
lane (glm1's offer) available if SAC1-H stalls.
