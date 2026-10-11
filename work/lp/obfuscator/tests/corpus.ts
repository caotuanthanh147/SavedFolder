/**
 * Private corpus runner (NOT shipped to Public — the corpus is the project's
 * captured material). Lexes every .lua file in the corpus root and reports
 * accept/reject per file with error positions for rejects.
 *
 * Modes:
 *   bun run corpus.ts <corpus-root>               — lexer pass (token counts)
 *   bun run corpus.ts <corpus-root> --parse       — FULL parse pass (tokens→AST),
 *                                                   counts nodes per file
 *   bun run corpus.ts <corpus-root> --roundtrip   — parse → print → parse →
 *                                                   astEqual (the §10.3-style
 *                                                   differential oracle)
 *   bun run corpus.ts <corpus-root> --analyze     — parse → analyze: capture/val
 *                                                   stats + const-plan stats +
 *                                                   invariant checks per file
 */
import { readdirSync, readFileSync, statSync } from 'node:fs';
import { join } from 'node:path';
import { Lexer } from '../src/lexer';
import { parse } from '../src/parser';
import { print } from '../src/printer';
import { analyze } from '../src/analysis';
import { astEqual } from './roundtrip';
import type { Chunk } from '../src/ast';

function* walk(dir: string): Generator<string> {
  for (const entry of readdirSync(dir)) {
    const p = join(dir, entry);
    if (statSync(p).isDirectory()) yield* walk(p);
    else if (entry.endsWith('.lua')) yield p;
  }
}

/** Count every AST node (kind field walk — works for exprs/stats/types). */
function countNodes(node: unknown): number {
  if (Array.isArray(node)) return node.reduce<number>((n, v) => n + countNodes(v), 0);
  if (node === null || typeof node !== 'object') return 0;
  const obj = node as Record<string, unknown>;
  let n = typeof obj.kind === 'string' ? 1 : 0;
  for (const key of Object.keys(obj)) {
    if (key === 'kind' || key === 'location') continue;
    n += countNodes(obj[key]);
  }
  return n;
}

const root = process.argv[2];
if (!root) {
  console.error('usage: bun run corpus.ts <corpus-root> [--parse|--roundtrip|--analyze]');
  process.exit(2);
}
const parseMode = process.argv.includes('--parse');
const roundtripMode = process.argv.includes('--roundtrip');
const analyzeMode = process.argv.includes('--analyze');

let total = 0;
let accepted = 0;
const rejects: Array<{ file: string; error: string }> = [];
let totalBytes = 0;
let totalTokens = 0;
let totalNodes = 0;

// analysis aggregates
let units = 0;
let captureCount = 0;
let valCount = 0;
let refCount = 0;
let planEntries = 0;
let protectedEntries = 0;
let inlineEntries = 0;
let maxPool = 0;
let maxPoolFile = '';
const invariantViolations: string[] = [];

for (const file of walk(root)) {
  const buf = readFileSync(file);
  totalBytes += buf.length;
  // latin1 decode: one char code per byte (byte-string model)
  const source = buf.toString('latin1');
  total++;
  try {
    const tokens = new Lexer(source).tokenize();
    totalTokens += tokens.length;
    if (parseMode || roundtripMode || analyzeMode) {
      const chunk: Chunk = parse(source);
      totalNodes += countNodes(chunk);
      if (roundtripMode) {
        const printed = print(chunk);
        const reparsed = parse(printed);
        if (!astEqual(chunk, reparsed)) {
          throw new Error('ROUND-TRIP MISMATCH: parse → print → parse diverged');
        }
      }
      if (analyzeMode) {
        const r = analyze(chunk);
        units += r.captures.size;
        for (const [unit, list] of r.captures) {
          const seen = new Set<unknown>();
          for (const ci of list) {
            captureCount++;
            if (ci.mode === 'val') valCount++; else refCount++;
            if (ci.mode === 'val' !== (ci.proof === 'never-assigned')) {
              invariantViolations.push(`${file}: mode/proof mismatch`);
            }
            if (seen.has(ci.local)) {
              invariantViolations.push(`${file}: duplicate capture entry`);
            }
            seen.add(ci.local);
          }
          void unit;
        }
        for (const p of r.constPlan.values()) {
          planEntries += p.length;
          const keys = new Set(p.map((e) => e.key));
          if (keys.size !== p.length) {
            invariantViolations.push(`${file}: plan keys not deduped`);
          }
          for (const e of p) {
            if (e.protect) protectedEntries++;
            if (e.inlineOk) {
              inlineEntries++;
              if (e.kind !== 'number') invariantViolations.push(`${file}: non-number inlineOk`);
            }
          }
          if (p.length > maxPool) { maxPool = p.length; maxPoolFile = file; }
        }
      }
    }
    accepted++;
  } catch (e) {
    rejects.push({ file, error: e instanceof Error ? e.message : String(e) });
  }
}

console.log(`mode:          ${roundtripMode ? 'roundtrip (parse→print→parse→astEqual)' : analyzeMode ? 'analyze (parse→analysis)' : parseMode ? 'parse (tokens→AST)' : 'lex'}`);
console.log(`corpus files:  ${total}`);
console.log(`accepted:      ${accepted}`);
console.log(`rejected:      ${rejects.length}`);
console.log(`total bytes:   ${totalBytes}`);
console.log(`total tokens:  ${totalTokens}`);
if (parseMode || analyzeMode) console.log(`total nodes:   ${totalNodes}`);
if (analyzeMode) {
  console.log(`units:         ${units}`);
  console.log(`captures:      ${captureCount} (val ${valCount} / ref ${refCount})`);
  console.log(`plan entries:  ${planEntries} (protected ${protectedEntries}, inline ${inlineEntries})`);
  console.log(`max pool:      ${maxPool} (${maxPoolFile})`);
  console.log(`invariants:    ${invariantViolations.length === 0 ? 'OK' : `${invariantViolations.length} VIOLATIONS`}`);
  for (const v of invariantViolations.slice(0, 10)) console.log(`  ! ${v}`);
}
if (rejects.length > 0) {
  console.log('\nrejects:');
  for (const r of rejects.slice(0, 25)) console.log(`  ${r.file}: ${r.error}`);
  if (rejects.length > 25) console.log(`  ...and ${rejects.length - 25} more`);
}
