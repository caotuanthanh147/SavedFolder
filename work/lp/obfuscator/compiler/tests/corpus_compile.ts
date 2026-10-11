/**
 * M5 corpus end-to-end runner: parse (M4) -> compile (M5) -> pack canonical
 * -> packWatermarked -> unpack -> structural differential + extraction.
 *
 * Scope honesty (§22.1): corpus files are real Roblox/executor scripts —
 * they cannot EXECUTE outside a Roblox world, so this runner proves the
 * pipeline at the container level, which is what M5 owns:
 *
 *  1. every parseable corpus file COMPILES (real-world Luau subset through
 *     the compiler — coverage beyond the hand fixtures);
 *  2. canonical pack/unpack: FULL instruction-stream + consts parity (the
 *     existing parity gate, now at corpus scale);
 *  3. watermarked pack/unpack: every K-reference operand in the loaded
 *     watermarked stream equals perm(canonical operand) with the loaded
 *     consts at perm(k) equal to the canonical consts at k — i.e. every
 *     constant reference resolves to the SAME VALUE as the canonical
 *     container (semantic preservation at the pool-reference level);
 *  4. extractWatermark recovers the exact watermark + carrier-1 consistency
 *     on every corpus container.
 *
 * Usage: bun run compiler/tests/corpus_compile.ts <corpus-root>
 */
import { readdirSync, readFileSync, statSync } from 'node:fs';
import { join } from 'node:path';
import { parse } from '../../src/parser';
import { compileProgram, type InsnOut, type Const, type Proto } from '../src/compile';
import { unpack, randomBytes } from '../src/container';
import {
  generatePackMaterial, packWatermarked, extractWatermark, carrierLayout,
  referencedIndices,
} from '../src/watermark';
import { Op } from '../src/opcode';

function* walk(dir: string): Generator<string> {
  for (const entry of readdirSync(dir)) {
    const p = join(dir, entry);
    if (statSync(p).isDirectory()) yield* walk(p);
    else if (entry.endsWith('.lua')) yield p;
  }
}

const K_C = new Set<number>([Op.ADDK, Op.SUBK, Op.MULK, Op.DIVK, Op.MODK, Op.POWK, Op.IDIVK]);
const K_D = new Set<number>([Op.LOADK, Op.GETGLOBAL, Op.SETGLOBAL]);
const K_AUX = new Set<number>([Op.LOADKX, Op.GETTABLEKS, Op.SETTABLEKS, Op.SELFKS]);
const K_AUX_NOT = new Set<number>([Op.JUMPIFEQKN, Op.JUMPIFEQKS]);

function constEquals(a: Const, b: Const): boolean {
  if (a.kind !== b.kind) return false;
  if (a.kind === 'bool' && b.kind === 'bool') return a.b === b.b;
  if (a.kind === 'num' && b.kind === 'num') return a.hi === b.hi && a.lo === b.lo;
  if (a.kind === 'str' && b.kind === 'str') return a.s === b.s;
  return false;
}

function insnEquals(a: InsnOut, b: InsnOut): boolean {
  return a.op === b.op && a.a === b.a && a.b === b.b && a.c === b.c && a.d === b.d && a.aux === b.aux;
}

/** Loaded watermarked operands must equal perm(canonical operand) — the
 *  forward map — for every K-reference field (the packer rewrote old ->
 *  perm[old]; comparing against perm directly proves the reindexing is
 *  exactly the pool permutation that placed the values). */
function inverseCheck(
  canonicalCode: readonly InsnOut[],
  loadedCode: readonly InsnOut[],
  perm: number[],
): boolean {
  if (canonicalCode.length !== loadedCode.length) return false;
  for (let i = 0; i < canonicalCode.length; i++) {
    const c = canonicalCode[i]!;
    const w = loadedCode[i]!;
    if (c.op !== w.op || c.a !== w.a || c.b !== w.b) return false;
    if (K_C.has(c.op)) {
      if (w.c !== perm[c.c]!) return false;
      if (c.d !== w.d || c.aux !== w.aux) return false;
    } else if (K_D.has(c.op)) {
      if (w.d !== perm[c.d]!) return false;
      if (c.c !== w.c || c.aux !== w.aux) return false;
    } else if (K_AUX.has(c.op)) {
      if (w.aux !== perm[c.aux]!) return false;
      if (c.c !== w.c || c.d !== w.d) return false;
    } else if (K_AUX_NOT.has(c.op)) {
      if ((w.aux & 0x7fffffff) !== perm[c.aux & 0x7fffffff]!) return false;
      if ((w.aux & 0x80000000) !== (c.aux & 0x80000000)) return false;
      if (c.c !== w.c || c.d !== w.d) return false;
    } else {
      if (c.c !== w.c || c.d !== w.d || c.aux !== w.aux) return false;
    }
  }
  return true;
}

