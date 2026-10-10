# RESEARCH-M7 — Anti-tamper, watermarking, leak tools (Module M7)

Research completed BEFORE code, per doc.md READ FIRST. SavedFolder TASKS claim
178d3ed was pushed before this research + code.

**Search-tool honesty note (§22.1):** live `web_search` was unavailable this
session (sandbox z-ai config carries the placeholder token `Z.ai`; the API
returns 401 `missing X-Token` — same condition M11 session 3 recorded). Sources
marked **[repo]** were read from this repository; sources marked **[model
knowledge]** come from training knowledge and are flagged for owner spot-check
before being treated as load-bearing. Every [model knowledge] claim used by a
design decision is conservative (worst-case assumptions about attackers).

## Research log

| # | Topic | Source | Key finding | Used for |
|---|---|---|---|---|
| 1 | Executor injects identity headers into the HTTP call | doc.md §1.2.9 **[repo, observed]** | The reference capture shows the executor ADDS identity headers to the headers table during `request` — the script did not set them, and the spy logs them after the call returns. | §11 hooked-HTTP detection: the SDK snapshots its headers table before/after a call; injected entries the SDK did not set = environment instrumenting our traffic (D-M7-6) |
| 2 | Unique per-fetch stub data used for integrity | doc.md §1.2.5, §5.6 **[repo]** | The stub carries per-fetch values "used by the init script for integrity-linked key derivation" — a fetch-local secret the server learns during the exchange. | CCP-M6 ruling input: per-fetch `s` binds the payload key to one fetch (replay useless cross-fetch) |
| 3 | Watermark already inside M1's key schedule | api/src/auth.ts L10-14, L81-82 **[repo]** | `payloadKey = HKDF(sessionKey, salt=buildHash, info="payload-key" \| watermark(16))`; the sealed `payload_ref` carries `watermark(16)` under `refSealKey`; `sessions.watermark_id` is a hex id column since M2. | Carrier inventory D-M7-1: the salt carrier + sealed-ref carrier are LIVE; extractor can unseal refs server-side today |
| 4 | Container const pools are integrity-anchored | BYTECODE-M5.md §5.9/§6.2, RUNTIME-M6.md §4 **[repo]** | Per-function AEAD const pools under chained keys `K_n = HKDF(K_{n-1}, u32be(n), "const-key")`; the runtime validates container build-hash + per-fetch `s` and selects a DECOY constKey on tamper ("garbage constants, generic 'load failed'"), CRC deliberately unverified. | Delivery-time container surgery (append junk consts at /auth/payload time) is IMPOSSIBLE without breaking the build hash → decoy path. In-container carriers (const order, junk, identifier fragments) are BUILD-side only → CCP-M7 to M5 (D-M7-2) |
| 5 | constKey rides inside the payload | RUNTIME-M6.md §2 **[repo]** | Entry field `c` = constKey is "delivered per session via the encrypted payload (M1 wire), never baked into the runtime." | Leak-threat model: a memory dump after handshake contains the decrypted bundle INCLUDING constKey → a custom M6-style runtime can execute the dump without our loader → in-container watermark carriers are the ONLY trace left in that artifact (D-M7-2) |
| 6 | Deobfuscation state of the art vs VMs | obfuscator/vm/RESEARCH-M6.md §2-3 **[repo]** | Luraph-V15 devirtualizer achieves 99.97% lift via SCCP symbolic execution; runtime-re-indexed handler tables are the one technique still defeating it; unluau decompiles Luau when bytecode is recoverable. | Watermark robustness ladder (D-M7-4): carriers must assume the attacker can devirtualize — carriers embedded in LIVE encrypted constants (used by program semantics) survive DCE; junk-only carriers do not survive a decompile+recompile pipeline |
| 7 | Software watermarking taxonomy | Collberg & Thomborson, "Watermarking, Tamper-proofing, and Obfuscation — Tools and Techniques for Software Protection" (IEEE TSE 2000ish) + "A Taxonomy of Obfuscating Transformations" **[model knowledge]** | Static vs dynamic watermarks; fingerprinting (per-copy unique) vs watermarking (same marker in all copies); stealthiness vs robustness tradeoff; evaluation criteria: rate (bits embeddable), stealth, overhead, resilience against semantics-preserving + subverting transforms. | §12 design vocabulary: what we build is per-copy FINGERPRINTING (doc calls it watermarking); rate needed = 128 bits (session watermark id); resilience target = survive re-serialization, not survive full decompile+recompile (that is the obfuscator's job, §10.4 realistic limits) |
| 8 | Collusion-resistant fingerprint codes | Boneh-Shaw CRYPTO'95 "Collusion-secure fingerprinting for digital data"; Tardos 2003 "Optimal probabilistic fingerprint codes" **[model knowledge]** | n-colluder identification needs code-theoretic constructions (BS: O(n^4) length; Tardos: asymptotically optimal length, noise-tolerant). | Scope ruling D-M7-3: our watermark is a RANDOM 128-bit session id, not a collusion-secure code — any single leak traces exactly; colluders sharing one leaked copy are traceable to THAT copy's owner; colluders cannot mix copies into a new valid payload because each copy decrypts only under its own session key chain (mixing breaks AEAD). Collusion-CODE overhead (Tardos) buys nothing here — the crypto already provides unforgeability. Honest limit: two colluders CAN both use the one copy that decrypts — damage = one traced key revoked, the other stays clean until its own leak. |
| 9 | Executor `request` surface | Synapse X docs / executor ecosystems **[model knowledge]** | `request`/`syn.request`/`http_request` aliases across Synapse X, Script-Ware, Krnl, Fluxus, Wave, Hydrogen, Delta, Arceus X; response table `{Status, StatusCode, Body, Headers, Cookies, Success}`; some executors rewrite headers (casing) and add identity headers (matches §1.2.9). | §11 checks operate on the table the SDK itself passes: alias-probing is NOT tamper (expected executor variance); post-call header-table mutation detection IS a signal (D-M7-6) |
| 10 | `loadstring` / `getfenv` / hooking toolkit | executor ecosystems **[model knowledge]** | `loadstring` compiles source (some executors reject raw bytecode); `getfenv`/`getgenv`/`setfenv` expose the fake global env; `hookfunction`/`replaceclosure` replace functions; `newcclosure` re-wraps a Lua closure to appear native (hides the wrapper from naive native checks); `getconnections` enumerates signal connections (remote-spy basis); `debug.sethook` single-stepping. | §11 client checks design (D-M7-5): naive `tostring(fn)` native checks are defeatable by newcclosure — checks must combine identity-over-time (capture twice, compare), upvalue anomalies, timing, and env consistency; ALL are signals (server-side scoring), never client-side hard bans |
| 11 | Timing-based instrumentation detection | anti-debug literature (e.g., single-step overhead) **[model knowledge]** | Debug hooks inflate per-instruction cost by orders of magnitude; os.clock granularity on Windows ~15ms (use elapsed over a large fixed work loop, not single calls); lag spikes and low-end devices create false positives — need percentile sampling and generous thresholds. | §11 timing check (D-M7-5): median of N samples of a fixed work unit vs a per-machine baseline captured at init; threshold = multiple of baseline, not absolute; FP mitigation documented |
| 12 | §11 false-positive philosophy | doc.md §11 **[repo]** | "raise effort and generate signals, not guarantee safety"; silent failure (no explanatory message); server-side correlation: "repeated tamper events plus HWID churn raises an abuse score." | D-M7-5/D-M7-7: client checks REPORT (tamper event via heartbeat), never act; the server aggregates into an abuse score; auto-actions (revoke/blacklist) stay admin-side with the leak workflow |

## Findings — §11 (anti-tamper) design space

**What checks are worth shipping client-side (all = signals, not verdicts):**

1. **Native/identity checks over time** — capture references to critical globals
   (`loadstring`, `request`, `getfenv`) at init AND at check time; a
   `hookfunction`-style replacement changes the reference between captures.
   Defeatable by re-hooking after each capture, but every evasion layer costs
   attacker effort and risks new anomalies. FP: near zero (same-env re-capture
   is stable).
2. **Upvalue/introspection anomalies** — a `newcclosure` wrapper hides Lua-level
   identity but historically leaves measurable differences (upvalue counts,
   behavior under `debug.getinfo` fields). Executor-dependent → FP-prone if
   treated as verdict → score weight low.
3. **Header-table injection detection** — §1.2.9-observed: executors ADD
   identity headers to our request tables. The SDK compares the table it passed
   vs the table after the call: entries the executor itself documents
   (identity headers configured at HWID provisioning) are EXPECTED; unknown
   additions = a wrapper is rewriting our traffic (remote-spy/HTTP logger
   pattern). FP: low — the check only fires on entries the server did not
   teach the SDK to expect.
4. **Timing sanity** — fixed work unit timed at init (baseline) and at check
   time; ratio above threshold = single-stepping/hooking overhead. Median of
   samples; generous threshold (≥20× baseline per [11]); FP: low-end devices
   inflate baseline itself, so ratio-based logic self-calibrates.
5. **Environment consistency** — expected globals present, executor identity
   consistent with the UA headers the server sees (server already reads
   executor HWID headers per doc §1.2.9 — cross-check server-side).

**Silent failure (doc §11):** on a failed check the client reports a `tamper`
event and loads nothing, with NO explanatory message. The tamper event rides
the heartbeat wire (request body is M1-owned; §5.3 pins heartbeat as optional
JSON envelope — adding an optional `tamper` field is Tier-1, no CCP needed).
Server-side: `tamper` events already exist as an event type (M1 analytics
counts them); M7 adds the client-reported ingestion path + correlation.

**Server-side correlation (doc §11):** abuse score per key = weighted sum of
tamper events, HWID churn (distinct HWID hashes across the key's sessions),
denial events (HWID_MISMATCH, KEY_INVALID lockouts). Score is a SIGNAL for
admins (dashboard badges, leak-workflow context), never an automatic ban —
false-positive cost analysis in D-M7-7.

## Findings — §12 (watermarking) design space

**Carrier inventory (what can carry the per-session watermark):**

| Carrier | Where it lives | Status | Survives memory-dump leak? | Survives re-serialization? |
|---|---|---|---|---|
| HKDF info (payload key schedule) | key material | LIVE since M1 | N/A (keys not in artifact) | N/A |
| Sealed `payload_ref` | stub/init memory | LIVE since M1 | yes (ref bytes in dump) | yes (sealed blob is opaque) |
| Per-fetch `s` in salt (CCP-M6) | key material | ruled ACCEPT this session | N/A (replay-blocking, not tracing) | N/A |
| Container const-pool ORDER | LPVB bytes (per-function pools) | CCP-M7 (M5, build-side) | yes | yes if pools kept intact |
| Junk-instruction patterns | LPVB bytes | CCP-M7 (M5, build-side) | yes | partially (dead slots DCE on recompile) |
| Identifier fragments inside LIVE encrypted constants | LPVB bytes | CCP-M7 (M5, build-side) | yes | BEST (semantically used → survives recompile if constant survives) |

**Why delivery-time container surgery is impossible (finding #4):** the
runtime pins the container build-hash and per-fetch `s`; tampering selects the
decoy constKey path by design. Appending watermark junk to a const pool at
`/auth/payload` time would change the bytes the build hash covers → decoy. So
in-container carriers require M5 to emit watermarkable regions at BUILD time
per session — which only the delivery path knows. CCP-M7 proposes the minimal
contract: M5 gains a `watermarkSlots` pack option (junk const entries +
const-order permutation + identifier-fragment constants derived from a
128-bit watermark value, all covered by a WATERMARK-REGION hash that the
runtime also derives from `s`-style material) — exact mechanism for glm6 to
own; M7's extractor will consume whatever BYTECODE-M5 vNext pins.

**Extractor requirements (doc §12):** "build the watermark extractor as a
first-class tool and test that it survives renaming and reformatting." For
artifact formats this session (ref / session token / watermark id), renaming =
file names (irrelevant); reformatting = the artifact arriving embedded in
arbitrary leaked text (logs, JSON blobs, chat messages). The extractor
therefore: accepts a raw artifact OR greps candidate tokens (base64url/base64
of the right length class) out of messy text; tries each candidate as
sealed-ref / session-token / hex watermark id; reports what matched. Container
carriers join the same CLI when CCP-M7 lands.

**Leak workflow (doc §12):** extract → lookup (watermark → session → key →
identity + hwid/ip hashes) → action (revoke key, blacklist HWID/IP) → audit →
notify admin channel. Notify = audit event + `leak` event row now; the Discord
admin-channel delivery is M8's lane (glm4's TASKS row already lists
`/leak lookup` as M7-dependent — this delivery unblocks it). Auto-revoke
default OFF (false-positive cost: revoking a paying user on a forged dump);
admin confirms in the dashboard Leak-tools view.

## Options compared (feeds DECISIONS-M7)

**Tamper reporting wire**
- A) New public `/tamper` endpoint: violates §5.3's pinned endpoint list → Tier-3 CCP for zero benefit. Rejected.
- B) **Optional `tamper` field on the existing heartbeat request** (heartbeat request body is unpinned, M1-owned): chosen — zero contract churn, heartbeat already carries the session identity, and a dead session heartbeat double-serves as a liveness check for the tamper signal.

**Abuse score storage**
- A) Materialized column on `keys`, updated on every event: write amplification, migrations, and the score is derived data anyway. Rejected.
- B) **Computed on read in `/admin/abuse-scores`** (SQL over events + sessions joins): chosen — no schema change, no drift, trivially tunable weights.

**Leak artifact intake**
- A) Strict JSON API only: fails "survives reformatting" — leaked dumps are messy text. Rejected.
- B) **Tolerant extractor: raw artifact OR free-text scan** (candidate token enumeration + classification), exposed as both an admin endpoint and a CLI: chosen.

**Watermark in-container carriers**
- A) Implement delivery-time surgery anyway: impossible (finding #4, decoy path). Rejected.
- B) Defer entirely to a future session: leaves §12's strongest carriers unowned. Rejected.
- C) **File CCP-M7 to M5 with the watermarkSlots contract direction + ship everything else now.** Chosen.
