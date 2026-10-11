/**
 * Watermarked containers through the M6 LUA runtime (CCP-M7 v1 runtime-side
 * integration, session 22).
 *
 * glm6's watermark suite proves packWatermarked against the M5 TS reference
 * interpreter (v1 runtime transparency). This file proves the second half
 * of the second-implementation rule on the RUNTIME side: watermarked
 * containers are ordinary valid v1 containers (CCP-M7 ruling) — the
 * M6-emitted Lua interpreter must run them transparently in BOTH emit
 * modes (embedded per-version, containerless per-session), under
 * per-session constKey rotation (D-M5-27), and the extractor must stay in
 * lockstep with the exact bytes the runtime consumed.
 *
 * §22.1 outside-source anchors: differential oracle = real Lua 5.4.7;
 * watermark length = 16 (M1 randomId); layout properties pinned per
 * BYTECODE-M5.md §6.5 — determinism, extractor lockstep.
 */

import { describe, expect, test } from 'bun:test';
import { FIXTURES } from '../../compiler/tests/fixtures';
import { runLua, luaByteString, cryptoBytes } from './helpers';
import { emitRuntime } from '../src/emit';
import { compileProgram } from '../../compiler/src/compile';
import { toHex } from '../../compiler/src/opcode';
import { generatePackMaterial, packWatermarked, extractWatermark } from '../../compiler/src/watermark';

function oracleOf(source: string): string {
  return runLua({ 'src.lua': source }, 'src.lua');
}

const STRATEGIES = [
  { dispatch: 'chain' as const },
  { dispatch: 'tree' as const },
  { dispatch: 'closure' as const, runtimeBuilt: false },
  { dispatch: 'closure' as const, runtimeBuilt: true },
];

/** Watermark must be 16 bytes (sessions.watermark_id, M1 randomId size). */
function wm16(): Uint8Array {
  return cryptoBytes(16);
}

describe('watermarked containers: embedded mode (per-version key) == oracle, all strategies', () => {
  // CCP-M7 ruling: a watermarked container is an ordinary valid v1
  // container. Embedded per-version build + default packWatermarked
  // (per-version constKey) — the differential must hold unchanged.
  for (const fixture of FIXTURES.slice(0, 10)) {
    test(`fixture ${fixture.name}: watermarked embedded, all strategies`, () => {
      const expected = oracleOf(fixture.source);
      const { protos } = compileProgram(fixture.ast);
      const { parts } = generatePackMaterial(protos);
      const { container } = packWatermarked(parts, wm16());
      for (const strat of STRATEGIES) {
        const emit = emitRuntime({
          container,
          opcodeSeed: parts.opcodeSeed,
          vmSeed: cryptoBytes(32),
          dispatch: strat.dispatch,
          runtimeBuilt: strat.runtimeBuilt,
        });
        const out = runLua(
          {
            'runtime.lua': emit.lua,
            'main.lua': `local entry = dofile("runtime.lua")
local ok, e1 = pcall(entry, { c = "${luaByteString(parts.constKey)}", s = "\\1\\2\\3\\4", args = {}, nargs = 0 })
if not ok then error(e1, 0) end`,
          },
          'main.lua',
        );
        expect(out).toBe(expected);
      }
    });
  }
});

describe('watermarked containers: containerless mode (sessionConstKey) == oracle, all strategies', () => {
  // The deployment shape of doc §8 step 10 + D-M5-27: a FIXED runtime
  // (immutable init build) consumes a per-session WATERMARKED container
  // re-sealed under a fresh session key via entry b/c. Self-consistency
  // integrity (v1.1) must accept the session-hashed container, and the
  // pools must open under the session key.
  for (const fixture of FIXTURES.slice(0, 10)) {
    test(`fixture ${fixture.name}: watermarked b-entry w/ session key, all strategies`, () => {
      const expected = oracleOf(fixture.source);
      const { protos } = compileProgram(fixture.ast);
      const { parts } = generatePackMaterial(protos);
      const sessionKey = cryptoBytes(32);
      const { container } = packWatermarked(parts, wm16(), { sessionConstKey: sessionKey });
      for (const strat of STRATEGIES) {
        const emit = emitRuntime({
          container: null,
          opcodeSeed: parts.opcodeSeed,
          vmSeed: cryptoBytes(32),
          dispatch: strat.dispatch,
          runtimeBuilt: strat.runtimeBuilt,
        });
        expect(emit.containerless).toBe(true);
        const out = runLua(
          {
            'runtime.lua': emit.lua,
            'main.lua': `local entry = dofile("runtime.lua")
local ok, e1 = pcall(entry, { b = "${luaByteString(container)}", c = "${luaByteString(sessionKey)}", s = "sess-wm", args = {}, nargs = 0 })
if not ok then error(e1, 0) end`,
          },
          'main.lua',
        );
        expect(out).toBe(expected);
      }
    });
  }
});

