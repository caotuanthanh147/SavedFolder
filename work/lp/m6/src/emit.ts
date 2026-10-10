/**
 * M6 runtime emitter — assembles a per-build Lua VM runtime
 * (doc §10.2 items 5-9) that consumes an M5 LPVB container
 * (BYTECODE-M5.md is the normative pin) and executes it inside a real
 * Lua 5.1-syntax-compatible host (lua5.4 oracle, Luau executors).
 *
 * Design anchors (DECISIONS-M6):
 *  - D-M6-1/2/3: dispatch portfolio + random orders + runtime-built tables
 *  - lazy per-function const-pool decryption over the pinned chained keys
 *    (BYTECODE-M5 §6.1/6.2) — blobs skipped via ctLen, chain head cached,
 *    so only touched functions pay AEAD cost (§10.2 item 6)
 *  - integrity feeds derivation, never a detectable branch (§10.2 item 9):
 *    the container build hash + per-fetch `s` validity select between the
 *    real constKey and a decoy derivation — tamper → garbage constants
 *  - emitted source is Lua 5.1-syntax-safe (no goto, no //, no compound
 *    assignment), comment-free, name/shape/junk-randomized per build
 *
 * Pipeline integration (two-pass, non-circular):
 *   1. emit with { placeholderLength } + opcodeSeed + vmSeed → vmChecksums
 *   2. constKey = deriveConstKey(masterKey, vmChecksums)    (index.ts)
 *   3. pack(protos, { constKey, opcodeSeed })               (M5)
 *   4. emit with the real container (same seeds) — the code region
 *      (everything except the blob literal) is byte-identical to pass 1;
 *      tests/api.test.ts asserts it.
 */

import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { Op, OP_INFO, OPCODE_COUNT, opcodeMapFromSeed, inverseMap, sha256Raw } from '../../compiler/src/opcode';
import { Rng } from './rng';
import { handlerBody, type HandlerNs } from './handlers';
import { emitDispatch, emitLoop, type DispatchKind } from './dispatch';

// ---------------------------------------------------------------------------
// public options / result
// ---------------------------------------------------------------------------

export interface EmitOptions {
  /** LPVB container bytes, or a placeholder spec (pipeline pre-pass that
   * needs vmChecksums before constKey/pack). */
  readonly container: Uint8Array | { readonly placeholderLength: number };
  /** 32-byte opcode permutation seed (M5 pack input) — its inverse map is
   * baked into the runtime; the seed itself is never emitted. */
  readonly opcodeSeed: Uint8Array;
  /** 32-byte build seed — fully determines the emitted shape. */
  readonly vmSeed: Uint8Array;
  /** Dispatch strategy; 'auto' (default) picks from the portfolio. */
  readonly dispatch?: DispatchKind | 'auto';
  /** Runtime-built handler table (closure strategy only); 'auto' flips. */
  readonly runtimeBuilt?: boolean | 'auto';
  /** Emit instruction-count hooks (parity gate; fills entry.dbg). */
  readonly countHook?: boolean;
}

export interface EmitResult {
  readonly lua: string;
  readonly dispatch: DispatchKind;
  readonly runtimeBuilt: boolean;
  /** FNV-1a32 + DJB2 over the code region (the emitted source with the
   * container blob literal removed) — fed into deriveConstKey (§10.2 item 9). */
  readonly vmChecksums: { readonly fnv: number; readonly djb2: number };
  readonly blobLength: number;
  readonly placeholder: boolean;
}

// ---------------------------------------------------------------------------
// tiny hash pair (M13 stub family, D-M6-5) — TS mirror of
// runtime/crypto/fnv.lua; KATs in tests/vectors.test.ts.
// ---------------------------------------------------------------------------

export function fnv1a32ts(data: Uint8Array | string): number {
  const n = data.length;
  const at = (i: number): number => (typeof data === 'string' ? data.charCodeAt(i) : data[i]!);
  let h = 2166136261;
  for (let i = 0; i < n; i++) {
    h = (h ^ at(i)) >>> 0;
    h = Math.imul(h, 16777619) >>> 0;
  }
  return h >>> 0;
}

export function djb2ts(data: Uint8Array | string): number {
  const n = data.length;
  const at = (i: number): number => (typeof data === 'string' ? data.charCodeAt(i) : data[i]!);
  let h = 5381;
  for (let i = 0; i < n; i++) {
    h = (Math.imul(h, 33) + at(i)) >>> 0;
  }
  return h >>> 0;
}

// ---------------------------------------------------------------------------
// name pool
// ---------------------------------------------------------------------------

const LUA_RESERVED = new Set([
  'and', 'break', 'do', 'else', 'elseif', 'end', 'false', 'for', 'function',
  'goto', 'if', 'in', 'local', 'nil', 'not', 'or', 'repeat', 'return',
  'then', 'true', 'until', 'while', 'continue', 'self',
]);

