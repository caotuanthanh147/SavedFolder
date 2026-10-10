/**
 * M6 public API — VM runtime generator (doc §10.2 items 5-9).
 *
 * generateRuntime: LPVB container (M5 pack output) + seeds → a Lua 5.1-
 * syntax-safe runtime chunk that returns the entry function
 * (RUNTIME-M6.md contract). The same call with a placeholder container
 * yields the vmChecksums the pipeline needs BEFORE packing (two-pass flow,
 * see emit.ts header).
 *
 * deriveConstKey: doc §10.2 item 9 — the VM runtime's checksums feed the
 * constKey derivation, so tampering with the emitted runtime (at build
 * time) silently corrupts every constant pool instead of tripping a check.
 */

import { hkdfSha256Sync } from '../../compiler/src/container';

export { emitRuntime, fnv1a32ts, djb2ts } from './emit';
export type { EmitOptions, EmitResult } from './emit';
export type { DispatchKind } from './dispatch';
export { ALL_DISPATCH } from './dispatch';

/** HKDF info label for the constKey pre-derivation (distinct from the
 * pinned "const-key" chain label of BYTECODE-M5 §6.2 — this one derives
 * the pack-time constKey input itself). */
export const VM_CONST_KEY_INFO = 'vm-const-key';

export interface VmManifest {
  /** hex SHA-256 of the emitted Lua source (whole file). */
  readonly vm_hash: string;
  readonly vm_seed: string;
  readonly dispatch: string;
  readonly runtime_built: boolean;
  readonly code_checksums: { readonly fnv: number; readonly djb2: number };
  readonly container_length: number;
}

/**
 * constKey = HKDF-SHA256(masterKey, salt = u32be(fnv) || u32be(djb2),
 * info = "vm-const-key", 32).
 *
 * The runtime's own bytes are the salt: any edit to the emitted runtime
 * changes the checksums and therefore the constKey — every pool then
 * decrypts to garbage (AEAD tag failure at first touch, silent generic
 * error — corrupted decryption, not a detectable branch).
 */
export function deriveConstKey(
  masterKey: Uint8Array,
  checksums: { readonly fnv: number; readonly djb2: number },
): Uint8Array {
  const salt = new Uint8Array(8);
  const dv = new DataView(salt.buffer);
  dv.setUint32(0, checksums.fnv >>> 0, false);
  dv.setUint32(4, checksums.djb2 >>> 0, false);
  return hkdfSha256Sync(masterKey, salt, new TextEncoder().encode(VM_CONST_KEY_INFO), 32);
}

export const M6_VERSION = '1.0.0';
