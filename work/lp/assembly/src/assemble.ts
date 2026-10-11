/**
 * loader/assembly — M3 session 3: the assembled init build generator.
 *
 * Splices the per-build pieces into ONE self-contained init source
 * (doc §8 steps 6-10; D-M13-6: the chunk returns the stub entry fn):
 *
 *   - the M3 crypto bundle + env_executor + handshake client (loader/)
 *   - the M7 §11 checks module (loader/checks/env_checks.lua)
 *   - the M6 emitted VM runtime (CONTAINERLESS mode, RUNTIME-M6 v1.1 —
 *     the container + constKey arrive per session; the runtime itself is
 *     the immutable part of the init build)
 *   - the entry glue (loader/init/entry.lua) + baked per-script config
 *     (script_id, base_url, proof_key, verify_pk, lv — doc §13 layer
 *     table: init is public/static; proof_key is M1's spam filter, not a
 *     trust anchor; verify_pk is public; the constKey NEVER lands here)
 *
 * The output is fed to M13's packageInit() → content-addressed build id
 * → script_versions.init_build.
 */

import { readFileSync } from 'node:fs';
import { join } from 'node:path';

export interface InitConfig {
  /** 32-hex script id (doc §5 keys/scripts). */
  readonly script_id: string;
  /** Fallback API base (the stub payload's api wins when present). */
  readonly base_url: string;
  /** Proof HMAC key, RAW bytes (M1 flow.ts proofKey — spam filter). */
  readonly proof_key: Uint8Array;
  /** Ed25519 VERIFY key (public), raw 32 bytes. */
  readonly verify_pk: Uint8Array;
  /** Loader version string (x-lv). */
  readonly lv: string;
  /** Key cache path override; default "lp/<script_id>.key" (doc §8 step 3
   * — the SDK↔init key channel; the file stores only the key). */
  readonly key_path?: string;
}

export interface AssembleOptions {
  /** M6 emitted runtime source — MUST be containerless mode
   * (emitRuntime({ container: null, ... })); embedded builds would pin
   * the canonical build hash and decoy every per-session container. */
  readonly runtimeSource: string;
  readonly config: InitConfig;
  /** loader/ dir containing crypto/, sdk/, init/, checks/. */
  readonly loaderRoot: string;
}

/** src keys in the assembled chunk (must mirror entry.lua's P.src). */
const MODULE_SOURCES: readonly (readonly [key: string, path: string])[] = [
  ['bit', 'crypto/bit.lua'],
  ['sha2', 'crypto/sha2.lua'],
  ['hmac', 'crypto/hmac.lua'],
  ['encoding', 'crypto/encoding.lua'],
  ['chacha20', 'crypto/chacha20.lua'],
  ['poly1305', 'crypto/poly1305.lua'],
  ['aead', 'crypto/aead.lua'],
  ['hkdf', 'crypto/hkdf.lua'],
  ['field25519', 'crypto/field25519.lua'],
  ['x25519', 'crypto/x25519.lua'],
  ['ed25519', 'crypto/ed25519.lua'],
  ['env_executor', 'sdk/env_executor.lua'],
  ['checks', 'checks/env_checks.lua'],
  ['handshake', 'init/handshake.lua'],
  ['glue', 'init/entry.lua'],
];

/** Lua long-string literal with a bracket level no `]=*]` in src can close. */
function luaLongString(src: string): string {
  let max = 0;
  let cur = 0;
  for (const ch of src) {
    cur = ch === '=' ? cur + 1 : 0;
    if (cur > max) max = cur;
  }
  const eq = '='.repeat(Math.max(1, max + 1));
  return `[${eq}[${src}]${eq}]`;
}

/** \ddd-escaped Lua string literal body for raw bytes. */
function luaByteString(bytes: Uint8Array): string {
  let out = '';
  for (let i = 0; i < bytes.length; i++) out += `\\${String(bytes[i]!).padStart(3, '0')}`;
  return out;
}

function isHex32(s: string): boolean {
  return /^[0-9a-f]{32}$/.test(s);
}

export function assembleInit(options: AssembleOptions): string {
  const { runtimeSource, config, loaderRoot } = options;
  if (!isHex32(config.script_id)) throw new Error('script_id must be 32 hex chars');
  if (!config.base_url || !/^https?:\/\//.test(config.base_url)) throw new Error('base_url must be an http(s) URL');
  if (config.proof_key.length < 8 || config.proof_key.length > 512) throw new Error('proof_key must be 8..512 bytes');
  if (config.verify_pk.length !== 32) throw new Error('verify_pk must be 32 bytes');
  if (!runtimeSource || runtimeSource.length < 1000) throw new Error('runtimeSource looks wrong (empty/short)');
  if (config.lv.length === 0 || config.lv.length > 32) throw new Error('lv must be 1..32 chars');

  const srcEntries: string[] = [];
  for (const [key, path] of MODULE_SOURCES) {
    const body = readFileSync(join(loaderRoot, path), 'utf8');
    srcEntries.push(`${key} = ${luaLongString(body)}`);
  }
  srcEntries.push(`runtime = ${luaLongString(runtimeSource)}`);

  const keyPath = config.key_path ?? `lp/${config.script_id}.key`;
  const cfgTable =
    `{\n` +
    `script_id = ${luaLongString(config.script_id)},\n` +
    `base_url = ${luaLongString(config.base_url)},\n` +
    `proof_key = "${luaByteString(config.proof_key)}",\n` +
    `verify_pk = "${luaByteString(config.verify_pk)}",\n` +
    `lv = ${luaLongString(config.lv)},\n` +
    `key_path = ${luaLongString(keyPath)},\n` +
    `}`;

  return (
    `-- lp init build (assembled by loader/assembly, M3 session 3).\n` +
    `-- Chunk returns the stub entry fn (D-M13-6): entry({api, script_id, build, t, s, r}).\n` +
    `-- Layer contract (doc.md §13): public static content; no script code, no session secrets.\n` +
    `local L = loadstring or load\n` +
    `local SRC = {\n${srcEntries.join(',\n')},\n}\n` +
    `local CONFIG = ${cfgTable}\n` +
    `local GLUE = ${luaLongString(readFileSync(join(loaderRoot, 'init/entry.lua'), 'utf8'))}\n` +
    `-- GLUE's body is: return function(P) ... end — the chunk call yields\n` +
    `-- the factory; the factory call takes the pieces table, returns the entry.\n` +
    `return ((L(GLUE, "=lp-glue"))())({ load = L, src = SRC, config = CONFIG })\n`
  );
}
