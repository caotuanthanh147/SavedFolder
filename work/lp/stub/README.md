# loader/stub — M13: Loader stub generator and CDN init packaging

doc.md module M13 (§5.6, §8 steps 5–6). Owner: glm4. Research → decisions →
verification: RESEARCH-M13.md, DECISIONS-M13.md, VERIFICATION-M13.md.

## What this builds

1. **Init build packaging** (`src/initpack.ts`) — turns an init Lua source
   into a content-addressed build: `build = "b" + sha256[0:12]`, served at
   `/static/init_<build>.lua` with immutable caching. New init content ⇒
   new URL ⇒ no cache invalidation ever needed.
2. **Unique-per-fetch stub generator** (`src/generator.ts` + template) —
   every `/loaders/<script_id>.lua` response embeds fresh values: fetch
   time, stub id (8B), per-stub random (32B, feeds the init's
   integrity-linked key derivation per §5.6), plus the expected exact size
   and dual 32-bit hashes (FNV-1a + DJB2) of the init bytes as served.
   Served with `cache-control: no-store`.
3. **The stub's Lua behavior** (`src/template.ts`) — §5.6 contract:
   look for the cached init (`lp/init_<build>.lua`, workspace-relative);
   validate (exact length + FNV + DJB2); on miss download
   `<static>/static/init_<build>.lua`, validate, best-effort cache write,
   then run. Passes `{api, script_id, build, t, s, r}` to the init's
   returned entry function. All failures are generic; nothing partial
   loads. Executor APIs are feature-checked (request + loadstring
   required; FS functions optional; bit32 optional — DJB2+size still
   validate without it).
4. **Mountable route handlers** (`src/routes.ts`) — `handleGetLoader` /
   `handleGetInit` returning plain `Response`s with the header contract,
   with an injectable edge cache (Workers `caches.default` adapter).

## Run the tests

```sh
cd loader/stub
bun install
bun test          # 42 tests incl. the lua5.4 executor-env harness + luac gate
bun run typecheck # tsc --noEmit
```

Lua toolchain: any Lua 5.4 (`lua5.4`/`luac5.4` on PATH, or
`$HOME/.lua54/bin/`, or `LUA54`/`LUAC54` env overrides).

## Integration notes

**M1 (api/)** — mount two routes:

```ts
import { handleGetLoader, handleGetInit, LoaderDeps, EdgeCache } from "../loader/stub/src/routes";

const loaderDeps: LoaderDeps = {
  resolveScript: async (id) => {
    // SELECT active version's init_build for script id (script_versions.init_build)
  },
  getInitBytes: async (build) => {
    // blob store read for the init build (e.g. env.INIT_BUCKET.get(`init/${build}.lua`))
  },
  apiBase: env.PUBLIC_API_BASE,      // e.g. https://auth.example.net
  staticBase: env.PUBLIC_STATIC_BASE // same origin or a second hostname
};
// router entries:
// GET /loaders/:script_id.lua  -> handleGetLoader(loaderDeps, params.script_id)
// GET /static/init_:build.lua  -> handleGetInit(loaderDeps, params.build, req.url)
```

Edge cache adapter for Workers (optional; omit to serve straight from the
blob store):

```ts
const edgeCache: EdgeCache = {
  match: (url) => caches.default.match(new Request(url)),
  put: (url, res) => caches.default.put(new Request(url), res),
};
```

Notes: every stub fetch performs one blob read for the init bytes (or memoize
`build → {bytes}` per isolate — the per-fetch uniqueness comes from CSPRNG
values, not from re-reading). 4xx/5xx from these handlers already carry
`no-store`, so nothing poisons the edge cache. Init upload path (admin
scripts/versions) should call `packageInit(bytes, now)` and store
`init_build = build` + the bytes.

**M3 (loader/init/, glm1)** — the init script contract (D-M13-6, msg'd):
the init chunk must `return` an entry function; the stub calls

```lua
entry({
  api = "<api base>",      -- for /auth/<script_id>/init|payload|heartbeat
  script_id = "<hex32>",
  build = "b<12hex>",      -- goes into the auth init request body
  t = <fetch unix sec>,    -- per-fetch data block (§5.6)
  s = "<stub id, 16 hex>",
  r = "<per-stub random, 64 hex>",  -- integrity-linked key derivation input
})
```

The init never needs to know the cache folder; it is loaded, not sourced.

## File tree

```
loader/stub/
  src/        hashes.ts initpack.ts template.ts generator.ts routes.ts
  test/       hashes.test.ts initpack.test.ts generator.test.ts
              routes.test.ts lua-harness.test.ts
  lua/        harness.lua   (executor-env simulator, 10 scenarios)
  RESEARCH-M13.md  DECISIONS-M13.md  VERIFICATION-M13.md  README.md
```