/** Module-scope names randomized per build (3-7 chars). Loop/handler-local
 * names (I, pcb, fr, rec, t, v, ap, ...) are 1-2 chars or scope-isolated —
 * they can only ever SHADOW, never capture. */
const NAME_FIELDS = [
  'e', 'ENTRY', 'BL', 'BH', 'INV', 'SHP', 'HXT',
  'BITM', 'SHM', 'HMM', 'HKM', 'CHM', 'POM', 'AEM', 'FNM',
  'B', 'SH', 'HM', 'HK', 'CH', 'PO', 'AE', 'FH',
  'BAND', 'FLR', 'HUGE', 'TYP', 'GTM', 'MTI', 'PK', 'UNP', 'TON',
  'EMPTY', 'ERRM', 'VI', 'F64', 'LE32', 'DECODE',
  'PROTOS', 'POOFS', 'POOFL', 'AADS', 'CHAINK',
  'CONTS', 'LOADPOOL', 'CELLG', 'CELLS', 'CELLC', 'CLOSEUP',
  'REG', 'MKFN', 'CALLIT', 'RUN', 'UNHEX', 'CNT', 'OPC', 'DBG',
  'IDX', 'HDL', 'HDIS', 'FMTW', 'WSTR',
] as const;

type NameKey = typeof NAME_FIELDS[number];
type Names = Record<NameKey, string>;

function makeNames(rng: Rng): Names {
  const used = new Set<string>(LUA_RESERVED);
  const out = {} as Names;
  const gen = (): string => {
    for (;;) {
      let s = '';
      const len = 3 + rng.int(5);
      while (s.length < len) {
        const r = rng.int(52);
        s += s.length === 0
          ? String.fromCharCode(r < 26 ? 65 + r : 97 + (r - 26))
          : (rng.chance(0.6) ? String.fromCharCode(97 + rng.int(26)) : String.fromCharCode(48 + rng.int(10)));
      }
      if (!used.has(s)) {
        used.add(s);
        return s;
      }
    }
  };
  for (const f of NAME_FIELDS) out[f] = gen();
  return out;
}

// ---------------------------------------------------------------------------
// vendored crypto inlining (M3 loader/crypto — byte-identical vendor copies)
// ---------------------------------------------------------------------------

const CRYPTO_DIR = join(import.meta.dir, '..', 'runtime', 'crypto');

/** Inline a vendored `return function(...) ... end` module as
 * `local NAME = function(...) ... end`, stripping full-line comments. */
function inlineModule(file: string, name: string): string {
  const raw = readFileSync(join(CRYPTO_DIR, file), 'utf8');
  const lines = raw.split('\n').filter((l) => !/^\s*--/.test(l));
  let src = lines.join('\n').trim();
  if (!src.startsWith('return function')) throw new Error(`${file}: unexpected module shape`);
  src = src.slice('return'.length).replace(/\s+$/, '');
  return `local ${name} =${src}`;
}

// ---------------------------------------------------------------------------
// literal emitters
// ---------------------------------------------------------------------------

function decLit(v: number, rng: Rng): string {
  if (v >= 16 && rng.chance(0.4)) return `0x${v.toString(16)}`;
  return String(v);
}

/** \ddd-escaped byte string, split into quoted chunks of 96 escapes
 * (chunk count depends only on byte LENGTH — placeholder/real stability). */
function strLit(bytes: Uint8Array): string {
  const out: string[] = [];
  let line: string[] = [];
  for (let i = 0; i < bytes.length; i++) {
    line.push(`\\${String(bytes[i]!).padStart(3, '0')}`);
    if (line.length >= 96) {
      out.push(`"${line.join('')}"`);
      line = [];
    }
  }
  if (line.length || out.length === 0) out.push(`"${line.join('')}"`);
  return out.join(' ..\n');
}

/** hex long-string (half the size; decoded at load via UNHEX). */
function hexLit(bytes: Uint8Array): string {
  const out: string[] = [];
  let line: string[] = [];
  for (let i = 0; i < bytes.length; i++) {
    line.push(bytes[i]!.toString(16).padStart(2, '0'));
    if (line.length >= 96) {
      out.push(line.join(''));
      line = [];
    }
  }
  if (line.length || out.length === 0) out.push(line.join(''));
  return `[[${out.join('\n')}]]`;
}

// ---------------------------------------------------------------------------
// junk / opaque predicates (§10.2 item 7, v1 surface). Junk names carry a
// leading underscore — the name pool never generates one, so no capture.
// ---------------------------------------------------------------------------