const root = process.argv[2];
if (!root) {
  console.error('usage: bun run corpus_compile.ts <corpus-root>');
  process.exit(2);
}

let total = 0;
let parseRejects = 0;
let compiled = 0;
let compileRejects = 0;
const failures: string[] = [];
let fnCount = 0;
let insnCount = 0;
let constCount = 0;
let watermarkedOk = 0;
let extractionOk = 0;

for (const file of walk(root)) {
  if (process.env.CORPUS_PROGRESS) console.error('FILE', file);
  total++;
  const source = readFileSync(file).toString('latin1');
  let ast;
  try {
    ast = parse(source);
  } catch {
    parseRejects++;
    continue;
  }
  let protos: readonly Proto[];
  try {
    protos = compileProgram(ast).protos;
  } catch (e) {
    compileRejects++;
    failures.push(`COMPILE ${file}: ${String(e)}`);
    continue;
  }
  compiled++;
  fnCount += protos.length;
  for (const p of protos) {
    insnCount += p.code.length;
    constCount += p.consts.length;
  }

  try {
    // Canonical pack/unpack parity at corpus scale.
    const { parts, canonicalContainer } = generatePackMaterial(protos);
    const canon = unpack(canonicalContainer, { constKey: parts.constKey, opcodeSeed: parts.opcodeSeed });
    for (let f = 0; f < protos.length; f++) {
      if (canon.protos[f]!.insns.length !== protos[f]!.code.length
        || !canon.protos[f]!.insns.every((insn, i) => insnEquals(insn as unknown as InsnOut, protos[f]!.code[i]!))
        || !canon.protos[f]!.consts.every((c, i) => constEquals(c, protos[f]!.consts[i]!))) {
        throw new Error(`canonical parity failed in function ${f}`);
      }
    }

    // Watermarked pack: K-reference consistency + junk tail + extraction.
    const watermark = randomBytes(16);
    const { container } = packWatermarked(parts, watermark);
    const wm = unpack(container, { constKey: parts.constKey, opcodeSeed: parts.opcodeSeed });
    for (let f = 0; f < protos.length; f++) {
      const p = protos[f]!;
      const nLive = p.consts.length;
      const { perm, junk } = carrierLayout(watermark, parts.buildSalt, f, nLive);
      const loaded = wm.protos[f]!;
      if (loaded.consts.length !== nLive + junk) {
        throw new Error(`function ${f}: pool ${loaded.consts.length} != ${nLive}+${junk}`);
      }
      // Every live const VALUE is present at perm(old): consts[perm[old]] == old.
      for (let old = 0; old < nLive; old++) {
        if (!constEquals(loaded.consts[perm[old]!]!, p.consts[old]!)) {
          throw new Error(`function ${f}: live const ${old} not at perm position ${perm[old]}`);
        }
      }
      // Junk = exactly the unreferenced tail.
      const refs = referencedIndices(loaded.insns as unknown as readonly InsnOut[]);
      if (refs.size !== nLive) {
        throw new Error(`function ${f}: referenced ${refs.size} != live ${nLive}`);
      }
      // Instruction-level inverse: operands are perm(old) consistently.
      if (!inverseCheck(p.code, loaded.insns as unknown as readonly InsnOut[], perm)) {
        throw new Error(`function ${f}: K operands do not reindex through the permutation`);
      }
    }
    const got = extractWatermark(container, parts);
    if (!got || !got.carrier1Ok) throw new Error('extraction or carrier-1 failed');
    if (Buffer.from(got.watermark).toString('hex') !== Buffer.from(watermark).toString('hex')) {
      throw new Error('watermark mismatch');
    }
    watermarkedOk++;
    extractionOk++;
  } catch (e) {
    failures.push(`PIPELINE ${file}: ${String(e)}`);
  }
}

console.log(`files: ${total}  parse-rejects: ${parseRejects}  compiled: ${compiled}  compile-rejects: ${compileRejects}`);
console.log(`functions: ${fnCount}  instructions: ${insnCount}  pool entries: ${constCount}`);
console.log(`watermarked+inverse+extraction OK: ${watermarkedOk}/${compiled}`);
if (failures.length) {
  console.log(`FAILURES (${failures.length}):`);
  for (const f of failures.slice(0, 20)) console.log('  ' + f);
  process.exit(1);
}
console.log('ALL GREEN');
