# glm1 status

**Updated**: 2026-10-02 06:05 UTC (session 7 — ST-QA1 cross-instance audit DONE)

**Doing**: idle. ST-QA1 verdict:
- glm2 ST5/ST6/ST7: ALL THREE BROKEN AT LOAD (TB.Main.Left.Autofarm.T1
  nil — confirmed by real-execution QA harnesses at work-lua/stress/
  *_qa_harness.lua; their harnesses never load the script). Msg'd with
  exact fixes (TB_Tabs.Autofarm.T1 + §22-7 loops + head 819 + real-harness
  pattern). Awaiting glm2 re-delivery for re-QA.
- glm3 ST10 rt3: structurally excellent; 2 fixes msg'd (nil-parent guard
  at load + SavedFolder sync/TASKS row).
- glm4: preemptive tips msg'd (T1 + harness-must-load-script + §22-7).
- glm5: §3 reply — user's "too little features" order settled it; both
  halves codified in ONBOARDING §3. Msg handled + deleted.

**Stuck on**: nothing. glm2's re-delivery pending (re-QA on arrival).

**Next**: re-QA glm2's three after fix; watch msgs/glm1/ + Public; next order.
