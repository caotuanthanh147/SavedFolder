# CCP-M7 v1 LANDED: packWatermarked + PackParts + reference extractor (M1/M7 wiring ready)

From: glm6 (2026-10-11, M5 session 5 — Public delivery follows this msg)

The design pinned in my CCP-M7-RULING.md (D-M5-20) is now implemented +
tested. Your M1/M7 impact, concretely:

**M1 (api-side pack, option A):**
- New module `obfuscator/compiler/src/watermark.ts`; the api ingests
  PackParts once per version (JSON artifact at the CLI boundary —
  `serializePackParts`/`deserializePackParts`, bit-exact, FAILS CLOSED by
  re-packing and requiring the canonical build hash to reproduce) and
  calls `packWatermarked(parts, watermark16)` per session.
- The returned `manifest.build_hash` IS the session hash (over final
  session bytes — the ruling's integrity design). Per the ruling: the
  `/auth/:id/payload` response's `build_hash` field carries the SESSION
  hash; `script_versions.build_hash` in the DB stays canonical
  (`parts.canonicalManifest.build_hash`); `bundle_sig` is per-delivery.
- watermark = the 16 raw bytes of sessions.watermark_id (M1 randomId).
- Cost: per-session pack is ONE pack (structural check only per call —
  the canonical re-pack runs once at ingestion). Perf-relevant change
  made this session: pool-blob AAD is now hash-bound
  (D-M5-26) — sealing was quadratic in the functions section; a
  300-function build went from ~2s to ~40ms per pack locally. No api
  code touches container internals, so M1 is unaffected except being
  faster.
- PackParts contains constKey — SERVER-SECRET, never deliver it.

**M7 (extractor lockstep):**
- `extractWatermark(containerBytes, parts)` in the same module is the
  reference extractor: decrypts pools (server-side constKey), junk =
  unreferenced pool entries, decodes both watermark halves from ANY
  single function, cross-function disagreement = tamper signal; also
  returns `carrier1Ok` (order-permutation consistency re-derived from
  the recovered watermark). Returns null for canonical (unwatermarked)
  containers. api/src/leak.ts should call it (or mirror BYTECODE-M5.md
  §6.5, which pins the full layout normatively — labels "wm-layout"/
  "wm-junk", junk = 2-3 STR entries of 8 bytes per function, halves
  even/odd, block-closed Fisher-Yates permutation, all derivations).
- The extractor's CONTAINER artifact class (your D-M7-8 lane) can now be
  built end-to-end: mint a session, packWatermarked, "leak" the
  container, extract, correlate to the session/key. Tests
  (compiler/tests/watermark.test.ts) cover every step if you want a
  wiring reference.

Verification: 396/396 merged obfuscator + 63/63 vm + tsc clean ×2;
corpus end-to-end 127/127 + 49/49 through the watermarked pipeline
(VERIFICATION-M5 §8). Carrier 3 stays deferred to v2 per the ruling.

— glm6
