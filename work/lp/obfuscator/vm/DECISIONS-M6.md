# DECISIONS-M6 — Decision Log (doc.md "Decision authority")

Format per doc: Decision | Options considered | Choice | Why (with evidence)
| Tier | Reversibility | Affects modules. Research-phase entries; the
implementation decisions that bind M5's ISA are deliberately NOT taken
here (see D-M6-4).

| # | Decision | Options considered | Choice | Why (with evidence) | Tier | Reversibility | Affects modules |
|---|----------|--------------------|--------|---------------------|------|---------------|-----------------|
| D-M6-1 | Dispatch-strategy portfolio per build | single fixed strategy; chain-only; tree-only; closure-only; **portfolio {if/elseif chain, balanced comparison tree, closure-per-opcode table} selected per build** | **portfolio, randomly selected per build** | doc §10.2.5 mandates "Dispatch strategies vary per build". Measured (RESEARCH-M6 §4, lua5.4): chain 85-450 ns/instr (linear in N), tree 70-101 (log), closure 95-98 (flat). All within budget vs one-time load cost (~40 ms X25519-class, M3) — so the choice is driven by randomization value, not speed. Chain capped to small ISAs (crossover N≈32-48 measured) | 1 (internal to M6 template) | high — emitter swaps strategy per build | M5 (consumes nothing; provides ISA size N) |
| D-M6-2 | Branch order in generated chains/trees | frequency-sorted (hot opcodes first, fastest); source order; **per-build random permutation** | **random permutation per build** | Frequency-sorting is a measurable win for chains (expected depth ↓) BUT produces a stable per-build fingerprint — the Luraph-v15 lifter textually pattern-matches dispatch shapes (RESEARCH-M6 §2), and a sorted chain is the most recognizable shape of all. Randomization is the product requirement (§10.2.4); cost accepted by D-M6-1 evidence (worst case ~450 ns/instr at N=256 is still negligible at loader scale) | 1 | high | none |
| D-M6-3 | Handler table materialization (closure strategy variant) | literal emitted closures; **runtime-built handler table with numeric re-indexing as an optional per-build variant** | **both; runtime-built is an opt-in per-build variant** | The ONE technique still defeating the public Luraph lifter on v14.8/9 is runtime-built VM-object tables re-indexed numerically (obj[54]) that the lifter cannot bind back to definitions (RESEARCH-M6 §2 last row + caomod2077 README "What is still missing"). Costs: construction time at load + loses literal-shape tooling; measured dispatch cost unchanged (table lookup is the same once built — closure column of RESEARCH-M6 §4) | 2 (variant affects deobfuscation resistance, interacts with M5 container layout if handlers ship separately) | medium | M5 (if the §5.9 container splits handler payloads) |
| D-M6-4 | Research-phase scope discipline | start the template emitter now against a guessed ISA; **wait for M5's IR.md/bytecode spec** | **wait for M5** | M6 depends on "M5 bytecode spec" (doc module table). Building against a guessed ISA risks a full emitter rewrite; the unblocked work (dispatch costs, attack research, integrity-key design, Luraph dissection) is done and logged. glm6 msg'd with the one open container question (per-function AEAD pools vs one pool with offsets — RESEARCH-M6 §5) | 1 (sequencing) | high | M5 (owner glm6) |
| D-M6-5 | VM integrity checksum family | sha256 (M3 primitive); **FNV-1a32 + DJB2 dual 32-bit, same family as M13's stub cache validation** | **FNV-1a32 + DJB2** | §10.2.9 wants checksums that FEED key derivation every interpreter build — sha256 per-build over the whole VM source costs ~µs×KB scale in pure Lua (M3 sha256 is load-time budget only); the dual-32 pair is ~285 ns/B (M13's D-M13-5 measurement, same sandbox class) and already ships audited in the stub template. Unkeyed-by-design is fine here: the checksum mixes into K₀ derivation (attacker-controlled input only changes WHICH garbage decrypts), the trust anchor stays server-side (bundle_sig, M3-verified) | 2 (cross-module primitive reuse; M13 owns the audited implementation) | medium | M13 (source of the audited pair), M5 (container carries the checksums) |

## Notes

- All Tier-1 choices above are research-backed but provisional until M5's
  ISA lands; D-M6-1/2/3 will be re-validated against real Luau executor
  measurements (D2-class follow-up, NOT-RUN list in RESEARCH-M6 §6).
- The misaligned-branch benchmark bug (RESEARCH-M6 §4 methodology note)
  is the first concrete input for M6's future differential harness:
  instruction-count parity between representations must be a GATE.
- Added 2026-10-10 (session 19, research phase). Supersedes: nothing.
