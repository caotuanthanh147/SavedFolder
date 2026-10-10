import { generateStub } from "./generator";
import { isBuildId } from "./initpack";

/**
 * Mountable route handlers for the two file endpoints of doc.md §5.3:
 *
 *   GET /loaders/<script_id>.lua   — unique stub per fetch (no-store)
 *   GET /static/init_<build>.lua   — immutable, CDN-cacheable init build
 *
 * These handlers are framework-free (Response only) so M1 can mount them in
 * its router. Dependencies (script resolution, init blob storage, edge
 * cache) are injected; see README integration notes.
 */

export interface ScriptRouting {
  /** Active init build for the script (script_versions.init_build). */
  initBuild: string;
}

export interface LoaderDeps {
  /** M1: resolve script_id -> active version routing; null when unknown. */
  resolveScript(scriptId: string): Promise<ScriptRouting | null>;
  /** M1: fetch the served bytes of an init build (R2/blob store); null when absent. */
  getInitBytes(build: string): Promise<Uint8Array | null>;
  apiBase: string;
  staticBase: string;
  nowSec?: () => number;
  /**
   * Edge cache in front of the init blob store (Workers: caches.default,
   * adapted to this interface; the adapter constructs Request keys).
   * Optional: without it the init is served straight from the blob store.
   */
  edgeCache?: EdgeCache;
}

export interface EdgeCache {
  match(url: string): Promise<Response | undefined>;
  put(url: string, res: Response): Promise<void>;
}

const INIT_HEADERS: Record<string, string> = {
  "content-type": "text/plain; charset=utf-8",
  // Content-addressed builds never change: cache forever at every layer.
  "cache-control": "public, max-age=31536000, immutable",
};

function notFound(): Response {
  // no-store keeps negative responses out of the edge cache.
  return new Response(null, { status: 404, headers: { "cache-control": "no-store" } });
}

function serverError(): Response {
  return new Response(null, { status: 500, headers: { "cache-control": "no-store" } });
}

function badRequest(): Response {
  return new Response(null, { status: 400, headers: { "cache-control": "no-store" } });
}

/** GET /loaders/<script_id>.lua — unique stub per fetch. */
export async function handleGetLoader(deps: LoaderDeps, scriptId: string): Promise<Response> {
  if (!/^[0-9a-f]{32}$/.test(scriptId)) return badRequest();
  const routing = await deps.resolveScript(scriptId);
  if (!routing || !isBuildId(routing.initBuild)) return notFound();
  const initBytes = await deps.getInitBytes(routing.initBuild);
  if (!initBytes) return serverError();
  const stub = generateStub({
    scriptId,
    build: routing.initBuild,
    apiBase: deps.apiBase,
    staticBase: deps.staticBase,
    initBytes,
    nowSec: deps.nowSec ? deps.nowSec() : Date.now() / 1000,
  });
  return new Response(stub.body, { status: 200, headers: stub.headers });
}

/** GET /static/init_<build>.lua — immutable init build, edge-cached when configured. */
export async function handleGetInit(deps: LoaderDeps, build: string, reqUrl: string): Promise<Response> {
  if (!isBuildId(build)) return badRequest();
  const cache = deps.edgeCache;
  if (cache) {
    const hit = await cache.match(reqUrl);
    if (hit) return hit;
  }
  const bytes = await deps.getInitBytes(build);
  if (!bytes) return notFound();
  const res = new Response(bytes as unknown as BodyInit, { status: 200, headers: INIT_HEADERS });
  if (cache) {
    // Cache API requires cacheable headers on the stored response; ours qualify.
    await cache.put(reqUrl, res.clone()).catch(() => undefined);
  }
  return res;
}