function junk(rng: Rng): string {
  const out: string[] = [];
  const n = rng.int(4);
  for (let i = 0; i < n; i++) {
    const kind = rng.int(3);
    if (kind === 0) {
      out.push(`local _q${i}z = ${decLit(rng.int(65536), rng)}`);
    } else if (kind === 1) {
      // opaque predicate: baked v with v % m ~= r — always false, but the
      // residue relation must be computed, not read.
      const m = 5 + rng.int(8);
      const r = rng.int(m);
      const v = (r + 1 + rng.int(m - 1)) % m;
      out.push(`local _q${i}o = ${decLit(v, rng)}`);
      out.push(`if _q${i}o % ${m} == ${r} then local _q${i}w = ${decLit(rng.int(256), rng)} end`);
    } else {
      out.push(`local _q${i}s = ${decLit(rng.int(2) === 0 ? rng.int(65536) : -(1 + rng.int(65536)), rng)}`);
    }
  }
  return out.join('\n');
}

function padIn(text: string, ind: string): string {
  return text
    .split('\n')
    .map((l) => (l.length ? ind + l : l))
    .join('\n');
}

function concat(a: Uint8Array, b: Uint8Array): Uint8Array {
  const out = new Uint8Array(a.length + b.length);
  out.set(a);
  out.set(b, a.length);
  return out;
}

// ---------------------------------------------------------------------------
// the emitter
// ---------------------------------------------------------------------------

