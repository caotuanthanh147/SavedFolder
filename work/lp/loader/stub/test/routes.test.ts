import { describe, expect, test } from "bun:test";
import { handleGetLoader, handleGetInit, EdgeCache, LoaderDeps } from "../src/routes";
import { packageInit } from "../src/initpack";

const enc = (s: string) => new TextEncoder().encode(s);

const INIT_SRC = "-- init fixture\nreturn function() end\n";

class MapCache implements EdgeCache {
  store = new Map<string, Response>();
  puts = 0;
  async match(url: string): Promise<Response | undefined> {
    return this.store.get(url);
  }
  async put(url: string, res: Response): Promise<void> {
    this.puts++;
    this.store.set(url, res.clone());
  }
}

const SCRIPT_ID = "0123456789abcdef0123456789abcdef";

async function makeDeps(overrides: Partial<LoaderDeps> = {}): Promise<LoaderDeps & { initBytes: Uint8Array; initBuild: string }> {
  const initBytes = enc(INIT_SRC);
  const packaged = await packageInit(initBytes, 1760000000);
  const deps: LoaderDeps & { initBytes: Uint8Array; initBuild: string } = {
    resolveScript: async (id) => (id === SCRIPT_ID ? { initBuild: packaged.build } : null),
    getInitBytes: async (build) => (build === packaged.build ? initBytes : null),
    apiBase: "https://auth.example.net",
    staticBase: "https://cdn.example.net",
    nowSec: () => 1760001234,
    initBytes,
    initBuild: packaged.build,
    ...overrides,
  };
  return deps;
}

describe("GET /loaders/:script_id.lua", () => {
  test("serves a unique stub with no-store headers", async () => {
    const deps = await makeDeps();
    const r1 = await handleGetLoader(deps, SCRIPT_ID);
    const r2 = await handleGetLoader(deps, SCRIPT_ID);
    expect(r1.status).toBe(200);
    expect(r1.headers.get("content-type")).toBe("text/plain; charset=utf-8");
    expect(r1.headers.get("cache-control")).toBe("no-store");
    const b1 = await r1.text();
    const b2 = await r2.text();
    expect(b1).not.toBe(b2); // unique per fetch
    expect(b1).toContain(`local SCRIPT_ID = "${SCRIPT_ID}"`);
    expect(b1).toContain(`local BUILD = "${deps.initBuild}"`);
  });

  test("unknown script -> 404 no-store; malformed id -> 400", async () => {
    const deps = await makeDeps();
    expect((await handleGetLoader(deps, "ffffffffffffffffffffffffffffffff")).status).toBe(404);
    expect((await handleGetLoader(deps, "../etc/passwd")).status).toBe(400);
    expect((await handleGetLoader(deps, "XYZ")).status).toBe(400);
    const nf = await handleGetLoader(deps, "ffffffffffffffffffffffffffffffff");
    expect(nf.headers.get("cache-control")).toBe("no-store");
  });

  test("script known but init blob missing -> 500 no-store", async () => {
    const deps = await makeDeps({ getInitBytes: async () => null });
    expect((await handleGetLoader(deps, SCRIPT_ID)).status).toBe(500);
  });

  test("routing with a non-build-id initBuild -> 404 (bad data guard)", async () => {
    const deps = await makeDeps({ resolveScript: async () => ({ initBuild: "not-a-build" }) });
    expect((await handleGetLoader(deps, SCRIPT_ID)).status).toBe(404);
  });
});

describe("GET /static/init_<build>.lua", () => {
  test("serves exact bytes with immutable caching headers", async () => {
    const deps = await makeDeps();
    const url = deps.staticBase + "/static/init_" + deps.initBuild + ".lua";
    const res = await handleGetInit(deps, deps.initBuild, url);
    expect(res.status).toBe(200);
    expect(res.headers.get("cache-control")).toBe("public, max-age=31536000, immutable");
    expect(res.headers.get("content-type")).toBe("text/plain; charset=utf-8");
    const body = new Uint8Array(await res.arrayBuffer());
    expect(body.length).toBe(deps.initBytes.length);
    for (let i = 0; i < body.length; i++) expect(body[i]).toBe(deps.initBytes[i]);
  });

  test("edge cache: first request stores, second is a hit without blob read", async () => {
    const base = await makeDeps();
    const build = base.initBuild;
    const cache = new MapCache();
    let blobReads = 0;
    const deps = await makeDeps({
      edgeCache: cache,
      getInitBytes: async (b) => {
        if (b !== build) return null;
        blobReads++;
        return enc(INIT_SRC);
      },
    });
    const url = deps.staticBase + "/static/init_" + build + ".lua";
    const r1 = await handleGetInit(deps, build, url);
    expect(cache.puts).toBe(1);
    expect(blobReads).toBe(1);
    const r2 = await handleGetInit(deps, build, url);
    expect(blobReads).toBe(1); // served from cache, no second blob read
    expect(await r1.text()).toBe(await r2.text());
    expect(r2.headers.get("cache-control")).toBe("public, max-age=31536000, immutable");
  });

  test("unknown build -> 404 no-store; malformed build -> 400", async () => {
    const deps = await makeDeps();
    expect((await handleGetInit(deps, "b000000000000", "https://x/init_b000000000000.lua")).status).toBe(404);
    expect((await handleGetInit(deps, "../../etc/passwd", "https://x/whatever")).status).toBe(400);
  });
});
