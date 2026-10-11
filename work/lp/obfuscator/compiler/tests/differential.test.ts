/**
 * Differential tests (§10.3, D-M5-13): every fixture's SOURCE runs under
 * the real Lua interpreter (portable Lua 5.4.7 — the outside oracle,
 * §22.1 "the original script's behavior"); the paired AST runs through
 * compile → pack (per-build opcode permutation + AEAD const pool) →
 * unpack → reference interpreter. Stdout must match byte-for-byte.
 */
import { describe, expect, test } from 'bun:test';
import { spawnSync } from 'node:child_process';
import { mkdtempSync, writeFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { compileProgram } from '../src/compile';
import { pack, unpack, randomBytes } from '../src/container';
import { runContainer, makeInterpreterEnv, LuaTable, type LuaValue, type HostFunction } from '../src/interpreter';
import { FIXTURES } from './fixtures';

const LUA54 = process.env.LUA54 ?? join(process.env.HOME ?? '/home/z', '.lua54', 'bin', 'lua5.4');

function runRealLua(source: string): string {
  const dir = mkdtempSync(join(tmpdir(), 'm5-diff-'));
  const file = join(dir, 'fixture.lua');
  writeFileSync(file, source, 'utf8');
  try {
    const res = spawnSync(LUA54, [file], { encoding: 'utf8', timeout: 10_000 });
    if (res.error) throw res.error;
    if (res.status !== 0) {
      throw new Error(`real lua failed (${res.status}): ${res.stderr}`);
    }
    return res.stdout;
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
}

function runProtected(ast: Parameters<typeof compileProgram>[0]): string {
  const lines: string[] = [];
  const { protos } = compileProgram(ast);
  const key = randomBytes(32);
  const seed = randomBytes(32);
  const { container } = pack(protos, { constKey: key, opcodeSeed: seed });
  const loaded = unpack(container, { constKey: key, opcodeSeed: seed });
  const env = makeInterpreterEnv();
  // Buffer-collecting print (same \t join as Lua's print).
  const print: HostFunction = (args: readonly LuaValue[]): LuaValue[] => {
    lines.push(args.map((a) => env.get('tostring') ? luaToDisplay(a, env) : String(a)).join('\t'));
    return [];
  };
  env.set('print', print);
  runContainer(loaded, env);
  return lines.join('\n') + (lines.length ? '\n' : '');
}

function luaToDisplay(v: LuaValue, env: LuaTable): string {
  const tostring = env.get('tostring') as HostFunction | null;
  if (tostring && typeof tostring === 'function') return String(tostring([v])[0]);
  return String(v);
}

describe('differential vs real Lua 5.4', () => {
  for (const fixture of FIXTURES) {
    test(`fixture: ${fixture.name}`, () => {
      const expected = runRealLua(fixture.source);
      const actual = runProtected(fixture.ast);
      expect(actual).toBe(expected);
    });
  }

  test('fixture count sanity (all named uniquely)', () => {
    const names = FIXTURES.map((f) => f.name);
    expect(new Set(names).size).toBe(names.length);
    expect(names.length).toBeGreaterThanOrEqual(15);
  });
});
