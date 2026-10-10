/**
 * Private corpus runner (NOT shipped to Public — the corpus is the project's
 * captured material). Lexes every .lua file in the corpus root and reports
 * accept/reject per file with error positions for rejects.
 *
 * Run: bun run corpus.ts <corpus-root>
 */
import { readdirSync, readFileSync, statSync } from 'node:fs';
import { join } from 'node:path';
import { Lexer } from '../src/lexer';

function* walk(dir: string): Generator<string> {
  for (const entry of readdirSync(dir)) {
    const p = join(dir, entry);
    if (statSync(p).isDirectory()) yield* walk(p);
    else if (entry.endsWith('.lua')) yield p;
  }
}

const root = process.argv[2];
if (!root) {
  console.error('usage: bun run corpus.ts <corpus-root>');
  process.exit(2);
}

let total = 0;
let accepted = 0;
const rejects: Array<{ file: string; error: string }> = [];
let totalBytes = 0;
let totalTokens = 0;

for (const file of walk(root)) {
  const buf = readFileSync(file);
  totalBytes += buf.length;
  // latin1 decode: one char code per byte (byte-string model)
  const source = buf.toString('latin1');
  total++;
  try {
    const tokens = new Lexer(source).tokenize();
    totalTokens += tokens.length;
    accepted++;
  } catch (e) {
    rejects.push({ file, error: e instanceof Error ? e.message : String(e) });
  }
}

console.log(`corpus files: ${total}`);
console.log(`accepted:     ${accepted}`);
console.log(`rejected:     ${rejects.length}`);
console.log(`total bytes:  ${totalBytes}`);
console.log(`total tokens: ${totalTokens}`);
if (rejects.length > 0) {
  console.log('\nrejects:');
  for (const r of rejects.slice(0, 25)) console.log(`  ${r.file}: ${r.error}`);
  if (rejects.length > 25) console.log(`  ...and ${rejects.length - 25} more`);
}
