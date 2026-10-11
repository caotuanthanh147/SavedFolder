import { fnv1a32, djb2a32 } from "./hashes";
import { renderStub } from "./template";

/**
 * Unique-per-fetch stub generation (doc.md §5.6, §8 step 5). The generator is
 * called by the /loaders/<script_id>.lua endpoint (see routes.ts). Each stub
 * embeds: the script id, the init build id it targets, the API/CDN bases, the
 * fetch time, a fresh stub id, a fresh per-stub random (used by the init for
 * integrity-linked key derivation), and the expected size + hashes of the
 * init bytes as actually served.
 */

export interface StubParams {
  scriptId: string;
  /** Init build id this stub should load (from script_versions.init_build). */
  build: string;
  /** Public API base URL (the init needs it for /auth calls). */
  apiBase: string;
  /** Public static/CDN base URL (the stub downloads the init from here). */
  staticBase: string;
  /** The actual init bytes for this build (expected size + hashes are derived from them). */
  initBytes: Uint8Array;
  /** On-disk cache folder name (workspace-relative), default "lp". */
  cacheDir?: string;
  nowSec: number;
  /** Injectable randomness for deterministic tests; defaults to CSPRNG. */
  randomBytes?: (n: number) => Uint8Array;
}

export interface StubOutput {
  body: string;
  headers: Record<string, string>;
  stubId: string;
  fetchedAt: number;
}

const HEX = "0123456789abcdef";

function toHex(bytes: Uint8Array): string {
  let out = "";
  for (let i = 0; i < bytes.length; i++) {
    out += HEX[(bytes[i] >> 4) & 0xf] + HEX[bytes[i] & 0xf];
  }
  return out;
}

function defaultRandomBytes(n: number): Uint8Array {
  const b = new Uint8Array(n);
  crypto.getRandomValues(b);
  return b;
}

export function generateStub(p: StubParams): StubOutput {
  const rnd = p.randomBytes ?? defaultRandomBytes;
  const stubId = toHex(rnd(8)); // 8 bytes -> 16 hex chars
  const stubR = toHex(rnd(32)); // 32 bytes -> 64 hex chars, per-stub random
  const body = renderStub({
    api: p.apiBase,
    staticBase: p.staticBase,
    scriptId: p.scriptId,
    build: p.build,
    fetchT: Math.floor(p.nowSec),
    stubId,
    stubR,
    expectLen: p.initBytes.length,
    expectFnv: fnv1a32(p.initBytes),
    expectDjb: djb2a32(p.initBytes),
    cacheDir: p.cacheDir ?? "lp",
  });
  return {
    body,
    headers: {
      "content-type": "text/plain; charset=utf-8",
      // Unique per fetch: must never be cached by any layer.
      "cache-control": "no-store",
    },
    stubId,
    fetchedAt: Math.floor(p.nowSec),
  };
}
