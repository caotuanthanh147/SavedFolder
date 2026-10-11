/**
 * M6 standalone obfuscation CLI — produces a SINGLE-FILE (embedded
 * container) protected artifact from any Luau/Lua source.
 *
 *   bun run tools/obfuscate.ts <input.lua> <output.lua> [--seed <hex>] [--dispatch chain|tree|closure] [--wm <hex16>]
 *
 * Pipeline (§10.2, same calls the M1 api uses server-side):
 *   M4 parse → M5 compile → M5 pack (plain or watermarked) → M6 embedded
 *   emit → wrapped as a self-executing chunk:
 *
 *     local entry = (function() <runtime> end)()
 *     pcall(entry, { c = <constKey>, s = <label>, args = {}, nargs = 0 })
 *
 * This is the RUNTIME-M6 §1 "harness + one-artifact" shape: runtime and
 * container ship together (build hash pinned inside the runtime). The
 * platform's DEPLOYMENT shape stays containerless (doc §8 step 10: the
 * runtime lives in the M13 init, the container arrives per-session over
 * the M1 wire) — this CLI exists for direct/one-off distribution.
 *
 * --seed: deterministic replay — vmSeed/opcodeSeed/constKey are all
 * derived from it (sha256 domain-separated); per-function pool nonces
 * are derived from seed + source-hash, so the SAME seed + SAME source
 * rebuild the artifact byte-identically (M5 D-M5-24 poolNonces option),
 * while a seed reused across DIFFERENT sources still yields distinct
 * nonces (no AEAD nonce reuse under the shared key). Without --seed,
 * every value is fresh random (D-M5-17 default).
 * --wm: pack a WATERMARKED container (CCP-M7 v1, per-version default key)
 * — 16 hex bytes of owner watermark, extractor = extractWatermark.
 *
 * The artifact is comment-free and Lua 5.1-syntax-safe (Roblox Luau
 * executors load it directly; luac5.4 -p gates it in tests).
 */

import { readFileSync, writeFileSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { parse } from '../../src/parser';
import { compileProgram } from '../../compiler/src/compile';
import { pack } from '../../compiler/src/container';
import { generatePackMaterial, packWatermarked } from '../../compiler/src/watermark';
import { emitRuntime, type DispatchKind } from '../src/emit';

function sha256(input: string): Uint8Array {
  return new Uint8Array(createHash('sha256').update(input, 'utf8').digest());
}

function hex(bytes: Uint8Array): string {
  return Buffer.from(bytes).toString('hex');
}

function luaByteString(bytes: Uint8Array): string {
  let out = '';
  for (let i = 0; i < bytes.length; i++) out += `\\${String(bytes[i]!).padStart(3, '0')}`;
  return out;
}

function randomBytes(n: number): Uint8Array {
  const out = new Uint8Array(n);
  crypto.getRandomValues(out);
  return out;
}

const args = process.argv.slice(2);
if (args.length < 2) {
  console.error('usage: bun run tools/obfuscate.ts <input.lua> <output.lua> [--seed <hex>] [--dispatch chain|tree|closure] [--wm <hex16>]');
  process.exit(2);
}
const [input, output] = args;
const seedIdx = args.indexOf('--seed');
const dispatchIdx = args.indexOf('--dispatch');
const wmIdx = args.indexOf('--wm');

const seedStr = seedIdx >= 0 ? (args[seedIdx + 1] ?? '') : '';
const dispatch = (dispatchIdx >= 0 ? (args[dispatchIdx + 1] ?? undefined) : undefined) as DispatchKind | undefined;
const wmHex = wmIdx >= 0 ? (args[wmIdx + 1] ?? '') : '';

if (dispatch && !['chain', 'tree', 'closure'].includes(dispatch)) {
  console.error(`--dispatch must be chain|tree|closure, got ${dispatch}`);
  process.exit(2);
}
if (wmHex && !/^[0-9a-fA-F]{32}$/.test(wmHex)) {
  console.error('--wm must be 16 bytes as 32 hex chars');
  process.exit(2);
}

// seeds: deterministic from --seed (domain-separated), else random
const vmSeed = seedStr ? sha256(`lp1-obf|vm|${seedStr}`) : randomBytes(32);
const opcodeSeed = seedStr ? sha256(`lp1-obf|opcode|${seedStr}`) : randomBytes(32);
const constKey = seedStr ? sha256(`lp1-obf|const|${seedStr}`) : randomBytes(32);
const sLabel = 'lp1-standalone';

// M4 parse — the byte-string contract: latin1, one code unit per byte
const source = readFileSync(input!).toString('latin1');
const chunk = parse(source);

// M5 compile + pack
const { protos } = compileProgram(chunk);
// seed-derived reproducible pool nonces (D-M5-24 option): only under
// --seed, and mixed with the source hash — byte-identical replay of the
// same (seed, source) pair, never a nonce reuse across sources.
const srcHash = createHash('sha256').update(source, 'latin1').digest('hex');
const poolNonces = seedStr
  ? protos.map(
      (_, i) =>
        sha256(`lp1-obf|nonce|${seedStr}|${srcHash}|${i}`).slice(0, 12),
    )
  : undefined;
let container: Uint8Array;
if (wmHex) {
  const wm = new Uint8Array(Buffer.from(wmHex, 'hex'));
  ({ container } = packWatermarked(generatePackMaterial(protos), wm));
} else {
  ({ container } = pack(protos, { constKey, opcodeSeed, poolNonces }));
}

// M6 embedded emit (runtime + container in one artifact)
const emit = emitRuntime({ container, opcodeSeed, vmSeed, dispatch });

const artifact = `local entry = (function()
${emit.lua}
end)()
local ok, err = pcall(entry, {
  c = "${luaByteString(constKey)}",
  s = "${sLabel}",
  args = {}, nargs = 0,
})
if not ok then error(err, 0) end
`;

writeFileSync(output!, artifact, 'utf8');

console.log(`input:        ${input} (${Buffer.byteLength(source, 'latin1')} bytes)`);
console.log(`container:    ${container.length} bytes (LPVB, ${wmHex ? 'watermarked' : 'plain'} pack)`);
console.log(`artifact:     ${output} (${Buffer.byteLength(artifact, 'utf8')} bytes)`);
console.log(`dispatch:     ${emit.dispatch}${emit.runtimeBuilt ? ' + runtime-built handler table' : ''}`);
console.log(`vmChecksums:  fnv=0x${emit.vmChecksums.fnv.toString(16)} djb2=0x${emit.vmChecksums.djb2.toString(16)}`);
console.log(`vmSeed:       ${hex(vmSeed)}`);
console.log(`opcodeSeed:   ${hex(opcodeSeed)}`);
console.log(`constKey:     ${hex(constKey)}`);
