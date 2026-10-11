import { fnv1a32, djb2a32 } from "./hashes";

/**
 * Init build packaging: turns an init Lua source into a content-addressed,
 * CDN-cacheable build. The build id is derived from the content (sha256
 * prefix), so a new init version yields a new URL and the old URL stays
 * immutable — the cache-busting strategy (see RESEARCH-M13).
 */

export interface InitBuild {
  /** Content-addressed build id: "b" + 12 lowercase hex of sha256(source). */
  build: string;
  /** File name served at /static/: "init_<build>.lua". */
  fileName: string;
  /** Exact byte length of the source (embedded in stubs for validation). */
  size: number;
  /** Full sha256 hex (identity for manifests/debugging; not embedded in stubs). */
  sha256Hex: string;
  /** Expected FNV-1a 32 of the served bytes (embedded in stubs). */
  fnv: number;
  /** Expected DJB2 of the served bytes (embedded in stubs). */
  djb: number;
  /** Packaging time, unix seconds. */
  createdAt: number;
}

const HEX = "0123456789abcdef";

function toHex(bytes: Uint8Array): string {
  let out = "";
  for (let i = 0; i < bytes.length; i++) {
    out += HEX[(bytes[i] >> 4) & 0xf] + HEX[bytes[i] & 0xf];
  }
  return out;
}

export async function sha256Hex(data: Uint8Array): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", data as unknown as ArrayBuffer);
  return toHex(new Uint8Array(digest));
}

/** Build id format this module produces and routes accept. */
export function isBuildId(build: string): boolean {
  return /^b[0-9a-f]{12}$/.test(build);
}

export async function packageInit(source: Uint8Array, nowSec: number): Promise<InitBuild> {
  const sha = await sha256Hex(source);
  return {
    build: "b" + sha.slice(0, 12),
    fileName: "init_b" + sha.slice(0, 12) + ".lua",
    size: source.length,
    sha256Hex: sha,
    fnv: fnv1a32(source),
    djb: djb2a32(source),
    createdAt: Math.floor(nowSec),
  };
}
