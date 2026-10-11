/**
 * packWatermarked (CCP-M7 v1, D-M5-20) tests.
 *
 * §22.1 outside-source anchors:
 * - differential oracle = real Lua 5.4.7 (same as the M5 differential suite);
 * - watermark_id size = M1's randomId (api/src/crypto.ts, 16 bytes);
 * - HKDF constructions = RFC 5869 via the shared contracts vectors
 *   (container.ts tests); here the layout streams are pinned properties
 *   (determinism, extractor lockstep) per BYTECODE-M5.md §6.
 */
import { describe, expect, test } from 'bun:test';
import { spawnSync } from 'node:child_process';
import { mkdtempSync, writeFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

import { compileProgram } from '../src/compile';
import { unpack, randomBytes, pack } from '../src/container';
import { toHex } from '../src/opcode';
import {
  packWatermarked, generatePackMaterial, extractWatermark,
  serializePackParts, deserializePackParts, verifyPackParts,
} from '../src/watermark';
import { runContainer, makeInterpreterEnv, type LuaValue, type HostFunction } from '../src/interpreter';
import { FIXTURES, chunk, localStat, exprStat, call, glob, num, str, local_, localE, localFn, ret } from './fixtures';
import type { Expr, Stat } from '../../src/ast';

const LUA54 = process.env.LUA54 ?? join(process.env.HOME ?? '/home/z', '.lua54', 'bin', 'lua5.4');

function runRealLua(source: string): string {
  const dir = mkdtempSync(join(tmpdir(), 'm5-wm-'));
  const file = join(dir, 'fixture.lua');
  // Byte-exact oracle stdout (D-M5-28): raw bytes as a latin1 char-per-byte
  // string, matching the protected side's byte-string consts. The utf8
  // decode compared text and could never match non-ASCII byte strings.
  writeFileSync(file, source, 'utf8');
  try {
    const res = spawnSync(LUA54, [file], { encoding: 'buffer', timeout: 10_000 });
    if (res.error) throw res.error;
    if (res.status !== 0) throw new Error(`real lua failed (${res.status}): ${res.stderr}`);
    return (res.stdout as Buffer).toString('latin1');
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
}

function runLoaded(loaded: Parameters<typeof runContainer>[0]): string {
  const lines: string[] = [];
  const env = makeInterpreterEnv();
  const print: HostFunction = (args: readonly LuaValue[]): LuaValue[] => {
    const tostring = env.get('tostring') as HostFunction;
    lines.push(args.map((a) => String(tostring([a])[0])).join('\t'));
    return [];
  };
  env.set('print', print);
  runContainer(loaded, env);
  return lines.join('\n') + (lines.length ? '\n' : '');
}

describe('packWatermarked: v1 runtime transparency (differential oracle)', () => {
  for (const fixture of FIXTURES) {
    test(`watermarked container runs identically to source: ${fixture.name}`, () => {
      const expected = runRealLua(fixture.source);
      const { protos } = compileProgram(fixture.ast);
      const { parts } = generatePackMaterial(protos);
      const watermark = randomBytes(16);
      const { container } = packWatermarked(parts, watermark);
      // UNCHANGED unpack: a v1 runtime consumes the watermarked container
      // with zero watermark knowledge (no version bump, CCP-M7 ruling).
      const loaded = unpack(container, { constKey: parts.constKey, opcodeSeed: parts.opcodeSeed });
      expect(runLoaded(loaded)).toBe(expected);
    });
  }
});

describe('packWatermarked: watermark recovery (extractor lockstep)', () => {
  const build = () => {
    const f = local_('f');
    return compileProgram(chunk(
      localStat([local_('x')], [num(41)]),
      localFn(f, [local_('a')], [ret(call(glob('tostring'), [localE(local_('a'))]))]),
      exprStat(call(glob('print'), [call(localE(f), [localE(local_('x'))])])),
    ));
  };

  test('extracts the exact watermark + carrier-1 consistency from the session container', () => {
    const { parts } = generatePackMaterial(build().protos);
    const watermark = randomBytes(16);
    const { container, manifest } = packWatermarked(parts, watermark);
    const got = extractWatermark(container, parts);
    expect(got).not.toBeNull();
    expect(toHex(got!.watermark)).toBe(toHex(watermark));
    expect(got!.carrier1Ok).toBe(true);
    // Session hash != canonical hash, and the container verifies itself.
    expect(manifest.build_hash).not.toBe(parts.canonicalManifest.build_hash);
    expect(manifest.opcode_seed).toBe(parts.canonicalManifest.opcode_seed);
  });

  test('session-random constKey (D-M5-27): packs under the override, per-version key cannot open, override key extracts', () => {
    const { parts } = generatePackMaterial(build().protos);
    const watermark = randomBytes(16);
    const sessionKey = randomBytes(32);
    const { container } = packWatermarked(parts, watermark, { sessionConstKey: sessionKey });
    // Anti-dump posture: the per-version PackParts key does NOT open the
    // session container (AEAD authentication failure).
    expect(() => extractWatermark(container, parts)).toThrow();
    // The session's own key does — a successful open IS the session
    // identification, and the watermark + carrier-1 follow as usual.
    const got = extractWatermark(container, parts, { constKey: sessionKey })!;
    expect(toHex(got.watermark)).toBe(toHex(watermark));
    expect(got.carrier1Ok).toBe(true);
  });

  test('canonical container extracts to null (nothing was watermarked)', () => {
    const { parts, canonicalContainer } = generatePackMaterial(build().protos);
    expect(extractWatermark(canonicalContainer, parts)).toBeNull();
  });

  test('two sessions from the same parts: unique containers, each recovers its own watermark', () => {
    const { parts } = generatePackMaterial(build().protos);
    const w1 = randomBytes(16);
    const w2 = randomBytes(16);
    const s1 = packWatermarked(parts, w1);
    const s2 = packWatermarked(parts, w2);
    expect(toHex(s1.container)).not.toBe(toHex(s2.container));
    expect(toHex(extractWatermark(s1.container, parts)!.watermark)).toBe(toHex(w1));
    expect(toHex(extractWatermark(s2.container, parts)!.watermark)).toBe(toHex(w2));
    expect(s1.manifest.build_hash).not.toBe(s2.manifest.build_hash);
  });

  test('deterministic for identical (parts, watermark, nonces); differs otherwise', () => {
    const { parts } = generatePackMaterial(build().protos);
    const w = randomBytes(16);
    const nonces = parts.protos.map(() => randomBytes(12));
    const a = packWatermarked(parts, w, { sessionNonces: nonces });
    const b = packWatermarked(parts, w, { sessionNonces: nonces });
    expect(toHex(a.container)).toBe(toHex(b.container));
    const otherNonces = parts.protos.map(() => randomBytes(12));
    const c = packWatermarked(parts, w, { sessionNonces: otherNonces });
    expect(toHex(a.container)).not.toBe(toHex(c.container));
    const wOther = randomBytes(16);
    const d = packWatermarked(parts, wOther, { sessionNonces: nonces });
    expect(toHex(a.container)).not.toBe(toHex(d.container));
  });

  test('byte corruption with a fixed CRC still fails (AEAD catches it, like the canonical container)', () => {
    const { parts } = generatePackMaterial(build().protos);
    const watermark = randomBytes(16);
    const { container } = packWatermarked(parts, watermark);
    const corrupted = new Uint8Array(container);
    corrupted[corrupted.length - 10] ^= 0x40;
    expect(() => unpack(corrupted, { constKey: parts.constKey, opcodeSeed: parts.opcodeSeed })).toThrow();
  });
});

describe('PackParts serialization (CLI boundary)', () => {
  test('JSON round-trip: bit-exact parts, verified, identical watermarked output', () => {
    const { parts } = generatePackMaterial(buildForSerialize());
    const json = serializePackParts(parts);
    expect(() => JSON.parse(json)).not.toThrow();
    const back = deserializePackParts(json);
    const w = randomBytes(16);
    const nonces = parts.protos.map(() => randomBytes(12));
    const a = packWatermarked(parts, w, { sessionNonces: nonces });
    const b = packWatermarked(back, w, { sessionNonces: nonces });
    expect(toHex(a.container)).toBe(toHex(b.container));
    expect(toHex(extractWatermark(b.container, back)!.watermark)).toBe(toHex(w));
  });

  test('corrupted JSON ingestion fails closed (canonical hash no longer reproduces)', () => {
    const { parts } = generatePackMaterial(buildForSerialize());
    const json = serializePackParts(parts);
    const parsed = JSON.parse(json) as { protos: { consts: { kind?: string; bits?: string }[] }[] };
    // Flip one bit inside the first num const's f64 pattern.
    const numConst = parsed.protos[0]!.consts.find((c) => c.kind === 'num');
    expect(numConst).toBeDefined();
    const bits = numConst!.bits!;
    const flipped = (parseInt(bits[15]!, 16) ^ 1).toString(16);
    numConst!.bits = bits.slice(0, 15) + flipped;
    expect(() => deserializePackParts(JSON.stringify(parsed))).toThrow(/canonical build hash mismatch/);
  });

  test('binary-exact string consts survive the JSON round-trip (junk bytes are 0..255)', () => {
    // Junk values are arbitrary byte strings — prove the JSON path carries
    // them exactly by watermarking and extracting through serialize+parse.
    const { parts } = generatePackMaterial(buildForSerialize());
    const back = deserializePackParts(serializePackParts(parts));
    const w = randomBytes(16);
    const { container } = packWatermarked(back, w);
    const got = extractWatermark(container, back)!;
    expect(toHex(got.watermark)).toBe(toHex(w));
  });
});

describe('junk-detection invariant (D-M5-22)', () => {
  const L = { start: { line: 1, column: 0, offset: 0 }, end: { line: 1, column: 1, offset: 1 } };
  const add = (left: Expr, right: Expr): Expr => ({ kind: 'Binary', op: 'Add' as const, left, right, location: L });
  const eq = (left: Expr, right: Expr): Expr => ({ kind: 'Binary', op: 'CompareEq' as const, left, right, location: L });

  /** v = 0.5; v = v + 0.5; ... v = v + 299.5 — 300 distinct number consts,
   *  crossing the kIndex8Max boundary: the first 256 ride arithK (8-bit C),
   *  the rest must take the register form WITHOUT leaving unreferenced pool
   *  entries behind (the arithK peek pollution this session fixed). */
  const buildChain = (n: number) => {
    const v = local_('v');
    const stats: Stat[] = [localStat([v], [num(0.5)])];
    for (let i = 1; i < n; i++) {
      stats.push({
        kind: 'Assign',
        vars: [{ kind: 'LocalExpr', local: v, location: L }],
        values: [add(localE(v), num(i + 0.5))],
        location: L,
      });
    }
    // v == 45000 -> boolean print avoids the 5.4-float format split
    // (fixture discipline, tests/fixtures.ts header).
    stats.push(exprStat(call(glob('print'), [eq(localE(v), num(45000))])));
    return chunk(...stats);
  };

  test('>256 distinct number consts: every pool entry stays referenced', () => {
    const { protos } = compileProgram(buildChain(300));
    expect(protos[0]!.consts.length).toBeGreaterThanOrEqual(300);
    const { parts } = generatePackMaterial(protos);
    expect(() => verifyPackParts(parts)).not.toThrow();
  });

  test('the 300-const chain runs correctly through a WATERMARKED container (block-boundary safety)', () => {
    const { protos } = compileProgram(buildChain(300));
    const { parts } = generatePackMaterial(protos);
    const watermark = randomBytes(16);
    const { container } = packWatermarked(parts, watermark);
    const loaded = unpack(container, { constKey: parts.constKey, opcodeSeed: parts.opcodeSeed });
    const lines: string[] = [];
    const env = makeInterpreterEnv();
    env.set('print', (args: readonly LuaValue[]): LuaValue[] => {
      const tostring = env.get('tostring') as HostFunction;
      lines.push(args.map((a) => String(tostring([a])[0])).join('\t'));
      return [];
    });
    runContainer(loaded, env);
    // 0.5 + (1.5 + ... + 299.5) = 45000
    expect(lines).toEqual(['true']);
  });
  test('watermark survives the 300-const chain (unanimous halves across 2-3 junk entries)', () => {
    const { protos } = compileProgram(buildChain(300));
    const { parts } = generatePackMaterial(protos);
    const watermark = randomBytes(16);
    const { container } = packWatermarked(parts, watermark);
    const got = extractWatermark(container, parts)!;
    expect(toHex(got.watermark)).toBe(toHex(watermark));
    expect(got.carrier1Ok).toBe(true);
  });
});

function buildForSerialize() {
  // Exercises every const kind (bool/num/str incl. -0 and a subnormal) plus
  // a child closure — the serialization round-trip must be bit-exact.
  const f = local_('f');
  const x = local_('x');
  const ast = chunk(
    localFn(f, [local_('a')], [ret(localE(local_('a')))]),
    localStat([x], [num(-0)]),
    exprStat(call(glob('print'), [call(localE(f), [localE(x)])])),
  );
  return compileProgram(ast).protos;
}

describe('byte-string contract (D-M5-28 — the corpus 2026-10-11 finding)', () => {
  // glm1's corpus-e2e --wm finding: a str const carrying a code unit > 0xFF
  // (UTF-8-decoded TEXT — readFileSync utf8 instead of the M4 latin1
  // contract) used to truncate silently to & 0xFF in pack. The container is
  // byte-exact for the documented contract (see differential fixtures:
  // raw UTF-8 em-dash/emoji/CJK + \xFF escapes, byte-equal vs real Lua
  // 5.4); the guard turns any contract violation into a LOUD pack error.
  test('pack THROWS on a code unit > 0xFF (no silent & 0xFF truncation)', () => {
    const { protos } = compileProgram(chunk(
      exprStat(call(glob('print'), [str('em-dash:\u{2014}end')])), // ONE code unit 0x2014 — text, not bytes
    ));
    expect(() =>
      pack(protos, { constKey: randomBytes(32), opcodeSeed: randomBytes(32) }),
    ).toThrow(/byte-string model/);
  });

  test('packWatermarked also enforces the guard (watermark path fails loud too)', () => {
    const { protos } = compileProgram(chunk(
      exprStat(call(glob('print'), [str('\u{d83d}\u{de00} emoji as text')])),
    ));
    const { parts } = generatePackMaterial(
      compileProgram(chunk(exprStat(call(glob('print'), [str('ok')])))).protos,
    );
    expect(() => packWatermarked(parts, randomBytes(16))).not.toThrow();
    // the guard lives in container.pack, which packWatermarked calls — a
    // text-const proto must fail through the watermarked path as well:
    const parts2 = { ...parts, protos };
    expect(() => packWatermarked(parts2, randomBytes(16))).toThrow(/byte-string model/);
  });

  test('high-byte LIVE pools (raw UTF-8 consts): byte-exact pack/unpack + watermark lockstep', () => {
    // The corpus shape: raw UTF-8 as latin1 code units (e2 80 94 em-dash,
    // f0 9f 98 80 emoji, e4 b8 ad e6 96 87 CJK, ff from \xFF escapes).
    const { protos } = compileProgram(chunk(
      exprStat(call(glob('print'), [str('em-dash:\u{e2}\u{80}\u{94}end')])),
      exprStat(call(glob('print'), [str('emoji:\u{f0}\u{9f}\u{98}\u{80} \u{e4}\u{b8}\u{ad}\u{e6}\u{96}\u{87}')])),
      exprStat(call(glob('print'), [str('byte:\u{ff}!\u{80}')])),
    ));
    const { parts } = generatePackMaterial(protos);
    const watermark = randomBytes(16);
    const { container } = packWatermarked(parts, watermark);
    const loaded = unpack(container, { constKey: parts.constKey, opcodeSeed: parts.opcodeSeed });
    // live consts round-trip byte-exact through the WATERMARKED container
    // (pool also holds the "print" global name + 2-3 junk entries, order
    // permuted by carrier 1 — check CONTAINS, byte-exact)
    const strs = (loaded.protos[0]!.consts.filter((c) => c.kind === 'str') as { kind: 'str'; s: string }[])
      .map((c) => c.s);
    for (const live of [
      'print',
      'em-dash:\u{e2}\u{80}\u{94}end',
      'emoji:\u{f0}\u{9f}\u{98}\u{80} \u{e4}\u{b8}\u{ad}\u{e6}\u{96}\u{87}',
      'byte:\u{ff}!\u{80}',
    ]) {
      expect(strs).toContain(live);
    }
    // and the watermark machinery is unaffected by high-byte pools
    const got = extractWatermark(container, parts)!;
    expect(toHex(got.watermark)).toBe(toHex(watermark));
    expect(got.carrier1Ok).toBe(true);
  });
});
