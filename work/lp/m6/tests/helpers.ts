/**
 * M6 test helpers — spawn real Lua 5.4.7 (outside oracle, §22.1), build
 * protected fixtures through the full M5→M6 pipeline, byte-escape keys
 * into runner scripts.
 */

import { spawnSync } from 'node:child_process';
import { mkdtempSync, writeFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { compileProgram } from '../../compiler/src/compile';
import { pack } from '../../compiler/src/container';
import { emitRuntime, type EmitOptions, type EmitResult } from '../src/emit';
import type { Fixture } from '../../compiler/tests/fixtures';

export const LUA54 = process.env.LUA54 ?? join(process.env.HOME ?? '/home/z', '.lua54', 'bin', 'lua5.4');

/** Run a Lua file list; main is the entry file. Returns stdout; throws with
 * stderr on nonzero exit. */
export function runLua(files: Record<string, string>, main: string, timeoutMs = 30_000): string {
  const dir = mkdtempSync(join(tmpdir(), 'm6-'));
  try {
    for (const [name, content] of Object.entries(files)) {
      writeFileSync(join(dir, name), content, 'utf8');
    }
    const res = spawnSync(LUA54, [main], { encoding: 'utf8', timeout: timeoutMs, cwd: dir });
    if (res.error) throw res.error;
    if (res.status !== 0) {
      throw new Error(`lua failed (${res.status}): ${res.stderr}`);
    }
    return res.stdout;
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
}

/** \ddd-escaped Lua string literal body for raw bytes. */
export function luaByteString(bytes: Uint8Array): string {
  let out = '';
  for (let i = 0; i < bytes.length; i++) out += `\\${String(bytes[i]!).padStart(3, '0')}`;
  return out;
}

export interface ProtectedBuild {
  readonly emit: EmitResult;
  readonly constKey: Uint8Array;
  readonly opcodeSeed: Uint8Array;
  readonly vmSeed: Uint8Array;
}

/** Full pipeline: fixture AST → M5 compile → pack → M6 runtime. */
export function buildProtected(
  fixture: Fixture,
  opts: {
    dispatch?: EmitOptions['dispatch'];
    runtimeBuilt?: boolean;
    countHook?: boolean;
    vmSeed?: Uint8Array;
    opcodeSeed?: Uint8Array;
    constKey?: Uint8Array;
    tamperContainer?: (bytes: Uint8Array) => Uint8Array;
  } = {},
): ProtectedBuild {
  const { protos } = compileProgram(fixture.ast);
  const constKey = opts.constKey ?? cryptoBytes(32);
  const opcodeSeed = opts.opcodeSeed ?? cryptoBytes(32);
  const vmSeed = opts.vmSeed ?? cryptoBytes(32);
  let { container } = pack(protos, { constKey, opcodeSeed });
  if (opts.tamperContainer) container = opts.tamperContainer(container);
  const emit = emitRuntime({
    container,
    opcodeSeed,
    vmSeed,
    dispatch: opts.dispatch,
    runtimeBuilt: opts.runtimeBuilt,
    countHook: opts.countHook,
  });
  return { emit, constKey, opcodeSeed, vmSeed };
}

/** Runner script: loads the runtime, calls the entry with key/seed/env. */
export function runnerScript(p: ProtectedBuild, extra = ''): string {
  return `local entry = dofile("runtime.lua")
local c = "${luaByteString(p.constKey)}"
local s = "\\1\\2\\3\\4"
local ok, e1 = pcall(entry, { c = c, s = s, args = {}, nargs = 0 })
if not ok then error(e1, 0) end
${extra}`;
}

export function cryptoBytes(n: number): Uint8Array {
  const out = new Uint8Array(n);
  crypto.getRandomValues(out);
  return out;
}
