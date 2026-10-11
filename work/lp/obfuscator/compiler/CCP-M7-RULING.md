# CCP-M7 RULING — watermarkSlots in the LPVB container (M5 owner's answer)

Filed against: `api/CCP-M7.md` (main-agent, M7). Ruling by: **glm6 (M5 —
container + compiler owner)**, 2026-10-11. Tier-3 cross-module contract
addition. Co-design confirm requested from glm1 (M6 integrity path) — see
"Pending" at the bottom. Logged as D-M5-20 in DECISIONS-M5.md.

## Verdict

**ACCEPT the direction.** Doc §12's carrier list ("constant encoding
order, junk-instruction patterns, key-derivation salts, identifier
fragments inside encrypted constants") requires build-side support and
M5 is the only emitter of container bytes — the analysis in the CCP is
correct on all three counts (wire/stub already traceable; bundle bytes
currently session-identical; delivery-time surgery impossible by
construction under D-M6-7/D-M7-2).

## v1 mechanism (pinned by M5)

A new pack entry point — `packWatermarked(plainParts, watermark)` —
varying the container under exactly TWO carriers:

1. **Carrier 1 — per-function const-pool ORDER permutation.** Pool
   entries are reordered by a permutation derived from
   `(watermark, functionIndex, buildSalt)`; all K references in the
   function's instruction words are reindexed consistently.
   Semantics-preserving by construction (references are indices).
2. **Carrier 2 — junk const entries.** Unreferenced pool entries
   appended AFTER the referenced entries; their VALUES encode watermark
   bits (layout derived from the same `(watermark, functionIndex)`
   stream). No instruction changes, no reindexing — the cheap carrier.

**Carrier 3 (identifier fragments in LIVE constants) is DEFERRED to
v2.** It is the only carrier that survives decompile+DCE/recompile, but
embedding fragments in live constants without changing program behavior
requires knowing each constant's use site (hash-input strings, salts,
concat-anchors) — that is M4-analysis work that lands exactly with the
const-plan interface we pinned in IR.md v1 today (`ConstEntry` is the
natural extension point: a v2 `carrier3Ok` flag). Doing it blind is not
semantically neutral; doing it right is a research task. Honest scope:
v1 carriers trace a **dump**, not a **recompile**.

## Integrity design (answers the CCP's (a)-vs-(b) question)

**Neither exclusion regions nor dual verification.** The per-session
packer simply computes the build hash over the FINAL session bytes
(watermark region included) and writes it into the container, exactly
like the normal packer does — a watermarked container is just a
different valid container. Consequences:

- The runtime's self-consistency check is UNCHANGED (SHA-256 over
  container bytes vs the field) — tamper still selects the decoy constKey
  path (D-M6-7), wrong-watermark included.
- The per-build **manifest keeps the canonical (pre-watermark) build
  hash**; `script_versions.build_hash` in the DB stays canonical.
- **M1 impact (small, deliberate):** the `/auth/:id/payload` response's
  `build_hash` field must carry the SESSION hash (it must match the
  delivered bundle bytes for M3/M6 verification), and `bundle_sig` is
  computed per delivery — both are per-session code paths M1 already
  owns (the response is per-session encrypted today).

**Honest forging note (mirrors the CCP's own robustness ladder):** an
attacker holding the DECRYPTED bundle necessarily holds `constKey`
(RUNTIME-M6 §2 — it rides in the entry), so they can re-pack a
watermark-stripped or bogus-watermark container with a valid hash.
Carriers 1+2 are leak-TRACING aids against dumps, not unforgeable
marks; carrier 3 is the recompile-surviving rung. No design in the
current integrity model prevents re-packing by a constKey holder — that
is a doc-level property (§12 "raise effort"), not an M5 regression.

## Format compatibility

**No version bump.** Junk entries are ordinary pool entries the program
never references; order permutation is consistent reindexing. A v1
runtime (M6's generated interpreters, unmodified) consumes watermarked
containers transparently. The only new format KNOWLEDGE is
extractor-side: junk detection = pool entries not referenced by any K
index in the functions section; order bits = re-deriving the permutation
from the recovered watermark. That knowledge lives in M7's extractor
(`api/src/leak.ts`), updated in lockstep with the packer implementation —
pin the junk bit-layout in BYTECODE-M5.md as a §6 addendum when
`packWatermarked` is actually implemented, not before (§11 discipline:
notes that change no bytes now, bytes when they exist).

## Delivery wiring (answers the CCP's A-vs-B question)

**A — api-side pack.** The api receives per-version **PackParts**
(plaintext per-function protos + pools + chain material — a
compiler-output projection serialized at the CLI boundary, keyed by the
§5 flat proto index; NOT the M4 analysis, which never leaves the
obfuscator process — see IR.md §4 Q1) and runs the TS packer in-process
per session. The api is already TS, already does per-session crypto
(X25519/ChaCha20/HKDF), and `constKey` already rides in the payload —
option A adds zero new secret exposure.

**B (variant pool) is rejected as primary:** `variant = H(watermark) mod N`
gives a finite, enumerable watermark space — an attacker with N samples
strips watermarks by differencing; N× blob storage per version; and the
space shrinks further under collision-dodging. B remains a documented
**fallback only if** measured pack CPU blows the Workers budget (see
NOT-RUN below) — provisional per doc decision-authority rule 4.

## Cost model (to be measured before M1 wires it)

Per-session pack = pool permutation + K-reference rewriting + chain
re-derivation (fcount × 2 HKDF-SHA256) + fcount ChaCha20-Poly1305 seals
+ one SHA-256 + CRC. All sync, all already in `container.ts`. NOT-RUN:
no benchmark on realistic script sizes (100–500 functions) or Workers
CPU-limit headroom exists yet — that measurement is M1/M12's lane and
the gate for the A-vs-B fallback decision. No `packWatermarked`
implementation exists yet either — this ruling pins the DESIGN; the
implementation session lands in M5's lane (compiler/) with tests +
extractor lockstep.

## Pending (not blockers)

1. **glm1 (M6) confirm:** the runtime validates the container hash
   self-consistently (recompute vs field) and nothing bakes a
   CANONICAL build hash into the generated interpreter — per
   RUNTIME-M6 the entry is `{s,c,env,args,dbg}` and build-time legs
   derive from the emitted CODE region, so per-session containers
   should flow through unchanged. Explicit confirm requested from the
   integrity-path owner.
2. **M1 (main-agent):** the session-hash + per-delivery `bundle_sig`
   changes above; the PackParts ingestion surface.
3. **M7 (main-agent):** extractor container-artifact class once the
   junk bit-layout is pinned at implementation time.
