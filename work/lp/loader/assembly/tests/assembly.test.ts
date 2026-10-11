/**
 * loader/assembly tests — the full §8-steps-6..10 integration under real
 * lua5.4: assembled init (crypto + env_executor + M7 checks + handshake
 * + M6 containerless runtime, one chunk) × the M3 mock M1 server × a
 * compiler fixture. The stub payload is the D-M13-6 shape; the driver
 * fakes the executor surface env_executor feature-detects (request,
 * HttpService-backed JSON, optional readfile).
 */

import { describe, expect, test } from 'bun:test';
import { spawnSync } from 'node:child_process';
import { mkdtempSync, writeFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { assembleInit } from '../src/assemble';
import { emitRuntime } from '../../../obfuscator/vm/src/emit';
import { compileProgram } from '../../../obfuscator/compiler/src/compile';
import { pack } from '../../../obfuscator/compiler/src/container';
import { sha256Raw } from '../../../obfuscator/compiler/src/opcode';
import { FIXTURES } from '../../../obfuscator/compiler/tests/fixtures';

const ROOT = join(import.meta.dir, '../../..'); // the Public repo root
const LOADER = join(ROOT, 'loader');
const LUA54 = process.env.LUA54 ?? join(process.env.HOME ?? '/home/z', '.lua54', 'bin', 'lua5.4');
const LUAC54 = process.env.LUAC54 ?? join(process.env.HOME ?? '/home/z', '.lua54', 'bin', 'luac5.4');

// fixed identities: the mock's Ed25519 signer is the TEST-ONLY Lua
// helper (tests/ed25519_sign.lua) — its secret_to_public(TV1 sk) derives
// ae700b... (self-consistent sign/verify pair; NOT the RFC pk — the
// SHIPPED loader only verifies, RFC 8032 vector-tested in the M3 suite).
// Bake the signer's actual pk so the assembled init's verify matches.
const SIGNING_SK_HEX = '9d61b19deffd5a60ba844af4927d2adf7817f8a7d9987c4bf0be36c17e94d0d2';
const SERVER_PK_HEX = 'ae700b6f7f06a79e714445bf3a342afd42814788bb8784e2b23d7b50f30b0d5d';
const X25519_SK_HEX = '5dab087e624a8a4b79e17f8b83800ee66f3bb1292618b6fd1c2f8b27ff88e0eb';
const SERVER_NONCE_HEX = '11111111111111111111111111111111';
const SCRIPT_ID = 'e2e0123456789abcdeffedcba9876543';
const WATERMARK_HEX = '0f1e2d3c4b5a69788796a5b4c3d2e1f0';
const KEY = 'TEST-AAAAA-BBBBB-CCCCC-DDDDD';
const R_HEX = 'a1b2c3d4e5f60718293a4b5c6d7e8f90a1b2c3d4e5f60718293a4b5c6d7e8f90';
const PROOF_KEY = new TextEncoder().encode('proof-secret-e2e-32-bytes-pad!'); // 30B

function hexToBytes(hex: string): Uint8Array {
  const out = new Uint8Array(hex.length / 2);
  for (let i = 0; i < out.length; i++) out[i] = parseInt(hex.slice(i * 2, i * 2 + 2), 16);
  return out;
}

function bytesToHex(bytes: Uint8Array): string {
  return Array.from(bytes, (b) => b.toString(16).padStart(2, '0')).join('');
}

function luaByteString(bytes: Uint8Array): string {
  let out = '';
  for (let i = 0; i < bytes.length; i++) out += `\\${String(bytes[i]!).padStart(3, '0')}`;
  return out;
}

function runLua(files: Record<string, string>, main: string, args: string[]): string {
  const dir = mkdtempSync(join(tmpdir(), 'lp-asm-'));
  try {
    for (const [name, content] of Object.entries(files)) {
      writeFileSync(join(dir, name), content, 'utf8');
    }
    const res = spawnSync(LUA54, [join(dir, main), ...args], { encoding: 'utf8', timeout: 60_000, cwd: dir });
    if (res.error) throw res.error;
    if (res.status !== 0) throw new Error(`lua failed (${res.status}): ${res.stderr}`);
    return res.stdout;
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
}

interface E2EBuild {
  readonly initLua: string;
  readonly constKeyHex: string;
  readonly container: Uint8Array;
  readonly buildHashHex: string;
}

function buildE2E(fixtureIdx: number): E2EBuild {
  const fixture = FIXTURES[fixtureIdx]!;
  const constKey = new Uint8Array(32);
  crypto.getRandomValues(constKey);
  const opcodeSeed = new Uint8Array(32);
  crypto.getRandomValues(opcodeSeed);
  const vmSeed = new Uint8Array(32);
  crypto.getRandomValues(vmSeed);
  const { protos } = compileProgram(fixture.ast);
  const { container } = pack(protos, { constKey, opcodeSeed });
  const runtimeSource = emitRuntime({ container: null, opcodeSeed, vmSeed, dispatch: 'chain' }).lua;
  const buildHashHex = bytesToHex(sha256Raw(container));
  const initLua = assembleInit({
    runtimeSource,
    loaderRoot: LOADER,
    config: {
      script_id: SCRIPT_ID,
      base_url: 'https://mock-api',
      proof_key: PROOF_KEY,
      verify_pk: hexToBytes(SERVER_PK_HEX),
      lv: '1.2.3',
    },
  });
  return { initLua, constKeyHex: bytesToHex(constKey), container, buildHashHex };
}

function tamperContainer(container: Uint8Array): Uint8Array {
  const c = new Uint8Array(container);
  c[c.length - 6] ^= 0xff; // inside the last AEAD tag, hash field untouched
  return c;
}

type Mode = 'plain' | 'keyed' | 'wrongkey' | 'tampered' | 'noconst';

function driverLua(b: E2EBuild, mode: Mode): string {
  const keyless = mode === 'plain' || mode === 'tampered' || mode === 'noconst';
  const bundle = mode === 'tampered' ? tamperContainer(b.container) : b.container;
  const constKeyOpt = mode === 'noconst' ? '' : `  const_key = "${luaByteString(hexToBytes(b.constKeyHex))}",`;
  const readfile =
    mode === 'keyed' || mode === 'wrongkey'
      ? `_G.readfile = function(path)
  if path == "lp/${SCRIPT_ID}.key" then return "${mode === 'wrongkey' ? 'TEST-WRONG-KEY-AAAA-BBBBB' : KEY}" end
  return nil
end
`
      : '';
  const keyChannelPrint =
    mode === 'keyed'
      ? `local kb = json.decode(server.state.init_request.Body)
print("KEYCHANNEL:" .. tostring(kb.key))
`
      : '';
  return `local ROOT = arg[1]
local function lf(p) return assert(loadfile(ROOT .. "/" .. p), p) end
local B = lf("loader/crypto/bit.lua")()()
local sha2 = lf("loader/crypto/sha2.lua")()(B)
local hmac = lf("loader/crypto/hmac.lua")()(B, sha2)
local encoding = lf("loader/crypto/encoding.lua")()()
local chacha20 = lf("loader/crypto/chacha20.lua")()(B)
local poly1305 = lf("loader/crypto/poly1305.lua")()(B)
local aead = lf("loader/crypto/aead.lua")()(B, chacha20, poly1305)
local hkdf = lf("loader/crypto/hkdf.lua")()(hmac)
local field = lf("loader/crypto/field25519.lua")()(B)
local x25519 = lf("loader/crypto/x25519.lua")()(B, field)
local ed25519 = lf("loader/crypto/ed25519.lua")()(B, field, sha2)
local Crypto = { sha2 = sha2, hmac = hmac, encoding = encoding, chacha20 = chacha20, poly1305 = poly1305, aead = aead, hkdf = hkdf, x25519 = x25519, ed25519 = ed25519 }
local Signer = lf("tests/ed25519_sign.lua")()(B, field, sha2, ed25519)
local json = lf("tests/json_test.lua")()
local MockServer = lf("tests/mock_server.lua")()
local server = MockServer(Crypto, { json_encode = json.encode, json_decode = json.decode }, Signer, {
  signing_sk = "${luaByteString(hexToBytes(SIGNING_SK_HEX))}",
  proof_key = "${luaByteString(PROOF_KEY)}",
  valid_key = "${KEY}",
  keyless = ${keyless ? 'true' : 'false'},
  script_id = "${SCRIPT_ID}",
  build = "b0123456789ab",
  build_hash = "${b.buildHashHex}",
  bundle = "${luaByteString(bundle)}",
  watermark_id = "${WATERMARK_HEX}",
  server_time = os.time(),
  server_x25519_sk = "${luaByteString(hexToBytes(X25519_SK_HEX))}",
  server_nonce = "${luaByteString(hexToBytes(SERVER_NONCE_HEX))}",
${constKeyOpt}
})
local HS = { JSONEncode = function(_, v) return json.encode(v) end, JSONDecode = function(_, s) return json.decode(s) end }
_G.game = { GetService = function(_, name)
  if name == "HttpService" then return HS end
  error("no such service", 0)
end }
_G.request = function(opts) return server.request(opts) end
${readfile}local init = assert(loadfile("init.lua"))
local entry = init()
local ok, r1, r2 = pcall(entry, {
  api = "https://mock-api",
  script_id = "${SCRIPT_ID}",
  build = "b0123456789ab",
  t = os.time(),
  s = "aabbccddeeff0011",
  r = "${R_HEX}",
})
if not ok then
  print("LUAFAIL:" .. tostring(r1))
elseif r1 == nil and r2 ~= nil then
  print("ENTRY-NIL:" .. tostring(r2))
else
${keyChannelPrint}end
`;
}

describe('assembled init — full §8 flow under lua5.4 (M3 mock M1 + M6 runtime)', () => {
  test('keyless happy path: stdout == oracle, byte-for-byte', () => {
    for (const idx of [0, 2, 5]) {
      const fixture = FIXTURES[idx]!;
      const oracle = runLua({ 'src.lua': fixture.source }, 'src.lua', []);
      expect(oracle.length).toBeGreaterThan(0);
      const b = buildE2E(idx);
      const out = runLua({ 'init.lua': b.initLua, 'driver.lua': driverLua(b, 'plain') }, 'driver.lua', [ROOT]);
      expect(out).toBe(oracle);
    }
  });

  test('keyed happy path: cache file -> key -> init body (channel proof) + oracle output', () => {
    const fixture = FIXTURES[0]!;
    const oracle = runLua({ 'src.lua': fixture.source }, 'src.lua', []);
    const b = buildE2E(0);
    const out = runLua({ 'init.lua': b.initLua, 'driver.lua': driverLua(b, 'keyed') }, 'driver.lua', [ROOT]);
    // guest output first (printed during the entry call), marker last
    const marker = `KEYCHANNEL:${KEY}`;
    const idx = out.lastIndexOf(marker);
    expect(idx).toBeGreaterThan(0);
    expect(out.slice(0, idx)).toBe(oracle);
    expect(out.slice(idx)).toBe(marker + '\n');
  });

  test('wrong cached key -> silent auth failure (ENTRY-NIL:auth)', () => {
    const b = buildE2E(0);
    const out = runLua({ 'init.lua': b.initLua, 'driver.lua': driverLua(b, 'wrongkey') }, 'driver.lua', [ROOT]);
    expect(out.trim()).toBe('ENTRY-NIL:auth');
  });

  test('tampered bundle bytes -> runtime decoy -> generic load failed', () => {
    const b = buildE2E(2);
    const out = runLua({ 'init.lua': b.initLua, 'driver.lua': driverLua(b, 'tampered') }, 'driver.lua', [ROOT]);
    expect(out.trim()).toBe('LUAFAIL:load failed');
  });

  test('payload without const_key -> ENTRY-NIL:payload (wire field pending M1)', () => {
    const b = buildE2E(0);
    const out = runLua({ 'init.lua': b.initLua, 'driver.lua': driverLua(b, 'noconst') }, 'driver.lua', [ROOT]);
    expect(out.trim()).toBe('ENTRY-NIL:payload');
  });
});

describe('assembled init — build-level properties (TS side)', () => {
  test('determinism: same inputs -> identical output', () => {
    const a = buildE2E(0);
    const b = buildE2EFixed(a);
    expect(b.initLua).toBe(a.initLua);
  });

  test('no session secrets: constKey bytes never appear in the init source', () => {
    const b = buildE2E(0);
    expect(b.initLua).not.toContain(luaByteString(hexToBytes(b.constKeyHex)));
  });

  test('luac5.4 -p parses the assembled init', () => {
    const b = buildE2E(0);
    const dir = mkdtempSync(join(tmpdir(), 'lp-asm-luac-'));
    try {
      const f = join(dir, 'init.lua');
      writeFileSync(f, b.initLua, 'utf8');
      const res = spawnSync(LUAC54, ['-p', f], { encoding: 'utf8' });
      expect(res.status).toBe(0);
    } finally {
      rmSync(dir, { recursive: true, force: true });
    }
  });

  test('config validation rejects bad inputs', () => {
    const b = buildE2E(0);
    const runtime = emitRuntime({ container: null, opcodeSeed: new Uint8Array(32), vmSeed: new Uint8Array(32) }).lua;
    const base = { runtimeSource: runtime, loaderRoot: LOADER, config: {
      script_id: SCRIPT_ID, base_url: 'https://mock-api', proof_key: PROOF_KEY,
      verify_pk: hexToBytes(SERVER_PK_HEX), lv: '1.2.3',
    } };
    expect(() => assembleInit({ ...base, config: { ...base.config, script_id: 'nothex' } })).toThrow();
    expect(() => assembleInit({ ...base, config: { ...base.config, base_url: 'ftp://x' } })).toThrow();
    expect(() => assembleInit({ ...base, config: { ...base.config, verify_pk: new Uint8Array(31) } })).toThrow();
    expect(() => assembleInit({ ...base, runtimeSource: 'too short' })).toThrow();
    expect(assembleInit(base).length).toBeGreaterThan(50_000);
    void b;
  });
});

/** rebuild with the SAME runtime source + config as a previous build —
 * assembly-level determinism (the runtime's own determinism is tested in
 * the vm package). */
function buildE2EFixed(ref: E2EBuild): E2EBuild {
  const runtimeSource = extractRuntime(ref.initLua);
  const initLua = assembleInit({
    runtimeSource,
    loaderRoot: LOADER,
    config: {
      script_id: SCRIPT_ID,
      base_url: 'https://mock-api',
      proof_key: PROOF_KEY,
      verify_pk: hexToBytes(SERVER_PK_HEX),
      lv: '1.2.3',
    },
  });
  return { initLua, constKeyHex: ref.constKeyHex, container: ref.container, buildHashHex: ref.buildHashHex };
}

/** bracket-level-aware extraction of the embedded runtime literal. */
function extractRuntime(initLua: string): string {
  const m = initLua.match(/runtime = (\[=*\[)/);
  if (!m || m.index === undefined) throw new Error('runtime literal not found');
  const eq = m[1]!.length - 2;
  const closer = `]${'='.repeat(eq)}]`;
  const start = m.index + m[0].length;
  const end = initLua.indexOf(closer, start);
  if (end < 0) throw new Error('runtime literal closer not found');
  return initLua.slice(start, end);
}