export function emitRuntime(options: EmitOptions): EmitResult {
  const placeholder = !ArrayBuffer.isView(options.container);
  const blobLen = placeholder
    ? (options.container as { placeholderLength: number }).placeholderLength
    : (options.container as Uint8Array).length;
  if (!Number.isInteger(blobLen) || blobLen < 42) throw new Error('bad container length');
  if (options.opcodeSeed.length !== 32) throw new Error('opcodeSeed must be 32 bytes');
  if (options.vmSeed.length !== 32) throw new Error('vmSeed must be 32 bytes');

  const rng = new Rng(options.vmSeed);
  const N = makeNames(rng);

  const dispatch: DispatchKind =
    options.dispatch && options.dispatch !== 'auto' ? options.dispatch : rng.pick(['chain', 'tree', 'closure'] as const);
  const runtimeBuilt: boolean =
    options.runtimeBuilt === true || options.runtimeBuilt === false
      ? options.runtimeBuilt
      : rng.chance(0.5);
  const countHook = options.countHook === true;
  const hexEmbed = rng.chance(0.5);

  // --- handler bodies: the single semantic source for all strategies ---
  // Loop/handler-local names are fixed (I, pcb, fr, rec) — see makeNames.
  const hns: HandlerNs = {
    I: 'I', pcb: 'pcb', fr: 'fr', rec: 'rec',
    CONTS: N.CONTS, CALLIT: N.CALLIT, MKFN: N.MKFN,
    CELLC: N.CELLC, CLOSEUP: N.CLOSEUP,
    CELLG: N.CELLG, CELLS: N.CELLS, PROTOS: N.PROTOS,
    BAND: N.BAND, FLR: N.FLR, HUGE: N.HUGE,
    TYP: N.TYP, GTM: N.GTM, ERRM: N.ERRM, PK: N.PK,
  };
  const bodies: string[] = [];
  for (let op = 0; op < OPCODE_COUNT; op++) bodies.push(handlerBody(op as Op, hns));

  const gns = {
    I: 'I', pcb: 'pcb', fr: 'fr', rec: 'rec', ERRM: N.ERRM,
    HDIS: N.HDIS, IDX: N.IDX, HDL: N.HDL,
    countHook: countHook
      ? `${N.CNT} = ${N.CNT} + 1 local cw = ${N.OPC}[I[1]] if cw == nil then ${N.OPC}[I[1]] = 1 else ${N.OPC}[I[1]] = cw + 1 end`
      : null,
  };

  const dispatchCore = emitDispatch(rng, dispatch, hns, gns, bodies, dispatch === 'closure' && runtimeBuilt);
  const loop = emitLoop(dispatch, gns, dispatchCore);

  // --- baked tables from the opcode seed (inverse map; BYTECODE-M5 §7) ---
  const inv = inverseMap(opcodeMapFromSeed(options.opcodeSeed));
  const invEntries: string[] = [];
  for (let emitted = 0; emitted < inv.length; emitted++) {
    const canon = inv[emitted]!;
    if (canon >= 0) invEntries.push(`[${emitted + 1}] = ${decLit(canon, rng)}`);
  }
  const shpEntries: string[] = [];
  const hxtEntries: string[] = [];
  for (let canon = 0; canon < OPCODE_COUNT; canon++) {
    const [, shape, hasAux] = OP_INFO[canon]!;
    shpEntries.push(`[${canon}] = ${shape === 'ABC' ? 0 : shape === 'AD' ? 1 : 2}`);
    if (hasAux) hxtEntries.push(`[${canon}] = true`);
  }

  // --- container bytes (real, or same-length dummy for the pre-pass) ---
  const realContainer = placeholder ? null : (options.container as Uint8Array);
  const blobBytes: Uint8Array = realContainer ?? new Uint8Array(blobLen);
  const bhBytes: Uint8Array = realContainer
    ? sha256Raw(concat(realContainer.subarray(0, 5), realContainer.subarray(37, realContainer.length - 4)))
    : new Uint8Array(32);
  const blobLiteral = hexEmbed ? `${N.UNHEX}(${hexLit(blobBytes)})` : strLit(blobBytes);

  // ---------------- assemble: HEAD | blob literal | TAIL ----------------
  const head: string[] = [];
  const tail: string[] = [];

  head.push(junk(rng));
  head.push(
    `local ${N.RUN}, ${N.CALLIT}, ${N.PROTOS}, ${N.POOFS}, ${N.POOFL}, ${N.AADS}, ${N.CHAINK}` +
    (countHook ? `, ${N.CNT}, ${N.OPC}, ${N.DBG}` : ''),
  );

  head.push(junk(rng));
  head.push(inlineModule('bit.lua', N.BITM));
  head.push(inlineModule('sha2.lua', N.SHM));
  head.push(inlineModule('hmac.lua', N.HMM));
  head.push(inlineModule('hkdf.lua', N.HKM));
  head.push(inlineModule('chacha20.lua', N.CHM));
  head.push(inlineModule('poly1305.lua', N.POM));
  head.push(inlineModule('aead.lua', N.AEM));
  head.push(inlineModule('fnv.lua', N.FNM));
  head.push(
    `local ${N.B} = ${N.BITM}()\n` +
    `local ${N.SH} = ${N.SHM}(${N.B})\n` +
    `local ${N.HM} = ${N.HMM}(${N.B}, ${N.SH})\n` +
    `local ${N.HK} = ${N.HKM}(${N.HM})\n` +
    `local ${N.CH} = ${N.CHM}(${N.B})\n` +
    `local ${N.PO} = ${N.POM}(${N.B})\n` +
    `local ${N.AE} = ${N.AEM}(${N.B}, ${N.CH}, ${N.PO})\n` +
    `local ${N.FH} = ${N.FNM}(${N.B})`,
  );

  head.push(junk(rng));
  head.push(
    `local ${N.BAND} = ${N.B}.band\n` +
    `local ${N.FLR} = math.floor\n` +
    `local ${N.HUGE} = math.huge\n` +
    `local ${N.TYP} = type\n` +
    `local ${N.GTM} = getmetatable\n` +
    `local ${N.MTI} = math.tointeger\n` +
    `local ${N.TON} = tonumber\n` +
    `local ${N.PK} = table.pack or function(...) return { n = select("#", ...), ... } end\n` +
    `local ${N.UNP} = table.unpack or unpack\n` +
    `local ${N.EMPTY} = { n = 0 }\n` +
    `local function ${N.ERRM}() error("load failed", 0) end`,
  );

  if (hexEmbed) {
    head.push(
      `local function ${N.UNHEX}(h)\n` +
      `\th = (h:gsub("\\n", ""))\n` +
      `\tlocal o = {}\n` +
      `\tlocal n = #h\n` +
      `\tlocal k = 0\n` +
      `\tfor i = 1, n, 2 do\n` +
      `\t\tk = k + 1\n` +
      `\t\to[k] = string.char(${N.TON}(h:sub(i, i + 1), 16) or 0)\n` +
      `\tend\n` +
      `\treturn table.concat(o)\n` +
      `end`,
    );
  }

  // %*-aware string.format (Luau interp-string lowering, RESEARCH-M5 #4 /
  // M5 interpreter luaFormat): bare %* consumes one arg via tostring and
  // splices the text; everything else passes through to the host format.
  // Exposed to guest code through the wrapped env below (D-M6-9).
  head.push(
    `local function ${N.FMTW}(fmt, ...)\n` +
    `\tif ${N.TYP}(fmt) ~= "string" then return string.format(fmt, ...) end\n` +
    `\tif fmt:find("%*", 1, true) == nil then return string.format(fmt, ...) end\n` +
    `\tlocal na = { n = select("#", ...), ... }\n` +
    `\tlocal out = {}\n` +
    `\tlocal a2 = {}\n` +
    `\tlocal n2 = 0\n` +
    `\tlocal ai = 1\n` +
    `\tlocal i = 1\n` +
    `\tlocal len = #fmt\n` +
    `\twhile i <= len do\n` +
    `\t\tlocal c = fmt:byte(i)\n` +
    `\t\tif c == 37 and i < len and fmt:byte(i + 1) == 42 then\n` +
    `\t\t\tout[#out + 1] = tostring(na[ai])\n` +
    `\t\t\tai = ai + 1\n` +
    `\t\t\ti = i + 2\n` +
    `\t\telseif c == 37 and i < len then\n` +
    `\t\t\tout[#out + 1] = fmt:sub(i, i + 1)\n` +
    `\t\t\ti = i + 2\n` +
    `\t\telse\n` +
    `\t\t\tout[#out + 1] = fmt:sub(i, i)\n` +
    `\t\t\ti = i + 1\n` +
    `\t\tend\n` +
    `\tend\n` +
    `\tfor k = ai, na.n do\n` +
    `\t\tn2 = n2 + 1\n` +
    `\t\ta2[n2] = na[k]\n` +
    `\tend\n` +
    `\treturn string.format(table.concat(out), ${N.UNP}(a2, 1, n2))\n` +
    `end\n` +
    `local ${N.WSTR} = setmetatable({ format = ${N.FMTW} }, { __index = string })`,
  );

  head.push(junk(rng));
  head.push(`local ${N.BH} =`);

  // ---- TAIL ---- (code region = head + tail; the container-dependent
  // literals (build hash, blob) live in the band between them and are
  // excluded from vmChecksums so the two-pass pipeline stays stable)
  tail.push(`local ${N.INV} = {${invEntries.join(', ')}}`);
  tail.push(`local ${N.SHP} = {${shpEntries.join(', ')}}`);
  tail.push(`local ${N.HXT} = {${hxtEntries.join(', ')}}`);
  tail.push(junk(rng));

  // varint reader (protobuf base-128)
  tail.push(
    `local function ${N.VI}(s, i)\n` +
    `\tlocal r = 0\n` +
    `\tlocal sh = 0\n` +
    `\twhile true do\n` +
    `\t\tlocal b = s:byte(i)\n` +
    `\t\tif b == nil then ${N.ERRM}() end\n` +
    `\t\ti = i + 1\n` +
    `\t\tr = r + (b % 128) * 2 ^ sh\n` +
    `\t\tif b < 128 then return r, i end\n` +
    `\t\tsh = sh + 7\n` +
    `\tend\n` +
    `end`,
  );

  // f64 decoder — exact for normals/subnormals/±inf; NaN payload lost;
  // integral floats integerized via math.tointeger when present (D-M6-8)
  tail.push(
    `local function ${N.F64}(s, i)\n` +
    `\tlocal b1, b2, b3, b4, b5, b6, b7, b8 = s:byte(i, i + 7)\n` +
    `\tlocal lo = b1 + b2 * 256 + b3 * 65536 + b4 * 16777216\n` +
    `\tlocal hi = b5 + b6 * 256 + b7 * 65536 + b8 * 16777216\n` +
    `\tlocal t = ${N.FLR}(hi / 1048576)\n` +
    `\tlocal e = t % 2048\n` +
    `\tlocal m = (hi % 1048576) * 4294967296 + lo\n` +
    `\tlocal v\n` +
    `\tif e == 2047 then\n` +
    `\t\tif m == 0 then\n` +
    `\t\t\tif t >= 2048 then v = -${N.HUGE} else v = ${N.HUGE} end\n` +
    `\t\telse\n` +
    `\t\t\tv = 0 / 0\n` +
    `\t\tend\n` +
    `\telseif e == 0 then\n` +
    `\t\tv = m * 2 ^ -1074\n` +
    `\telse\n` +
    `\t\tv = (4503599627370496 + m) * 2 ^ (e - 1075)\n` +
    `\tend\n` +
    `\tif t >= 2048 then v = -v end\n` +
    `\tif ${N.MTI} ~= nil then\n` +
    `\t\tlocal iv = ${N.MTI}(v)\n` +
    `\t\tif iv ~= nil then return iv end\n` +
    `\tend\n` +
    `\treturn v\n` +
    `end`,
  );

  tail.push(
    `local function ${N.LE32}(n)\n` +
    `\treturn string.char(${N.FLR}(n / 16777216) % 256, ${N.FLR}(n / 65536) % 256, ${N.FLR}(n / 256) % 256, n % 256)\n` +
    `end`,
  );
  tail.push(junk(rng));

  // container decode (BYTECODE-M5 §2-§6; trap slots refuse to load)
  tail.push(
    `local function ${N.DECODE}()\n` +
    `\tlocal s = ${N.BL}\n` +
    `\tif s:byte(1) ~= 76 or s:byte(2) ~= 80 or s:byte(3) ~= 86 or s:byte(4) ~= 66 then ${N.ERRM}() end\n` +
    `\tif s:byte(5) ~= 1 then ${N.ERRM}() end\n` +
    `\tlocal fcount, i = ${N.VI}(s, 38)\n` +
    `\tlocal protos = {}\n` +
    `\tlocal poofs = {}\n` +
    `\tlocal poofl = {}\n` +
    `\tfor f = 1, fcount do\n` +
    `\t\tlocal np, mr\n` +
    `\t\tnp, i = ${N.VI}(s, i)\n` +
    `\t\tmr, i = ${N.VI}(s, i)\n` +
    `\t\tlocal flags = s:byte(i)\n` +
    `\t\ti = i + 1\n` +
    `\t\tlocal ninst\n` +
    `\t\tninst, i = ${N.VI}(s, i)\n` +
    `\t\tlocal code = {}\n` +
    `\t\tfor k = 1, ninst do\n` +
    `\t\t\tlocal w1, w2, w3, w4 = s:byte(i, i + 3)\n` +
    `\t\t\tif w1 == nil or w2 == nil or w3 == nil or w4 == nil then ${N.ERRM}() end\n` +
    `\t\t\tlocal w = w1 + w2 * 256 + w3 * 65536 + w4 * 16777216\n` +
    `\t\t\ti = i + 4\n` +
    `\t\t\tlocal canon = ${N.INV}[w % 256 + 1]\n` +
    `\t\t\tif canon == nil then ${N.ERRM}() end\n` +
    `\t\t\tlocal sh = ${N.SHP}[canon]\n` +
    `\t\t\tlocal ins = { canon, ${N.FLR}(w / 256) % 256, 0, 0, 0, 0 }\n` +
    `\t\t\tif sh == 0 then\n` +
    `\t\t\t\tins[3] = ${N.FLR}(w / 65536) % 256\n` +
    `\t\t\t\tins[4] = ${N.FLR}(w / 16777216) % 256\n` +
    `\t\t\telseif sh == 1 then\n` +
    `\t\t\t\tlocal d = ${N.FLR}(w / 65536)\n` +
    `\t\t\t\tif d >= 32768 then d = d - 65536 end\n` +
    `\t\t\t\tins[5] = d\n` +
    `\t\t\telse\n` +
    `\t\t\t\tlocal d = ${N.FLR}(w / 256)\n` +
    `\t\t\t\tif d >= 8388608 then d = d - 16777216 end\n` +
    `\t\t\t\tins[5] = d\n` +
    `\t\t\tend\n` +
    `\t\t\tif ${N.HXT}[canon] then\n` +
    `\t\t\t\tlocal a1, a2, a3, a4 = s:byte(i, i + 3)\n` +
    `\t\t\t\tif a1 == nil or a2 == nil or a3 == nil or a4 == nil then ${N.ERRM}() end\n` +
    `\t\t\t\tins[6] = a1 + a2 * 256 + a3 * 65536 + a4 * 16777216\n` +
    `\t\t\t\ti = i + 4\n` +
    `\t\t\tend\n` +
    `\t\t\tcode[k] = ins\n` +
    `\t\tend\n` +
    `\t\tlocal nup\n` +
    `\t\tnup, i = ${N.VI}(s, i)\n` +
    `\t\tlocal upv = {}\n` +
    `\t\tfor k = 1, nup do\n` +
    `\t\t\t\tlocal kd = s:byte(i)\n` +
    `\t\t\t\ti = i + 1\n` +
    `\t\t\t\tlocal src\n` +
    `\t\t\t\tsrc, i = ${N.VI}(s, i)\n` +
    `\t\t\t\tupv[k] = { kd, src }\n` +
    `\t\tend\n` +
    `\t\tprotos[f] = { np = np, mr = mr, isv = flags % 2 == 1, code = code, upv = upv, f = f, ks = nil }\n` +
    `\tend\n` +
    `\tlocal fnsEnd = i - 1\n` +
    `\tfor f = 1, fcount do\n` +
    `\t\tlocal cl\n` +
    `\t\tcl, i = ${N.VI}(s, i)\n` +
    `\t\tpoofs[f] = i + 12\n` +
    `\t\tpoofl[f] = cl\n` +
    `\t\ti = i + 12 + cl + 16\n` +
    `\tend\n` +
    `\tlocal aads = s:sub(1, 5) .. s:sub(38, fnsEnd)\n` +
    `\treturn protos, poofs, poofl, aads\n` +
    `end`,
  );
  tail.push(junk(rng));

  // lazy const pools (chained keys, BYTECODE-M5 §6.1/6.2). Key cache handles
  // NON-MONOTONIC pool access: K_{n} derived keys are memoized (KS[i] =
  // K_{i-1}); walking resumes from the highest contiguous index, so any
  // load order pays each derivation at most once and always gets the right
  // chain position (a walk-forward-only head would use K_j for pool i<j).
  tail.push(
    `local function ${N.LOADPOOL}(P)\n` +
    (countHook ? `\tif ${N.DBG} ~= nil then ${N.DBG}.pools = (${N.DBG}.pools or 0) + 1 end\n` : '') +
    `\tlocal f = P.f\n` +
    `\tlocal key = ${N.CHAINK}[f]\n` +
    `\tif key == nil then\n` +
    `\t\tlocal i = ${N.CHAINK}.w\n` +
    `\t\twhile i < f do\n` +
    `\t\t\t${N.CHAINK}[i + 1] = ${N.HK}.hkdf_sha256(${N.CHAINK}[i], ${N.LE32}(i), "const-key", 32)\n` +
    `\t\t\ti = i + 1\n` +
    `\t\tend\n` +
    `\t\t${N.CHAINK}.w = f\n` +
    `\t\tkey = ${N.CHAINK}[f]\n` +
    `\tend\n` +
    `\tlocal off = ${N.POOFS}[f]\n` +
    `\tlocal cl = ${N.POOFL}[f]\n` +
    `\tlocal pt = ${N.AE}.open(key, ${N.BL}:sub(off - 12, off - 1), ${N.AADS}, ${N.BL}:sub(off, off + cl + 15))\n` +
    `\tif pt == nil then ${N.ERRM}() end\n` +
    `\tlocal n, j = ${N.VI}(pt, 1)\n` +
    `\tlocal cs = {}\n` +
    `\tfor k = 1, n do\n` +
    `\t\tlocal tg = pt:byte(j)\n` +
    `\t\tj = j + 1\n` +
    `\t\tif tg == 1 then\n` +
    `\t\t\tcs[k] = pt:byte(j) ~= 0\n` +
    `\t\t\tj = j + 1\n` +
    `\t\telseif tg == 2 then\n` +
    `\t\t\tcs[k] = ${N.F64}(pt, j)\n` +
    `\t\t\tj = j + 8\n` +
    `\t\telse\n` +
    `\t\t\tlocal ln\n` +
    `\t\t\tln, j = ${N.VI}(pt, j)\n` +
    `\t\t\tcs[k] = pt:sub(j, j + ln - 1)\n` +
    `\t\t\tj = j + ln\n` +
    `\t\tend\n` +
    `\tend\n` +
    `\tP.ks = cs\n` +
    `\treturn cs\n` +
    `end\n` +
    `local function ${N.CONTS}(P, idx)\n` +
    `\tlocal cs = P.ks\n` +
    `\tif cs == nil then cs = ${N.LOADPOOL}(P) end\n` +
    `\treturn cs[idx + 1]\n` +
    `end`,
  );
  tail.push(junk(rng));

  // upvalue cells {1, frame, reg} open / {0, value} closed
  tail.push(
    `local function ${N.CELLG}(c) if c[1] == 1 then return c[2].R[c[3] + 1] end return c[2] end\n` +
    `local function ${N.CELLS}(c, v) if c[1] == 1 then c[2].R[c[3] + 1] = v else c[2] = v end end\n` +
    `local function ${N.CELLC}(c) if c[1] == 1 then c[2] = c[2].R[c[3] + 1] c[1] = 0 end end\n` +
    `local function ${N.CLOSEUP}(fr, a)\n` +
    `\tlocal oc = fr.oc\n` +
    `\tlocal w = 0\n` +
    `\tfor i = 1, #oc do\n` +
    `\t\tlocal c = oc[i]\n` +
    `\t\tif c[3] < a then\n` +
    `\t\t\tw = w + 1\n` +
    `\t\t\toc[w] = c\n` +
    `\t\telse\n` +
    `\t\t\t${N.CELLC}(c)\n` +
    `\t\tend\n` +
    `\tend\n` +
    `\tfor i = #oc, w + 1, -1 do oc[i] = nil end\n` +
    `end`,
  );
  tail.push(junk(rng));

  // guest closures + weak registry + call trampoline
  tail.push(
    `local ${N.REG} = setmetatable({}, { __mode = "k" })\n` +
    `local function ${N.MKFN}(rec)\n` +
    `\tlocal f = function(...)\n` +
    `\t\tlocal r = ${N.RUN}(rec, ${N.PK}(...))\n` +
    `\t\treturn ${N.UNP}(r, 1, r.n)\n` +
    `\tend\n` +
    `\t${N.REG}[f] = rec\n` +
    `\treturn f\n` +
    `end\n` +
    `${N.CALLIT} = function(f, ap)\n` +
    `\tlocal rec = ${N.REG}[f]\n` +
    `\tif rec ~= nil then return ${N.RUN}(rec, ap) end\n` +
    `\treturn ${N.PK}(f(${N.UNP}(ap, 1, ap.n)))\n` +
    `end`,
  );
  tail.push(junk(rng));

  // closure strategy: the handler table is chunk-level (built once)
  if (dispatch === 'closure') {
    tail.push(dispatchCore);
    tail.push(junk(rng));
  }

  // the interpreter
  tail.push(
    `${N.RUN} = function(rec, ap)\n` +
    `\tlocal P = ${N.PROTOS}[rec.p]\n` +
    `\tlocal np = P.np\n` +
    `\tlocal R = {}\n` +
    `\tfor k = 1, np do R[k] = ap[k] end\n` +
    `\tlocal va = ${N.EMPTY}\n` +
    `\tif P.isv then\n` +
    `\t\tlocal m = ap.n - np\n` +
    `\t\tif m > 0 then\n` +
    `\t\t\tva = {}\n` +
    `\t\t\tfor k = 1, m do va[k] = ap[np + k] end\n` +
    `\t\t\tva.n = m\n` +
    `\t\tend\n` +
    `\tend\n` +
    `\tlocal fr = { P = P, R = R, top = np, va = va, oc = {}, env = rec.env }\n` +
    `\tlocal pcb = { 1 }\n` +
    `\tlocal code = P.code\n` +
    `${padIn(loop, '\t')}\n` +
    `end`,
  );
  tail.push(junk(rng));

  // entry (RUNTIME-M6.md contract: e.s, e.c, e.env, e.args, e.nargs, e.dbg)
  const dbgReset = countHook
    ? `\t${N.CNT} = 0\n\t${N.OPC} = {}\n\t${N.DBG} = e.dbg\n\tif ${N.TYP}(${N.DBG}) ~= "table" then ${N.DBG} = nil end\n`
    : '';
  const dbgFill = countHook
    ? `\tif ${N.DBG} ~= nil then ${N.DBG}.count = ${N.CNT} ${N.DBG}.ops = ${N.OPC} end\n`
    : '';
  tail.push(
    `local ${N.ENTRY} = function(e)\n` +
    `\tlocal renv = e.env\n` +
    `\tif renv == nil then renv = _G end\n` +
    // wrapped env (D-M6-9): reads fall through to the real env; guest
    // writes go THROUGH to it; only `string` is replaced by the %*-aware
    // table. env identity is preserved for everything except `string`.
    `\tlocal ENVV = setmetatable({ string = ${N.WSTR} }, { __index = renv, __newindex = function(_, k, v) rawset(renv, k, v) end })\n` +
    `\tlocal ck = e.c\n` +
    `\tlocal sv = e.s\n` +
    `\tlocal good = ${N.TYP}(ck) == "string" and #ck == 32\n` +
    `\tif good and sv ~= nil and (${N.TYP}(sv) ~= "string" or #sv > 64) then good = false end\n` +
    `\tlocal bh = ${N.SH}.sha256(${N.BL}:sub(1, 5) .. ${N.BL}:sub(38, #${N.BL} - 4))\n` +
    `\tif bh ~= ${N.BH} then good = false end\n` +
    `\tif not good then\n` +
    `\t\tck = ${N.HK}.hkdf_sha256(bh, bh:sub(1, 8), "const-key", 32)\n` +
    `\tend\n` +
    `\t${N.CHAINK} = { ${N.HK}.hkdf_sha256(ck, "", "const-key", 32), w = 1 }\n` +
    `${dbgReset}` +
    `\tlocal protos, poofs, poofl, aads = ${N.DECODE}()\n` +
    `\t${N.PROTOS} = protos\n` +
    `\t${N.POOFS} = poofs\n` +
    `\t${N.POOFL} = poofl\n` +
    `\t${N.AADS} = aads\n` +
    `\tlocal ap = {}\n` +
    `\tlocal aa = e.args\n` +
    `\tlocal an = 0\n` +
    `\tif aa ~= nil then\n` +
    `\t\tan = e.nargs\n` +
    `\t\tif an == nil then an = #aa end\n` +
    `\t\tfor k = 1, an do ap[k] = aa[k] end\n` +
    `\tend\n` +
    `\tap.n = an\n` +
    `\tlocal res = ${N.RUN}({ p = 1, u = {}, env = ENVV }, ap)\n` +
    `${dbgFill}` +
    `\treturn ${N.UNP}(res, 1, res.n)\n` +
    `end`,
  );
  tail.push(junk(rng));
  tail.push(`return ${N.ENTRY}`);

  const headText = head.join('\n\n');
  const tailText = tail.join('\n\n');
  const lua = headText + '\n' + strLit(bhBytes) + '\nlocal ' + N.BL + ' =\n' + blobLiteral + '\n' + tailText;
  const codeRegion = headText + '\n' + tailText;

  return {
    lua,
    dispatch,
    runtimeBuilt: dispatch === 'closure' && runtimeBuilt,
    vmChecksums: { fnv: fnv1a32ts(codeRegion), djb2: djb2ts(codeRegion) },
    blobLength: blobLen,
    placeholder,
  };
}
