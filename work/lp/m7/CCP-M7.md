# CCP-M7 — Watermark slots in the LPVB container (M5 → per-session payload uniqueness)

Filed by: main-agent (module M7, this session). Kind: Tier-3 cross-module
contract change (additive). Owners of the affected surfaces: **M5/glm6**
(container + compiler), **M6/glm1** (runtime decoy/integrity path), M1 (this
agent — delivery wire, ready to consume).

## Problem

Doc §12 requires the server to mix each session's watermark into the
delivered payload "in semantically neutral ways: constant encoding order,
junk-instruction patterns, key-derivation salts, identifier fragments inside
encrypted constants", so that "each payload is unique" and a leaked dump
traces to its session.

Current state (verified this session, RESEARCH-M7 findings #3-#5):

- The **key-derivation salt carrier is live** — `payloadKey = HKDF(sessionKey,
  buildHash ‖ s, "payload-key" ‖ watermark)` (CCP-M6 ruled ACCEPT) — and the
  sealed `payload_ref` carries `watermark(16)`. A leak of the *wire* or the
  *stub memory* is traceable today (extractor shipped).
- The **payload BYTES are identical across sessions**: one prebuilt LPVB blob
  per script version, sealed per session. A dump of the *decrypted bundle*
  (which necessarily includes the entry `c` constKey per RUNTIME-M6 §2) is
  byte-identical for every session → **not traceable**, and runnable by
  anyone who reimplements the M6 entry contract.
- Delivery-time container surgery is impossible by construction: the runtime
  validates the container build hash and per-fetch `s`, and tampering selects
  the decoy constKey path (garbage constants, generic failure) — D-M6-7/D-M7-2.

So the three in-container carriers require BUILD-time support, and only the
delivery path knows the session's watermark. M5 is the only component that
can emit watermark-varied container bytes.

## Proposed change (direction — exact mechanism owned by M5)

Add a **watermarkSlots pack option** to the M5 compiler: given a 128-bit
watermark value (the session's `watermark_id`), the pack step varies the
container in semantically neutral, extractor-recoverable ways:

1. **Const-pool ORDER permutation** — within each function's const pool,
   order the entries by a permutation derived from the watermark (references
   are indices, so reordering is semantics-preserving).
2. **Junk const entries** — dead-slot constants whose VALUES encode
   watermark bits (never referenced; survive container re-serialization but
   not a decompile+DCE pass — the robustness ladder is in RESEARCH-M7).
3. **Identifier fragments in LIVE encrypted constants** — the highest-value
   carrier: watermark-derived fragments embedded in constants the program
   actually uses (e.g. salt strings the code hashes), surviving recompile.

**Integrity interaction (the part that needs M6's co-design):** the build
hash currently covers the container bytes; per-session variation would break
the hash unless (a) the watermark region is excluded from the build hash and
covered instead by a WATERMARK-REGION key/hash derived per session (mirror of
the CCP-M6 `s` pattern), or (b) the build hash is computed over the
pre-watermark canonical form and the runtime verifies both layers. Which of
(a)/(b) — or a third design — is M5+M6's call; M7 only requires that the
extractor can recover the watermark from the container bytes WITHOUT secret
knowledge beyond the build (admin-side tool), and that tamper/wrong-watermark
still degrades to the existing decoy path.

## Delivery model (M1 side, ready to consume)

- The build pipeline (M13 lane) would produce per-session variants at
  `/auth/:id/payload` time. Two feasible wirings, M5's pick:
  - **A) api-side pack**: the api receives per-version container "parts"
    (pre-compiled function blobs + const-pool material) and runs the M5
    packer in-process per session (the packer is TS — same runtime as the
    api). Requires the constKey/build secrets to be deliverable to the api
    (they already ride inside the payload per RUNTIME-M6 §2).
  - **B) pre-generated variant pool**: the build emits N variants per
    version and the api picks variant = H(watermark) mod N — weaker (finite
    variant space) but zero new api code.
- M7's extractor (`api/src/leak.ts`) will gain the container-artifact class
  the moment BYTECODE-M5 vNext pins the slot format; the admin lookup chain
  (watermark → session → key → revoke) is already live and format-agnostic.

## Why now

M7 session 1 shipped everything that does not need this contract. The
remaining §12 goal — "a leaked file from one user cannot serve as a generic
cracked loader" — is only fully true once the payload bytes themselves carry
the watermark. glm4's M8 leak-lookup lane and this extractor are ready to
consume it.

Ruling requested from glm6 (M5 owner) + glm1 (M6 integrity-path co-design).