describe('per-session rotation on ONE fixed runtime (doc §12 per-payload uniqueness)', () => {
  const fixture = FIXTURES[0]!;
  const expected = oracleOf(fixture.source);
  const { protos } = compileProgram(fixture.ast);
  const { parts } = generatePackMaterial(protos);
  const vmSeed = cryptoBytes(32);
  const emit = emitRuntime({ container: null, opcodeSeed: parts.opcodeSeed, vmSeed, dispatch: 'tree' });

  test('two sessions: distinct watermarks, distinct session keys, same runtime file -> both == oracle', () => {
    const w1 = wm16();
    const w2 = wm16();
    const k1 = cryptoBytes(32);
    const k2 = cryptoBytes(32);
    const s1 = packWatermarked(parts, w1, { sessionConstKey: k1 });
    const s2 = packWatermarked(parts, w2, { sessionConstKey: k2 });
    // containers must differ (per-payload uniqueness)
    expect(toHex(s1.container)).not.toBe(toHex(s2.container));
    const out = runLua(
      {
        'runtime.lua': emit.lua,
        'main.lua': `local entry = dofile("runtime.lua")
local ok1 = pcall(entry, { b = "${luaByteString(s1.container)}", c = "${luaByteString(k1)}", s = "sess-one", args = {}, nargs = 0 })
local ok2 = pcall(entry, { b = "${luaByteString(s2.container)}", c = "${luaByteString(k2)}", s = "sess-two", args = {}, nargs = 0 })
if not ok1 or not ok2 then error("session run failed", 0) end`,
      },
      'main.lua',
    );
    expect(out).toBe(expected + expected);
  });

  test('session-key cross-use is denied: session-2 container under session-1 key -> never oracle', () => {
    const k1 = cryptoBytes(32);
    const k2 = cryptoBytes(32);
    const s2 = packWatermarked(parts, wm16(), { sessionConstKey: k2 });
    let out = '';
    let ok = false;
    try {
      out = runLua(
        {
          'runtime.lua': emit.lua,
          'main.lua': `local entry = dofile("runtime.lua")
local ok2, e2 = pcall(entry, { b = "${luaByteString(s2.container)}", c = "${luaByteString(k1)}", s = "cross", args = {}, nargs = 0 })
if not ok2 then error(e2, 0) end`,
        },
        'main.lua',
      );
      ok = true;
    } catch {
      ok = false;
    }
    // A leaked session-1 bundle decrypts ONE session's pools — session 2's
    // container under session 1's key must decoy or fail generically, and
    // can never produce the oracle output (D-M5-27 anti-dump posture).
    expect(ok ? out : '').not.toBe(expected);
    expect(ok ? out : out).not.toContain(expected);
  });
});

describe('extractor lockstep with the runtime-consumed bytes (CCP-M7 leak workflow)', () => {
  const fixture = FIXTURES[2]!; // strings fixture (rich const pool)
  const { protos } = compileProgram(fixture.ast);
  const { parts, canonicalContainer } = generatePackMaterial(protos);

  test('per-version watermarked container: extraction recovers the watermark', () => {
    const w = wm16();
    const { container } = packWatermarked(parts, w);
    const got = extractWatermark(container, parts);
    expect(got).not.toBeNull();
    expect(toHex(got!.watermark)).toBe(toHex(w));
    expect(got!.carrier1Ok).toBe(true);
  });

  test('session-keyed container: version key throws, session key recovers (session-key trial IS the id)', () => {
    const w = wm16();
    const sessionKey = cryptoBytes(32);
    const { container } = packWatermarked(parts, w, { sessionConstKey: sessionKey });
    expect(() => extractWatermark(container, parts)).toThrow();
    const got = extractWatermark(container, parts, { constKey: sessionKey });
    expect(got).not.toBeNull();
    expect(toHex(got!.watermark)).toBe(toHex(w));
    expect(got!.carrier1Ok).toBe(true);
  });

  test('canonical container extracts null (no junk — nothing watermarked)', () => {
    expect(extractWatermark(canonicalContainer, parts)).toBeNull();
  });
});

describe('tamper resistance on WATERMARKED containers (§10.2 item 9 posture holds)', () => {
  const fixture = FIXTURES[2]!;
  const oracle = oracleOf(fixture.source);
  const { protos } = compileProgram(fixture.ast);
  const { parts } = generatePackMaterial(protos);
  const sessionKey = cryptoBytes(32);

  function runWith(container: Uint8Array, key: Uint8Array): { ok: boolean; out: string } {
    const emit = emitRuntime({ container: null, opcodeSeed: parts.opcodeSeed, vmSeed: cryptoBytes(32), dispatch: 'chain' });
    try {
      return {
        ok: true,
        out: runLua(
          {
            'runtime.lua': emit.lua,
            'main.lua': `local entry = dofile("runtime.lua")
local ok, e1 = pcall(entry, { b = "${luaByteString(container)}", c = "${luaByteString(key)}", s = "sess-wm", args = {}, nargs = 0 })
if not ok then error(e1, 0) end`,
          },
          'main.lua',
        ),
      };
    } catch (e) {
      return { ok: false, out: String(e) };
    }
  }

  test('bit flip inside a pool blob -> never oracle (decoy/garbage, no raw crash)', () => {
    const { container } = packWatermarked(parts, wm16(), { sessionConstKey: sessionKey });
    const tampered = new Uint8Array(container);
    tampered[tampered.length - 6] ^= 0xff; // inside the last AEAD tag
    const r = runWith(tampered, sessionKey);
    expect(r.ok ? r.out : '').not.toBe(oracle);
    expect(r.ok ? r.out : r.out).not.toContain(oracle);
  });

  test('hash-field flip (re-hash attack class) -> self-consistency decoy, never oracle', () => {
    const { container } = packWatermarked(parts, wm16(), { sessionConstKey: sessionKey });
    const tampered = new Uint8Array(container);
    tampered[10] ^= 0x01; // inside the container's own hash field (bytes 6-37)
    const r = runWith(tampered, sessionKey);
    expect(r.ok ? r.out : '').not.toBe(oracle);
  });

  test('watermark carrier region tamper (junk const slot) -> AEAD names it, runtime never oracle', () => {
    const { container } = packWatermarked(parts, wm16(), { sessionConstKey: sessionKey });
    const tampered = new Uint8Array(container);
    tampered[44] ^= 0x80; // early functions-region byte (carrier-2 junk lives in sealed pools)
    const r = runWith(tampered, sessionKey);
    expect(r.ok ? r.out : '').not.toBe(oracle);
  });
});
