# RESEARCH-M13 — Loader stub generator and CDN init packaging

Research Log per doc.md "READ FIRST" (research before code). All URLs below
were opened during this session (2026-10-10) unless marked otherwise. Local
benchmarks were executed and their transcripts are quoted below.

## Research table

| Topic | Source URL | Version / date | Key finding | Used for |
|-------|-----------|----------------|-------------|----------|
| Cloudflare default cache behavior | https://developers.cloudflare.com/cache/concepts/default-cache-behavior/ | opened 2026-10-10 | Cloudflare caches **by file extension, not MIME type**. `.lua` is NOT in the default cached-extension list (7Z, AVI, CSV, DOC, GIF, … JS, PDF, ZIP — no LUA). HTML/JSON are not cached by default. A resource is cached when `Cache-Control: public, max-age>0` (or future `Expires`) and method is GET; never cached on `no-store`/`no-cache`/`private`/`max-age=0`. | D-M13-3: init endpoint needs explicit caching; stub endpoint must use `no-store` |
| Workers Cache API | https://developers.cloudflare.com/workers/runtime-apis/cache/ | opened 2026-10-10 | `caches.default` is the programmatic cache inside a Worker; `cache.put()` requires cacheable `Cache-Control` on the stored response; `cache.put` is not compatible with tiered caching (use `fetch` for that). Works regardless of file extension — a Worker-served `/static/init_<build>.lua` can be edge-cached without any Cache Rule. | D-M13-3: serve init via M1's Worker + Cache API instead of R2-custom-domain + Cache Rule |
| R2 public buckets | https://developers.cloudflare.com/r2/buckets/public-buckets/ | opened 2026-10-10 | R2 objects are exposed via a custom domain or an `r2.dev` subdomain. (Page opened for the exposure model; caching details come from the two sources above.) | D-M13-3 context: R2 as blob origin behind the Worker |
| Executor FS API — UNC reference (Potassium docs) | https://docs.potassium.pro/api-reference/FileSystem%20Library/readfile.md (+ writefile, makefolder, isfile, isfolder; index at https://docs.potassium.pro/llms.txt) | opened 2026-10-10 | `readfile(file: string): string` (workspace-relative), `writefile(file, contents)`, `makefolder(path)`, `isfile(path): boolean`, `isfolder(path): boolean`. Paths resolve against the executor's workspace directory. The team guide (GLM_SCRIPTING_RULES §12) already pins these docs as the canonical UNC reference. | D-M13-4/D12: cache folder + file layout, feature-check list |
| Executor FS API — second executor (Solara) | https://getsolara.dev/docs | opened 2026-10-10 | Same UNC surface confirmed on a second executor: readfile/writefile/makefolder/isfile/isfolder/appendfile/listfiles/delfile/delfolder/loadfile. Notably `readfile` **errors if the file does not exist** — reads must be isfile-gated or pcall-wrapped. | D-M13-4: pcall-gated reads; isfile-gated cache check |
| Executor HTTP API (UNC standard) | https://docs.potassium.pro/api-reference/Miscellaneous%20Library/request.md | opened 2026-10-10 | `request({Url, Method, Body?, Headers?, Cookies?})` → table with `Body: string`, `StatusCode: number`, `StatusMessage: string`, `Success: boolean`, `Headers: table`. Aliases `http_request`/`http.request`. | Stub download path: check `Success` + `StatusCode == 200` + `Body` type |
| FNV-1a 32-bit known-answer vectors | https://datatracker.ietf.org/doc/html/draft-eastlake-fnv/ (IETF draft, "The FNV Non-Cryptographic Hash Algorithm"; fetched via reader service — direct curl was blocked by a Cloudflare challenge) | draft revision current as of 2026-10-10 | `teststring[] = { "", "a", "foobar", "Hello!\x01\xFF\xED" }`; FNV-1a 32-bit values `{ 0x811c9dc5, 0xe40c292c, 0xbf9cf968, 0xfd9d3881 }`. Prime is 16777619 (0x01000193), offset basis 2166136261. | Outside-source KATs for the TS and Lua hash implementations (test/hashes.test.ts, bench assertions) |
| Cache-Control directive semantics | https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Cache-Control | opened 2026-10-10 | `immutable` is a standard response directive (clients/agents that don't recognize it ignore it); pairs with long `max-age` for content that never changes. | Init response headers: `public, max-age=31536000, immutable` |
| Cache-busting strategy | Derived from the two Cloudflare sources above + MDN | 2026-10-10 | Content-addressed URLs (new content → new URL) make responses permanently cacheable (`immutable`) with no invalidation problem — the URL itself busts. Cloudflare request collapsing avoids duplicate origin fetches on a cold new build. | D-M13-2: build id = sha256 prefix; `init_<build>.lua` naming |

## Local benchmark (executed, lua5.4, bit32 shimmed with native ops)

Machine: project sandbox (linux). Payload: deterministic pseudo-random bytes.
Script: research scratch (`bench-hash.lua`, retained in the session log; the
shipped module contains only the two chosen algorithms). Correctness gates in
the script passed first (FNV draft vectors incl. `"Hello!\x01\xFF\xED"`,
SHA-256 FIPS vectors `"abc"` and `""`).

```
$ lua5.4 bench-hash.lua 200000
payload: 200000 bytes
fnv1a32      29.797 ms/pass  (148.99 ns/byte)  [reps=20]
djb2         27.235 ms/pass  (136.18 ns/byte)  [reps=20]
sha256      187.407 ms/pass  (937.04 ns/byte)  [reps=3]

$ lua5.4 bench-hash.lua 500000
payload: 500000 bytes
fnv1a32      73.985 ms/pass  (147.97 ns/byte)  [reps=20]
djb2         67.571 ms/pass  (135.14 ns/byte)  [reps=20]
sha256      467.886 ms/pass  (935.77 ns/byte)  [reps=3]
```

Interpretation (feeds D-M13-5): dual 32-bit hashing (FNV-1a + DJB2) costs
~285 ns/byte combined vs ~936 ns/byte for SHA-256 — 3.3x cheaper at runtime
and ~50 lines less embedded code in every per-fetch stub, with no keyed
security either way (an attacker who can hook `readfile` defeats any
unkeyed hash; the trust anchors are server-side per doc.md §3). Numbers are
lua5.4-interpreter evidence, NOT real-executor numbers — real-executor
timing is a §22.1 human test (see VERIFICATION-M13 NOT-RUN list).

## Options compared

- **Init delivery/caching**: (a) R2 custom domain + Cache Rule "cache
  everything" on `/static/*` vs (b) M1 Worker route + `caches.default`
  Cache API vs (c) Workers Static Assets (deploy-time upload). (c) is out:
  init builds are uploaded at runtime through the admin API, static assets
  are deploy-time only. (a) works but adds a config dependency outside the
  code (and `.lua` is not default-cached, so without the rule it silently
  does not cache). (b) works regardless of extension list, needs no extra
  Cloudflare config, and M1 already owns the hostname. → (b), with (a)
  documented as the scale-out alternative (D-M13-3).
- **Cache-validation hash**: (a) FNV-1a 32 + size, (b) dual FNV-1a 32 +
  DJB2 32 + exact size, (c) SHA-256 + size. Evidence above → (b): 64-bit
  combined fingerprint at ~1/3 the runtime cost of (c) and a ~25-line Lua
  embed vs ~5KB; (a) is weaker against same-size tampering for only ~2
  lines saved (D-M13-5).
- **Stub→init handoff**: (a) global variable set by stub, (b) init chunk
  returns an entry function the stub calls with a payload table, (c)
  init reads a file. (b): no global pollution, explicit contract, works
  under loadstring-per-run (D-M13-6).

## Prior art found

- Infinite Yield (public Roblox script) emulates a missing `isfile` via
  `pcall(readfile)` (search-snippet evidence, scribd mirror of its source):
  confirms the fallback pattern used in the stub when `isfile` is absent.
- UNC `UNCCheckEnv.lua` (github.com/unified-naming-convention, surfaced in
  search) exercises the same FS API set across executors — corroborates
  that readfile/writefile/makefolder/isfile/isfolder are the portable core.
  (Indexed via search results; page not deep-read — noted for honesty.)
- The reference key-system flow (doc.md §1, HTTPSpy capture): stub caches
  `init-<build>.lua` in a folder and re-downloads when "missing or too
  small". Per the clean-room rule our design (dual hash + exact size,
  workspace-relative `lp/` folder, underscore naming) is independently
  derived from the doc's own §5.6 contract, not from the vendor's file.

## Unverified items

- **Real-executor availability matrix** (which executor ships which FS
  function): verified on two executors' docs (Potassium, Solara) + team
  guide; a per-executor matrix is a §22.1 real-environment test (human).
- **writefile parent-directory auto-creation**: not documented on either
  executor's docs — the stub defensively `makefolder`s first and pcalls the
  write (behavior verified in harness scenarios, not on real executors).
- **Cloudflare Edge TTL default for 404** (negative caching window): the
  default-cache-behavior page documents Edge TTL by status code; exact 404
  window not re-verified — we sidestep it with explicit `no-store` on all
  non-200 responses from these routes.
- **lua5.4 vs Luau perf parity**: benchmark numbers are lua5.4 (interpreter
  C); executors run Luau. Order-of-magnitude argument only.

## Decisions made and why

See DECISIONS-M13.md (each decision links back to the rows above).
