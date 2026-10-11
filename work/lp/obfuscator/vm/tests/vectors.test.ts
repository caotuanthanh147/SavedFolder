/**
 * Crypto vector tests: the VENDORED Lua crypto (runtime/crypto/*.lua —
 * byte-identical copies of M3's loader/crypto) executed on real lua5.4
 * against contracts/test_vectors.json (outside source, §22.1) — plus the
 * const-key chain parity vs M5's TS implementation (BYTECODE-M5 §6.2) and
 * the FNV/DJB2 family KATs (M13 pair, D-M6-5).
 */

import { describe, expect, test } from 'bun:test';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { runLua } from './helpers';
import { fnv1a32ts, djb2ts } from '../src/emit';
import { constKeyChainRoot, constKeyChainStep } from '../../compiler/src/container';
import { toHex } from '../../compiler/src/opcode';

const vectors = JSON.parse(
  readFileSync(join(import.meta.dir, '../../../contracts/test_vectors.json'), 'utf8'),
) as Record<string, unknown>;

const CRYPTO_DIR = join(import.meta.dir, '..', 'runtime', 'crypto');

function escapeLua(bytes: string): string {
  let out = '';
  for (let i = 0; i < bytes.length; i++) out += `\\${String(bytes.charCodeAt(i)).padStart(3, '0')}`;
  return out;
}

/** Harness loading the vendored files raw (dofile) and running checks. */
function vendorHarness(body: string): string {
  const prelude = `local B = dofile("${CRYPTO_DIR}/bit.lua")()
local SH = dofile("${CRYPTO_DIR}/sha2.lua")(B)
local HM = dofile("${CRYPTO_DIR}/hmac.lua")(B, SH)
local HK = dofile("${CRYPTO_DIR}/hkdf.lua")(HM)
local FH = dofile("${CRYPTO_DIR}/fnv.lua")(B)
local function unhex(h)
  local o = {}
  for i = 1, #h, 2 do o[#o + 1] = string.char(tonumber(h:sub(i, i + 1), 16)) end
  return table.concat(o)
end
local function hex(s)
  local o = {}
  for i = 1, #s do o[i] = string.format("%02x", s:byte(i)) end
  return table.concat(o)
end
`;
  return runLua({ 'h.lua': prelude + body }, 'h.lua');
}

describe('vendored crypto on lua5.4 vs contracts/test_vectors.json', () => {
  test('sha256 FIPS 180-4 vectors (empty/abc/200a/1000a)', () => {
    const cases: [string, string][] = [
      ['sha256_empty', ''],
      ['sha256_abc', 'abc'],
    ];
    // 200a / 1000a are long repeated inputs; pass as hex through unhex.
    const body = [
      ...cases.map(
        ([key, msg]) =>
          `print("${key}=" .. hex(SH.sha256("${escapeLua(msg)}")))`,
      ),
      `print("sha256_200a=" .. hex(SH.sha256(unhex(("61"):rep(200)))))`,
      `print("sha256_1000a=" .. hex(SH.sha256(unhex(("61"):rep(1000)))))`,
    ].join('\n');
    const out = vendorHarness(body);
    for (const key of ['sha256_empty', 'sha256_abc', 'sha256_200a', 'sha256_1000a']) {
      expect(out).toContain(`${key}=${vectors[key]}`);
    }
  });

  test('hkdf RFC 5869 TC1-3', () => {
    const tcs = [vectors.hkdf_tc1, vectors.hkdf_tc2, vectors.hkdf_tc3] as {
      ikm: string; salt: string; info: string; okm: string; L: number;
    }[];
    const body = tcs
      .map(
        (tc, i) =>
          `print("tc${i}=" .. hex(HK.hkdf_sha256(unhex("${tc.ikm}"), unhex("${tc.salt}"), unhex("${tc.info}"), ${tc.L})))`,
      )
      .join('\n');
    const out = vendorHarness(body);
    tcs.forEach((tc, i) => {
      expect(out).toContain(`tc${i}=${tc.okm}`);
    });
  });

  test('const-key chain parity vs M5 TS (root + steps 1..3)', () => {
    const ikm = new Uint8Array(32);
    crypto.getRandomValues(ikm);
    const rootTs = constKeyChainRoot(ikm);
    const steps: Uint8Array[] = [];
    let k = rootTs;
    for (let i = 1; i <= 3; i++) {
      k = constKeyChainStep(k, i);
      steps.push(k);
    }
    const body = [
      `local ikm = unhex("${toHex(ikm)}")`,
      `local k0 = HK.hkdf_sha256(ikm, "", "const-key", 32)`,
      `print("k0=" .. hex(k0))`,
      `local k = k0`,
      `for n = 1, 3 do`,
      `\tk = HK.hkdf_sha256(k, string.char(0, 0, 0, n), "const-key", 32)`,
      `\tprint("k" .. n .. "=" .. hex(k))`,
      `end`,
    ].join('\n');
    const out = vendorHarness(body);
    expect(out).toContain(`k0=${toHex(rootTs)}`);
    steps.forEach((s, i) => {
      expect(out).toContain(`k${i + 1}=${toHex(s)}`);
    });
  });
});

describe('FNV-1a32 + DJB2 family (M13 pair, D-M6-5)', () => {
  const KATS: [string, number, number][] = [
    // draft-eastlake-fnv FNV-1a 32 / classic Bernstein DJB2
    ['', 0x811c9dc5, 5381],
    ['a', 0xe40c292c, 177670],
    ['b', 0xe70c2de5, 177671],
    ['foobar', 0xbf9cf968, 4259602622],
  ];

  test('TS mirror matches draft-eastlake-fnv + Bernstein KATs', () => {
    for (const [s, fnv, djb] of KATS) {
      expect(fnv1a32ts(s)).toBe(fnv);
      expect(djb2ts(s)).toBe(djb);
    }
  });

  test('vendored Lua pair matches the TS mirror on varied inputs', () => {
    const inputs = ['hello world', 'LPVB\x00\x01\x02', 'x'.repeat(1000), '\xff\xfe\xfb'];
    const body = inputs
      .map(
        (s, i) =>
          `print("p${i}=" .. string.format("%d", FH.fnv1a("${escapeLua(s)}")) .. "," .. string.format("%d", FH.djb2("${escapeLua(s)}")))`,
      )
      .join('\n');
    const out = vendorHarness(body);
    inputs.forEach((s, i) => {
      expect(out).toContain(`p${i}=${fnv1a32ts(s)},${djb2ts(s)}`);
    });
  });
});
