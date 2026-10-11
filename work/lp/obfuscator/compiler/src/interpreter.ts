/**
 * M5 reference interpreter (differential-test executor, D-M5-16).
 *
 * Executes loaded containers (canonical decoded form) against a Lua-5.1 /
 * Luau-semantics environment: register frames with runtime `top`, open
 * upvalue cells closed by CLOSEUPVALS, metatables, multret propagation,
 * string.format incl. Luau's `%*`. This is the M5-side oracle for §10.3
 * differential testing (original = real Lua executing the fixture source)
 * and the future conformance reference for M6's generated runtimes.
 *
 * Not covered (see VERIFICATION-M5): coroutines, io/os/debug libraries,
 * string.pack, bit32, buffer, goto (not in Luau), real executor timing.
 */

import { Op, type Insn } from './opcode';
import type { LoadedContainer, LoadedProto } from './container';

// ---------------------------------------------------------------------------
// Values
// ---------------------------------------------------------------------------

export type LuaValue = null | boolean | number | string | LuaTable | LuaClosure | HostFunction;

export type HostFunction = (args: readonly LuaValue[]) => LuaValue[];

let objectCounter = 0;

export class LuaTable {
  readonly id = ++objectCounter;
  private readonly map = new Map<string | number | object, LuaValue>();
  metatable: LuaTable | null = null;

  private static key(k: LuaValue): string | number | object {
    if (k === null || k === undefined) throw new LuaError('table index is nil');
    if (typeof k === 'number') {
      // -0 normalizes to 0 ("table index is NaN" when NaN)
      if (Number.isNaN(k)) throw new LuaError('table index is NaN');
      if (k === 0) return 0;
      // integer keys: 1 and 1.0 are the same key (Lua semantics)
      if (Number.isInteger(k)) return k;
      return `f${k}`;
    }
    if (typeof k === 'string' || typeof k === 'boolean') return typeof k === 'boolean' ? (k ? 'b:true' : 'b:false') : 's:' + k;
    return k as object;
  }

  get(k: LuaValue): LuaValue {
    return this.map.get(LuaTable.key(k)) ?? null;
  }

  set(k: LuaValue, v: LuaValue): void {
    const key = LuaTable.key(k);
    if (v === null) this.map.delete(key);
    else this.map.set(key, v);
  }

  /** rawget without key normalization errors (for rawget). */
  rawGet(k: LuaValue): LuaValue {
    if (k === null || (typeof k === 'number' && Number.isNaN(k))) return null;
    return this.map.get(LuaTable.key(k)) ?? null;
  }

  /** Lua length: border b such that t[1..b] non-nil and t[b+1] nil. */
  length(): number {
    let n = 0;
    while (this.map.get(n + 1) !== undefined && this.map.get(n + 1) !== null) n++;
    return n;
  }

  /** Ordered key list for next()/pairs(): array part first, then hash. */
  nextIter(): LuaValue[] {
    const keys: LuaValue[] = [];
    let i = 1;
    while (this.map.has(i)) {
      keys.push(i);
      i++;
    }
    for (const k of this.map.keys()) {
      if (typeof k === 'number') continue;
      if (typeof k === 'string') {
        if (k.startsWith('s:')) keys.push(k.slice(2));
        else if (k === 'b:true') keys.push(true);
        else if (k === 'b:false') keys.push(false);
        else if (k.startsWith('f')) keys.push(parseFloat(k.slice(1)));
        else continue;
      } else {
        keys.push(k as LuaValue);
      }
    }
    return keys;
  }

  allPairs(): [LuaValue, LuaValue][] {
    const out: [LuaValue, LuaValue][] = [];
    for (const k of this.nextIter()) out.push([k, this.get(k)]);
    return out;
  }
}

/** Open-or-closed upvalue cell. */
class UpvalCell {
  frame: Frame | null = null; // open: bound to a live frame register
  reg = -1;
  value: LuaValue = null; // closed

  get(): LuaValue {
    return this.frame ? this.frame.regs[this.reg] : this.value;
  }

  set(v: LuaValue): void {
    if (this.frame) this.frame.regs[this.reg] = v;
    else this.value = v;
  }

  close(): void {
    if (this.frame) {
      this.value = this.frame.regs[this.reg];
      this.frame = null;
    }
  }
}

export class LuaClosure {
  constructor(
    readonly proto: LoadedProto,
    readonly upvals: readonly UpvalCell[],
    readonly env: LuaTable,
    /** All protos of the loaded container (flat-index child resolution). */
    readonly siblings: readonly LoadedProto[],
  ) {}
}

export class LuaError extends Error {
  constructor(readonly luaValue: LuaValue) {
    super(typeof luaValue === 'string' ? luaValue : luaToStringStatic(luaValue, null));
  }
}

type Interp = (fn: LuaClosure, args: readonly LuaValue[]) => LuaValue[];

/** Build a self-contained stdlib environment whose host functions route
 *  closure calls back through runFunction. */
export function makeInterpreterEnv(): LuaTable {
  const interp: Interp = (fn, args) => runFunction(fn, args, interp);
  return makeStandardEnv(interp);
}

// ---------------------------------------------------------------------------
// Environment (stdlib)
// ---------------------------------------------------------------------------

export function makeStandardEnv(interp: Interp): LuaTable {
  const env = new LuaTable();
  /** tostring with __tostring metamethod dispatch (closures included). */
  const tostrV = (v: LuaValue): string => {
    if (v instanceof LuaTable) {
      const mm = v.metatable?.get('__tostring');
      if (mm !== null && mm !== undefined && isCallable(mm)) {
        return tostrV(callValue(mm, [v], env, interp)[0] ?? null);
      }
    }
    return luaToStringStatic(v, env);
  };
  const define = (name: string, fn: HostFunction): void => {
    env.set(name, makeHost(name, fn));
  };
  const makeHost = (name: string, fn: HostFunction): HostFunction => {
    const f = fn as HostFunction;
    Object.defineProperty(f, 'name', { value: name, configurable: true });
    return f;
  };

  define('print', (args) => {
    console.log(args.map((a) => tostrV(a)).join('\t'));
    return [];
  });

  define('type', (args) => [typeName(args[0] ?? null)]);
  define('typeof', (args) => [typeName(args[0] ?? null)]); // Luau typeof ~ type for our subset
  define('tostring', (args) => [tostrV(args[0] ?? null)]);
  define('tonumber', (args) => {
    const v = args[0] ?? null;
    if (typeof v === 'number') return [v];
    if (typeof v === 'string') {
      const n = parseNumber(v);
      if (n !== null) {
        if (args.length > 1 && typeof args[1] === 'number') {
          return [tonumberBase(v, args[1])];
        }
        return [n];
      }
      return [null];
    }
    return [null];
  });

  define('rawget', (args) => {
    const t = checkTable(args[0] ?? null, 'rawget');
    return [t.rawGet(args[1] ?? null)];
  });
  define('rawset', (args) => {
    const t = checkTable(args[0] ?? null, 'rawset');
    t.set(args[1] ?? null, args[2] ?? null);
    return [t];
  });
  define('rawequal', (args) => [(args[0] ?? null) === (args[1] ?? null)]);
  define('rawlen', (args) => {
    const t = checkTable(args[0] ?? null, 'rawlen');
    return [t.length()];
  });

  define('getmetatable', (args) => {
    const v = args[0] ?? null;
    if (v instanceof LuaTable) {
      const mt = v.metatable;
      if (!mt) return [null];
      const mtField = mt.get('__metatable');
      if (mtField !== null && mtField !== undefined) return [mtField];
      return [mt];
    }
    return [null];
  });
  define('setmetatable', (args) => {
    const t = checkTable(args[0] ?? null, 'setmetatable');
    const mt = args[1] ?? null;
    if (mt !== null && !(mt instanceof LuaTable)) throw new LuaError('bad argument #2 to \'setmetatable\' (nil or table expected)');
    t.metatable = mt;
    return [t];
  });

  define('assert', (args) => {
    const v = args[0] ?? null;
    if (truthy(v)) return args.slice();
    const msg = args.length > 1 ? args[1] : 'assertion failed!';
    throw new LuaError(msg);
  });
  define('error', (args) => {
    throw new LuaError(args[0] ?? null);
  });
  define('pcall', (args) => {
    const f = args[0] ?? null;
    if (!isCallable(f)) return [false, `attempt to call a ${typeName(f)} value`];
    try {
      const res = callValue(f, args.slice(1), env, interp);
      return [true, ...res];
    } catch (e) {
      if (e instanceof LuaError) return [false, e.luaValue];
      throw e;
    }
  });
  define('select', (args) => {
    const n = args[0] ?? null;
    if (n === '#') return [args.length - 1];
    const i = n as number;
    if (i < 0) return args.slice(args.length + i);
    return args.slice(i);
  });
  define('unpack', (args) => tableUnpack(args, env));
  define('next', (args) => {
    const t = checkTable(args[0] ?? null, 'next');
    const k = args[1] ?? null;
    const pairs = t.allPairs();
    if (k === null) return pairs.length ? [pairs[0][0], pairs[0][1]] : [null];
    const idx = pairs.findIndex((p) => rawEqualKey(p[0], k));
    if (idx < 0) throw new LuaError("invalid argument to 'next'");
    if (idx + 1 < pairs.length) return [pairs[idx + 1][0], pairs[idx + 1][1]];
    return [null];
  });
  define('pairs', (args) => {
    const t = args[0] ?? null;
    if (t instanceof LuaTable) {
      const mt = t.metatable;
      const iter = mt?.get('__pairs');
      if (iter !== null && iter !== undefined && isCallable(iter)) {
        const r = callValue(iter, [t], env, interp);
        return r;
      }
    }
    const nextFn = env.get('next') as HostFunction;
    return [nextFn, t, null];
  });
  define('ipairs', (args) => {
    const t = args[0] ?? null;
    const inext = makeHost('inext', (a) => {
      const tb = checkTable(a[0] ?? null, 'inext');
      const i = ((a[1] ?? null) as number) + 1;
      const v = tb.get(i);
      if (v === null || v === undefined) return [null];
      return [i, v];
    });
    return [inext, t, 0];
  });

  // --- math ---
  const math = new LuaTable();
  const mdef = (n: string, f: (x: number) => number): void => math.set(n, makeHost(`math.${n}`, ([a]) => [f(toNumber(a ?? null, `math.${n}`))]));
  math.set('pi', Math.PI);
  math.set('huge', Infinity);
  mdef('floor', Math.floor);
  mdef('ceil', Math.ceil);
  mdef('abs', Math.abs);
  mdef('sqrt', Math.sqrt);
  mdef('sin', Math.sin);
  mdef('cos', Math.cos);
  mdef('tan', Math.tan);
  mdef('exp', Math.exp);
  math.set('fmod', makeHost('math.fmod', ([a, b]) => {
    const x = toNumber(a ?? null, 'math.fmod');
    const y = toNumber(b ?? null, 'math.fmod');
    if (y === 0 || Number.isNaN(x) || Number.isNaN(y) || !Number.isFinite(x) && y === 1) return [NaN];
    return [x % y];
  }));
  math.set('pow', makeHost('math.pow', ([a, b]) => [toNumber(a ?? null, 'math.pow') ** toNumber(b ?? null, 'math.pow')]));
  math.set('max', makeHost('math.max', (a) => [Math.max(...a.map((x) => toNumber(x, 'math.max')))]));
  math.set('min', makeHost('math.min', (a) => [Math.min(...a.map((x) => toNumber(x, 'math.min')))]));
  env.set('math', math);

  // --- string ---
  const string = new LuaTable();
  const sdef = (n: string, f: HostFunction): void => string.set(n, makeHost(`string.${n}`, f));
  sdef('format', (args) => [luaFormat(args, tostrV, env, interp)]);
  sdef('rep', (args) => {
    const s = tostrV(args[0] ?? null);
    const n = toNumber(args[1] ?? null, 'string.rep');
    const sep = args.length > 2 ? tostrV(args[2] ?? null) : '';
    if (n <= 0) return [''];
    return [Array(n).fill(s).join(sep)];
  });
  sdef('sub', (args) => {
    const s = tostrV(args[0] ?? null);
    const len = s.length;
    let i = Math.trunc(toNumber(args[1] ?? null, 'string.sub') || 1);
    let j = args.length > 2 ? Math.trunc(toNumber(args[2] ?? null, 'string.sub') || 0) : -1;
    if (i < 0) i = Math.max(len + i + 1, 1);
    else if (i === 0) i = 1;
    if (j < 0) j = len + j + 1;
    else if (j > len) j = len;
    if (i > j) return [''];
    return [s.slice(i - 1, j)];
  });
  sdef('len', (args) => [tostrV(args[0] ?? null).length]);
  sdef('upper', (args) => [tostrV(args[0] ?? null).toUpperCase()]);
  sdef('lower', (args) => [tostrV(args[0] ?? null).toLowerCase()]);
  sdef('byte', (args) => {
    const s = tostrV(args[0] ?? null);
    const i = args.length > 1 ? Math.trunc(toNumber(args[1] ?? null, 'string.byte')) : 1;
    const out: LuaValue[] = [];
    for (let k = i; k <= s.length; k++) out.push(s.charCodeAt(k - 1));
    return out;
  });
  sdef('char', (args) => [args.map((a) => String.fromCharCode(Math.trunc(toNumber(a ?? null, 'string.char')))).join('')]);
  env.set('string', string);
  // --- table ---
  const table = new LuaTable();
  const tdef = (n: string, f: HostFunction): void => table.set(n, makeHost(`table.${n}`, f));
  tdef('insert', (args) => {
    const t = checkTable(args[0] ?? null, 'table.insert');
    if (args.length >= 3) {
      const pos = Math.trunc(toNumber(args[1] ?? null, 'table.insert'));
      const v = args[2] ?? null;
      const n = t.length();
      if (pos < 1 || pos > n + 1) throw new LuaError("bad argument #2 to 'insert' (position out of bounds)");
      for (let i = n; i >= pos; i--) t.set(i + 1, t.get(i));
      t.set(pos, v);
    } else {
      const v = args[1] ?? null;
      const n = t.length();
      t.set(n + 1, v);
    }
    return [];
  });
  tdef('remove', (args) => {
    const t = checkTable(args[0] ?? null, 'table.remove');
    const n = t.length();
    const pos = args.length > 1 ? Math.trunc(toNumber(args[1] ?? null, 'table.remove')) : n;
    if (n === 0 && args.length <= 1) return [null];
    if (pos < 1 || pos > n + 1) throw new LuaError("bad argument #2 to 'remove' (position out of bounds)");
    const v = t.get(pos);
    for (let i = pos; i < n; i++) t.set(i, t.get(i + 1));
    t.set(n, null);
    return [v];
  });
  tdef('concat', (args) => {
    const t = checkTable(args[0] ?? null, 'table.concat');
    const sep = args.length > 1 ? tostrV(args[1] ?? null) : '';
    let i = args.length > 2 ? Math.trunc(toNumber(args[2] ?? null, 'table.concat')) : 1;
    const j = args.length > 3 ? Math.trunc(toNumber(args[3] ?? null, 'table.concat')) : t.length();
    const parts: string[] = [];
    for (; i <= j; i++) parts.push(tostrV(t.get(i) ?? null));
    return [parts.join(sep)];
  });
  table.set('unpack', makeHost('table.unpack', (args) => tableUnpack(args, env)));
  env.set('table', table);

  return env;
}

function tableUnpack(args: readonly LuaValue[], _env: LuaTable): LuaValue[] {
  const t = checkTable(args[0] ?? null, 'unpack');
  const i = args.length > 1 ? Math.trunc(toNumber(args[1] ?? null, 'unpack')) : 1;
  const j = args.length > 2 ? Math.trunc(toNumber(args[2] ?? null, 'unpack')) : t.length();
  const out: LuaValue[] = [];
  for (let k = i; k <= j; k++) out.push(t.get(k));
  return out;
}

// ---------------------------------------------------------------------------
// Value helpers
// ---------------------------------------------------------------------------

export function truthy(v: LuaValue): boolean {
  return !(v === null || v === undefined || v === false);
}

export function typeName(v: LuaValue): string {
  if (v === null || v === undefined) return 'nil';
  if (typeof v === 'boolean') return 'boolean';
  if (typeof v === 'number') return 'number';
  if (typeof v === 'string') return 'string';
  if (v instanceof LuaTable) return 'table';
  return 'function';
}

function isCallable(v: LuaValue): boolean {
  return v instanceof LuaClosure || typeof v === 'function' || (v instanceof LuaTable && !!v.metatable?.get('__call'));
}

function checkTable(v: LuaValue, who: string): LuaTable {
  if (!(v instanceof LuaTable)) throw new LuaError(`bad argument #1 to '${who}' (table expected, got ${typeName(v)})`);
  return v;
}

function toNumber(v: LuaValue, who: string): number {
  if (typeof v === 'number') return v;
  if (typeof v === 'string') {
    const n = parseNumber(v);
    if (n !== null) return n;
  }
  throw new LuaError(`bad argument #1 to '${who}' (number expected, got ${typeName(v)})`);
}

function parseNumber(s: string): number | null {
  const t = s.trim();
  if (t === '') return null;
  if (/^0[xX][0-9a-fA-F]+$/.test(t)) return parseInt(t, 16);
  if (/^-?\d+(\.\d*)?([eE][+-]?\d+)?$/.test(t) || /^-?\.\d+([eE][+-]?\d+)?$/.test(t)) {
    const n = parseFloat(t);
    if (!Number.isNaN(n)) return n;
  }
  return null;
}

function tonumberBase(s: string, base: number): number | null {
  const b = Math.trunc(base);
  if (b < 2 || b > 36) throw new LuaError("bad argument #2 to 'tonumber' (base out of range)");
  const t = s.trim().toLowerCase();
  const sign = t.startsWith('-') ? -1 : 1;
  const body = sign < 0 ? t.slice(1) : t;
  if (body === '') return null;
  let n = 0;
  for (const ch of body) {
    const d = parseInt(ch, 36);
    if (Number.isNaN(d) || d >= b) return null;
    n = n * b + d;
  }
  return sign * n;
}

/** C-style %.14g (Luau tostring number formatting). */
export function formatG14(n: number): string {
  if (Number.isNaN(n)) return 'nan';
  if (n === Infinity) return 'inf';
  if (n === -Infinity) return '-inf';
  if (n === 0) return Object.is(n, -0) ? '-0' : '0';
  if (Number.isInteger(n) && Math.abs(n) < 1e15) return String(n);
  // %g behavior: use %e if exponent < -4 or >= precision
  const prec = 14;
  const exp = Math.floor(Math.log10(Math.abs(n)));
  if (exp < -4 || exp >= prec) {
    return formatExp(n, prec - 1).replace(/(\.\d*?)0+e/, '$1e').replace(/\.e/, 'e');
  }
  const fixed = n.toPrecision(prec);
  // strip trailing zeros in the fractional part
  if (fixed.includes('.') && !fixed.includes('e')) {
    return fixed.replace(/(\.\d*?)0+$/, '$1').replace(/\.$/, '');
  }
  return fixed;
}

function formatExp(n: number, prec: number): string {
  let s = n.toExponential(prec);
  // JS: "1.5e+21" ; C: "1.5e+21" (two-digit exponent minimum in C is 2)
  const m = s.match(/^(-?\d(?:\.\d+)?)e([+-])(\d+)$/);
  if (m) {
    const ex = m[3].padStart(2, '0');
    s = `${m[1]}e${m[2]}${ex}`;
  }
  return s;
}

export function luaToStringStatic(v: LuaValue, env: LuaTable | null): string {
  if (v === null || v === undefined) return 'nil';
  if (typeof v === 'boolean') return v ? 'true' : 'false';
  if (typeof v === 'number') return formatG14(v);
  if (typeof v === 'string') return v;
  if (v instanceof LuaTable) {
    const mt = v.metatable;
    const mm = mt?.get('__tostring');
    if (mm && isCallable(mm)) {
      // Note: no interp available here; __tostring tables are not exercised
      // by fixtures without the interpreter path (callValue handles it via
      // the interpreter when used inside VM code).
      if (typeof mm === 'function') return (mm as HostFunction)([v])[0] as string;
    }
    return `table: 0x${(v.id * 8 + 0x55aa0000).toString(16).padStart(8, '0')}`;
  }
  const fn = v as { name?: string };
  return `function: builtin: ${fn.name ?? 'anonymous'}`;
}

function rawEqualKey(a: LuaValue, b: LuaValue): boolean {
  if (typeof a === 'number' && typeof b === 'number') return a === b;
  return a === b;
}

// ---------------------------------------------------------------------------
// string.format
// ---------------------------------------------------------------------------

function luaFormat(args: readonly LuaValue[], tostrV: (v: LuaValue) => string, env: LuaTable, interp: Interp): string {
  const fmt = tostrV(args[0] ?? null);
  let ai = 1;
  let out = '';
  let i = 0;
  while (i < fmt.length) {
    const ch = fmt[i];
    if (ch !== '%') {
      out += ch;
      i++;
      continue;
    }
    i++;
    if (i >= fmt.length) throw new LuaError("invalid conversion '%' to 'format'");
    if (fmt[i] === '%') {
      out += '%';
      i++;
      continue;
    }
    if (fmt[i] === '*') {
      // Luau %*: tostring-style conversion (RESEARCH-M5 #4).
      const v = args[ai++] ?? null;
      out += tostrV(v);
      i++;
      continue;
    }
    // flags / width / precision
    let spec = '';
    while (i < fmt.length && /[+\- #0-9.]/.test(fmt[i])) {
      spec += fmt[i];
      i++;
    }
    const conv = fmt[i];
    i++;
    const getArg = (): LuaValue => {
      if (ai >= args.length) throw new LuaError("bad argument #* to 'format' (no value)");
      return args[ai++] ?? null;
    };
    switch (conv) {
      case 'd': case 'i': {
        const v = getArg();
        let n: number;
        if (typeof v === 'string') {
          const p = parseNumber(v);
          if (p === null) throw new LuaError("bad argument #* to 'format' (number expected, got string)");
          n = p;
        } else if (typeof v === 'number') n = Math.trunc(v);
        else throw new LuaError(`bad argument #${ai} to 'format' (number expected, got ${typeName(v)})`);
        out += applyFlags(String(n), spec, false);
        break;
      }
      case 'u': {
        const n = Math.trunc(toNumber(getArg(), 'format'));
        out += applyFlags(String(Math.abs(n)), spec, false);
        break;
      }
      case 'f': case 'F': {
        const n = toNumber(getArg(), 'format');
        out += cPrintf(spec.includes('.') ? spec : spec + '.6', conv, n);
        break;
      }
      case 'e': case 'E': {
        const n = toNumber(getArg(), 'format');
        const p = spec.includes('.') ? spec : spec + '.6';
        out += cPrintf(p, conv, n);
        break;
      }
      case 'g': case 'G': {
        const n = toNumber(getArg(), 'format');
        out += formatG14(n);
        break;
      }
      case 'x': case 'X': {
        const n = Math.trunc(toNumber(getArg(), 'format')) >>> 0;
        const h = conv === 'x' ? n.toString(16) : n.toString(16).toUpperCase();
        out += applyFlags(h, spec, false);
        break;
      }
      case 'o': {
        const n = Math.trunc(toNumber(getArg(), 'format')) >>> 0;
        out += applyFlags(n.toString(8), spec, false);
        break;
      }
      case 'c': {
        const n = Math.trunc(toNumber(getArg(), 'format'));
        out += String.fromCharCode(n);
        break;
      }
      case 's': {
        const v = getArg();
        let s: string;
        if (typeof v === 'string') s = v;
        else s = tostrV(v);
        out += applyFlags(s, spec, true);
        break;
      }
      case 'q': {
        const v = getArg();
        if (typeof v === 'number') {
          out += formatG14(v);
          // numbers: %q appends no quotes
          break;
        }
        const s = typeof v === 'string' ? v : luaToStringStatic(v, env);
        out += '"' + s.replace(/\\/g, '\\\\').replace(/"/g, '\\"').replace(/\n/g, '\\n').replace(/\r/g, '\\r').replace(/\0/g, '\\0') + '"';
        break;
      }
      default:
        throw new LuaError(`invalid conversion '%${conv}' to 'format'`);
    }
    void interp;
  }
  return out;
}

function applyFlags(body: string, spec: string, isString: boolean): string {
  const m = spec.match(/^([+\- 0#]*)(\d+)?(?:\.(\d+))?$/);
  if (!m) return body;
  const [, flags, widthStr, precStr] = m;
  let s = body;
  if (precStr !== undefined && isString) s = s.slice(0, parseInt(precStr));
  const width = widthStr ? parseInt(widthStr) : 0;
  if (s.length < width) {
    const pad = flags?.includes('0') && !isString ? '0' : ' ';
    const neg = s.startsWith('-');
    const core = neg ? s.slice(1) : s;
    if (pad === '0' && neg) s = '-' + core.padStart(width - 1, '0');
    else if (flags?.includes('-')) s = s.padEnd(width, pad);
    else s = s.padStart(width, pad);
  }
  if (flags?.includes('+') && !s.startsWith('-') && !isString) s = '+' + s;
  else if (flags?.includes(' ') && !s.startsWith('-') && !isString) s = ' ' + s;
  return s;
}

function cPrintf(spec: string, conv: string, n: number): string {
  const m = spec.match(/^([+\- 0#]*)(\d+)?(?:\.(\d+))?$/);
  const prec = m && m[3] !== undefined ? parseInt(m[3]) : 6;
  const width = m && m[2] !== undefined ? parseInt(m[2]) : 0;
  let s: string;
  if (conv === 'f' || conv === 'F') s = fixedPrec(n, prec) + (prec > 0 ? '' : '');
  else s = formatExp(n, prec);
  if (conv === 'E') s = s.toUpperCase();
  if (s.length < width) s = s.padStart(width, ' ');
  return s;
}

function fixedPrec(n: number, prec: number): string {
  return prec === 0 ? Math.round(n).toString() : n.toFixed(prec);
}

// ---------------------------------------------------------------------------
// The VM
// ---------------------------------------------------------------------------

interface Frame {
  proto: LoadedProto;
  regs: LuaValue[];
  top: number; // one past the last open-window value
  varargs: LuaValue[];
  openCells: UpvalCell[];
  env: LuaTable;
}

export function runContainer(
  container: LoadedContainer,
  env: LuaTable,
  args: readonly LuaValue[] = [],
): LuaValue[] {
  const main = container.protos[0];
  if (!main) throw new Error('empty container');
  const closure = new LuaClosure(main, [], env, container.protos);
  return runFunction(closure, args);
}

function runFunction(fn: LuaClosure, args: readonly LuaValue[], interp?: Interp): LuaValue[] {
  const interpFn: Interp = interp ?? ((f, a) => runFunction(f, a));
  const { proto } = fn;
  const frame: Frame = {
    proto,
    regs: new Array<LuaValue>(proto.maxRegs + 8).fill(null),
    top: 0,
    varargs: proto.isVararg ? args.slice(proto.numParams) : [],
    openCells: [],
    env: fn.env,
  };
  // Bind parameters (missing -> nil; extra absorbed into varargs above).
  for (let i = 0; i < proto.numParams; i++) {
    frame.regs[i] = args[i] ?? null;
  }
  frame.top = proto.numParams;
  // Pre-decoded instructions: pc counts INSTRUCTIONS (jump offsets are
  // instruction-relative — the container format's unit; word-level walking
  // misaligns on aux-carrying instructions).
  const insns = proto.insns;
  let pc = 0;
  const consts = proto.consts;
  const constOf = (idx: number): LuaValue => {
    const c = consts[idx];
    if (!c) throw new Error(`constant ${idx} out of range`);
    switch (c.kind) {
      case 'bool': return c.b;
      case 'num': return c.n;
      case 'str': return c.s;
    }
  };
  let insn: Insn;

  for (;;) {
    insn = insns[pc]!;
    pc += 1;
    if (process.env.M5_TRACE) {
      const regsPreview = frame.regs.slice(0, Math.min(6, frame.regs.length)).map((v) => v === null ? 'nil' : typeof v === 'number' ? v : typeof v === 'string' ? JSON.stringify(v) : v instanceof LuaTable ? `T${v.id}` : typeof v === 'function' ? 'fn' : String(v)).join(',');
      console.error(`  pc=${pc - 1} op=${insn.op} a=${insn.a} b=${insn.b} c=${insn.c} d=${insn.d} aux=${insn.aux} regs=[${regsPreview}] top=${frame.top}`);
    }
    switch (insn.op) {
      case Op.NOP:
        break;
      case Op.LOADNIL:
        frame.regs[insn.a] = null;
        break;
      case Op.LOADBOOL:
        frame.regs[insn.a] = insn.b !== 0;
        break;
      case Op.LOADINT:
        frame.regs[insn.a] = insn.d;
        break;
      case Op.LOADK:
        frame.regs[insn.a] = constOf(insn.d);
        break;
      case Op.LOADKX:
        frame.regs[insn.a] = constOf(insn.aux);
        break;
      case Op.MOVE:
        frame.regs[insn.a] = frame.regs[insn.b];
        break;
      case Op.GETGLOBAL: {
        const name = constOf(insn.d);
        let v = frame.env.get(name);
        if (v === null || v === undefined) {
          v = getMetaField(frame.env, '__index') !== null ? indexTable(frame.env, name, frame.env, interpFn) : null;
        }
        frame.regs[insn.a] = v;
        break;
      }
      case Op.SETGLOBAL:
        setTable(frame.env, constOf(insn.d), frame.regs[insn.a], frame.env, interpFn);
        break;
      case Op.GETUPVAL:
        frame.regs[insn.a] = fn.upvals[insn.b]?.get() ?? null;
        break;
      case Op.SETUPVAL:
        fn.upvals[insn.b]?.set(frame.regs[insn.a]);
        break;
      case Op.CLOSEUPVALS: {
        for (const cell of frame.openCells) {
          if (cell.frame === frame && cell.reg >= insn.a) cell.close();
        }
        frame.openCells = frame.openCells.filter((c) => c.frame === frame && c.reg < insn.a);
        break;
      }
      case Op.GETTABLE: {
        const t = frame.regs[insn.b];
        const k = frame.regs[insn.c];
        frame.regs[insn.a] = indexAny(t, k, frame.env, interpFn);
        break;
      }
      case Op.GETTABLEKS: {
        const t = frame.regs[insn.b];
        const k = constOf(insn.aux);
        frame.regs[insn.a] = indexAny(t, k, frame.env, interpFn);
        break;
      }
      case Op.SETTABLE: {
        const t = frame.regs[insn.b];
        const k = frame.regs[insn.c];
        setAny(t, k, frame.regs[insn.a], frame.env, interpFn);
        break;
      }
      case Op.SETTABLEKS: {
        const t = frame.regs[insn.b];
        const k = constOf(insn.aux);
        setAny(t, k, frame.regs[insn.a], frame.env, interpFn);
        break;
      }
      case Op.NEWTABLE: {
        const t = new LuaTable();
        // B/C are hints; the table grows on demand.
        frame.regs[insn.a] = t;
        break;
      }
      case Op.SELF: {
        const t = frame.regs[insn.b];
        const k = frame.regs[insn.c];
        frame.regs[insn.a + 1] = t;
        frame.regs[insn.a] = indexAny(t, k, frame.env, interpFn);
        break;
      }
      case Op.SELFKS: {
        const t = frame.regs[insn.b];
        const k = constOf(insn.aux);
        frame.regs[insn.a + 1] = t;
        frame.regs[insn.a] = indexAny(t, k, frame.env, interpFn);
        break;
      }
      case Op.ADD: case Op.SUB: case Op.MUL: case Op.DIV: case Op.MOD: case Op.POW: case Op.IDIV:
      case Op.ADDK: case Op.SUBK: case Op.MULK: case Op.DIVK: case Op.MODK: case Op.POWK: case Op.IDIVK: {
        const binop = arithOpName(insn.op);
        const x = frame.regs[insn.b];
        const y = insn.op >= Op.ADDK && insn.op <= Op.IDIVK ? constOf(insn.c) : frame.regs[insn.c];
        frame.regs[insn.a] = arith(binop, x, y, frame.env, interpFn);
        break;
      }
      case Op.AND: {
        const b = frame.regs[insn.b];
        frame.regs[insn.a] = truthy(b) ? frame.regs[insn.c] : b;
        break;
      }
      case Op.OR: {
        const b = frame.regs[insn.b];
        frame.regs[insn.a] = truthy(b) ? b : frame.regs[insn.c];
        break;
      }
      case Op.CONCAT: {
        // Lua semantics: fold the operand range RIGHT-TO-LEFT; adjacent
        // string/number operands fold into one string; a __concat
        // metamethod (checked on the LEFT operand first, then the right)
        // receives [left, rightAcc] and its result REPLACES the
        // accumulator — it is not re-concatenated with later operands.
        let acc: LuaValue = frame.regs[insn.c];
        for (let r = insn.c - 1; r >= insn.b; r--) {
          const v = frame.regs[r];
          const vPrim = typeof v === 'string' || typeof v === 'number';
          const aPrim = typeof acc === 'string' || typeof acc === 'number';
          if (vPrim && aPrim) {
            acc = (typeof v === 'number' ? formatG14(v) : v) + (typeof acc === 'number' ? formatG14(acc) : acc);
          } else {
            const mm = metaOf(v, '__concat') ?? metaOf(acc, '__concat');
            if (mm) {
              acc = callValue(mm, [v, acc], frame.env, interpFn)[0] ?? null;
            } else {
              throw new LuaError(`attempt to concatenate a ${typeName(vPrim ? acc : v)} value`);
            }
          }
        }
        frame.regs[insn.a] = acc;
        break;
      }
      case Op.NOT:
        frame.regs[insn.a] = !truthy(frame.regs[insn.b]);
        break;
      case Op.MINUS:
        frame.regs[insn.a] = arith('unm', frame.regs[insn.b], null, frame.env, interpFn);
        break;
      case Op.LENGTH:
        frame.regs[insn.a] = lengthOp(frame.regs[insn.b], frame.env, interpFn);
        break;
      case Op.JUMP:
        pc += insn.d;
        break;
      case Op.JUMPIF:
        if (truthy(frame.regs[insn.a])) pc += insn.d;
        break;
      case Op.JUMPIFNOT:
        if (!truthy(frame.regs[insn.a])) pc += insn.d;
        break;
      case Op.JUMPIFEQ: {
        const eq = rawEq(frame.regs[insn.a], frame.regs[insn.aux & 0x7fffffff], frame.env, interpFn);
        const not = (insn.aux >>> 31) !== 0;
        if (not ? !eq : eq) pc += insn.d;
        break;
      }
      case Op.JUMPIFLT: {
        if (lessThan(frame.regs[insn.a], frame.regs[insn.aux], frame.env, interpFn)) pc += insn.d;
        break;
      }
      case Op.JUMPIFLE: {
        if (lessEq(frame.regs[insn.a], frame.regs[insn.aux], frame.env, interpFn)) pc += insn.d;
        break;
      }
      case Op.JUMPIFEQKNIL: {
        const eq = frame.regs[insn.a] === null;
        const not = (insn.aux >>> 31) !== 0;
        if (not ? !eq : eq) pc += insn.d;
        break;
      }
      case Op.JUMPIFEQKB: {
        const eq = frame.regs[insn.a] === ((insn.aux & 1) !== 0);
        const not = (insn.aux >>> 31) !== 0;
        if (not ? !eq : eq) pc += insn.d;
        break;
      }
      case Op.JUMPIFEQKN: case Op.JUMPIFEQKS: {
        const k = constOf(insn.aux & 0x7fffffff);
        const eq = rawEq(frame.regs[insn.a], k, frame.env, interpFn);
        const not = (insn.aux >>> 31) !== 0;
        if (not ? !eq : eq) pc += insn.d;
        break;
      }
      case Op.CALL: {
        const callee = frame.regs[insn.a];
        let callArgs: LuaValue[];
        if (insn.b === 0) {
          callArgs = frame.regs.slice(insn.a + 1, frame.top);
        } else {
          callArgs = frame.regs.slice(insn.a + 1, insn.a + insn.b);
        }
        const res = callValue(callee, callArgs, frame.env, interpFn);
        if (insn.c === 0) {
          for (let i = 0; i < res.length; i++) frame.regs[insn.a + i] = res[i] ?? null;
          frame.top = insn.a + res.length;
        } else {
          const n = insn.c - 1;
          for (let i = 0; i < n; i++) frame.regs[insn.a + i] = res[i] ?? null;
          frame.top = insn.a + n;
        }
        break;
      }
      case Op.RETURN: {
        const n = insn.b === 0 ? frame.top - insn.a : insn.b - 1;
        const out: LuaValue[] = [];
        for (let i = 0; i < n; i++) out.push(frame.regs[insn.a + i] ?? null);
        // Frame teardown: close all open cells bound to this frame.
        for (const cell of frame.openCells) if (cell.frame === frame) cell.close();
        return out;
      }
      case Op.GETVARARGS: {
        const n = insn.b === 0 ? frame.varargs.length : insn.b - 1;
        if (insn.b === 0) {
          for (let i = 0; i < frame.varargs.length; i++) frame.regs[insn.a + i] = frame.varargs[i];
          frame.top = insn.a + frame.varargs.length;
        } else {
          for (let i = 0; i < n; i++) frame.regs[insn.a + i] = frame.varargs[i] ?? null;
        }
        break;
      }
      case Op.NEWCLOSURE: {
        const childProto = fn.siblings[insn.d];
        if (!childProto) throw new Error(`NEWCLOSURE child ${insn.d} out of range`);
        const upvals: UpvalCell[] = [];
        for (const d of childProto.upvals) {
          if (d.kind === 'ref') {
            const cell = new UpvalCell();
            cell.frame = frame;
            cell.reg = d.reg;
            upvals.push(cell);
            frame.openCells.push(cell);
          } else if (d.kind === 'upval') {
            upvals.push(fn.upvals[d.idx]);
          } else {
            const cell = new UpvalCell();
            cell.value = frame.regs[d.reg];
            upvals.push(cell);
          }
        }
        frame.regs[insn.a] = new LuaClosure(childProto, upvals, frame.env, fn.siblings);
        break;
      }
      case Op.FORNPREP: {
        const limit = frame.regs[insn.a];
        const step = frame.regs[insn.a + 1];
        const index = frame.regs[insn.a + 2];
        const ln = forNumber(limit, "'for' limit must be a number");
        const st = forNumber(step, "'for' step must be a number");
        const ix = forNumber(index, "'for' initial value must be a number");
        frame.regs[insn.a] = ln;
        frame.regs[insn.a + 1] = st;
        frame.regs[insn.a + 2] = ix;
        frame.regs[insn.a + 3] = ix; // visible variable starts at initial value
        if (!forContinue(ix, ln, st)) pc += insn.d;
        break;
      }
      case Op.FORNLOOP: {
        const limit = frame.regs[insn.a] as number;
        const step = frame.regs[insn.a + 1] as number;
        const index = (frame.regs[insn.a + 2] as number) + step;
        frame.regs[insn.a + 2] = index;
        if (forContinue(index, limit, step)) {
          frame.regs[insn.a + 3] = index;
          pc += insn.d;
        }
        break;
      }
      case Op.FORGPREP: {
        // Generalized iteration (D-M5-7): function -> as-is; table -> next
        // (or __iter metamethod).
        let gen = frame.regs[insn.a];
        const state = frame.regs[insn.a + 1];
        if (gen instanceof LuaTable) {
          const iterMm = getMetaField(gen, '__iter');
          if (iterMm !== null) {
            const r = callValue(iterMm, [gen, state], frame.env, interpFn);
            gen = r[0] ?? null;
            frame.regs[insn.a + 1] = r[1] ?? null;
            frame.regs[insn.a + 2] = r[2] ?? null;
          } else {
            const nextFn = frame.env.get('next');
            frame.regs[insn.a] = nextFn;
            frame.regs[insn.a + 1] = gen;
            frame.regs[insn.a + 2] = null;
            gen = nextFn;
          }
        }
        void gen;
        pc += insn.d; // jump to FORGLOOP (first generator call)
        break;
      }
      case Op.FORGLOOP: {
        const gen = frame.regs[insn.a];
        const state = frame.regs[insn.a + 1];
        const index = frame.regs[insn.a + 2];
        const nvars = insn.aux;
        const res = callValue(gen, [state, index], frame.env, interpFn);
        const first = res[0] ?? null;
        if (first !== null) {
          frame.regs[insn.a + 2] = first;
          for (let i = 0; i < nvars; i++) {
            frame.regs[insn.a + 3 + i] = res[i] ?? null;
          }
          pc += insn.d;
        }
        break;
      }
      case Op.SETLIST: {
        const t = frame.regs[insn.a];
        if (!(t instanceof LuaTable)) throw new LuaError('attempt to index a non-table in SETLIST');
        let n = insn.b === 0 ? frame.top - insn.a - 1 : insn.b;
        for (let i = 1; i <= n; i++) {
          t.set(insn.aux + i, frame.regs[insn.a + i] ?? null);
        }
        break;
      }
      default:
        throw new Error(`unhandled opcode ${insn.op}`);
    }
  }
}

function forNumber(v: LuaValue, msg: string): number {
  if (typeof v === 'number') return v;
  if (typeof v === 'string') {
    const n = parseNumber(v);
    if (n !== null) return n;
  }
  throw new LuaError(msg);
}

function forContinue(index: number, limit: number, step: number): boolean {
  if (step > 0) return index <= limit;
  if (step < 0) return index >= limit;
  return true; // step 0: infinite loop guard -> treat as continuing (Lua errors)
}

// --- operator semantics -----------------------------------------------------

function arithOpName(op: number): string {
  switch (op) {
    case Op.ADD: case Op.ADDK: return 'add';
    case Op.SUB: case Op.SUBK: return 'sub';
    case Op.MUL: case Op.MULK: return 'mul';
    case Op.DIV: case Op.DIVK: return 'div';
    case Op.MOD: case Op.MODK: return 'mod';
    case Op.POW: case Op.POWK: return 'pow';
    case Op.IDIV: case Op.IDIVK: return 'idiv';
    default: return 'add';
  }
}

function arith(op: string, x: LuaValue, y: LuaValue | null, env: LuaTable, interp: Interp): LuaValue {
  const event = op === 'unm' ? '__unm' : `__${op}`;
  // string -> number coercion first (Lua 5.1 / Luau arithmetic)
  const xn = typeof x === 'string' ? parseNumber(x) : typeof x === 'number' ? x : null;
  if (op === 'unm') {
    if (xn !== null) return -xn;
    const mm = metaOf(x, event);
    if (mm) {
      const r = op === 'unm' ? callValue(mm, [x, x], env, interp) : callValue(mm, [x], env, interp);
      return r[0] ?? null;
    }
    throw new LuaError(`attempt to perform arithmetic (negate) on a ${typeName(x)} value`);
  }
  const yn = typeof y === 'string' ? parseNumber(y) : typeof y === 'number' ? y : null;
  if (xn !== null && yn !== null) {
    switch (op) {
      case 'add': return xn + yn;
      case 'sub': return xn - yn;
      case 'mul': return xn * yn;
      case 'div': return xn / yn;
      case 'mod': {
        if (yn === 0) return NaN;
        return xn % yn;
      }
      case 'pow': return Math.pow(xn, yn);
      case 'idiv': {
        if (yn === 0) return xn === 0 ? NaN : xn > 0 ? Infinity : -Infinity;
        return Math.floor(xn / yn);
      }
    }
  }
  const mm = metaOf(x, event) ?? metaOf(y ?? null, event);
  if (mm && (x instanceof LuaTable || y instanceof LuaTable)) {
    const r = callValue(mm, [x, y as LuaValue], env, interp);
    return r[0] ?? null;
  }
  throw new LuaError(`attempt to perform arithmetic on a ${typeName(xn === null ? x : y ?? x)} value`);
}

function metaOf(v: LuaValue, event: string): LuaValue {
  if (v instanceof LuaTable) {
    const f = v.metatable?.get(event);
    if (f !== null && f !== undefined) return f;
  }
  return null;
}

function getMetaField(t: LuaTable, event: string): LuaValue {
  return metaOf(t, event);
}

function indexAny(t: LuaValue, k: LuaValue, env: LuaTable, interp: Interp): LuaValue {
  if (t instanceof LuaTable) {
    return indexTable(t, k, env, interp);
  }
  if (typeof t === 'string') {
    // string library as metatable (string methods on values)
    const str = env.get('string');
    if (str instanceof LuaTable) return str.get(k);
    return null;
  }
  throw new LuaError(`attempt to index a ${typeName(t)} value${typeof k === 'string' ? ` (field '${k}')` : ''}`);
}

function indexTable(t: LuaTable, k: LuaValue, env: LuaTable, interp: Interp): LuaValue {
  const v = t.get(k);
  if (v !== null) return v;
  const h = t.metatable?.get('__index');
  if (h === null || h === undefined) return null;
  if (h instanceof LuaTable) return indexTable(h, k, env, interp);
  const r = callValue(h, [t, k], env, interp);
  return r[0] ?? null;
}

function setAny(t: LuaValue, k: LuaValue, v: LuaValue, env: LuaTable, interp: Interp): void {
  if (t instanceof LuaTable) {
    setTable(t, k, v, env, interp);
    return;
  }
  throw new LuaError(`attempt to index a ${typeName(t)} value`);
}

function setTable(t: LuaTable, k: LuaValue, v: LuaValue, env: LuaTable, interp: Interp): void {
  if (t.get(k) === null) {
    const h = t.metatable?.get('__newindex');
    if (h !== null && h !== undefined) {
      if (h instanceof LuaTable) {
        setTable(h, k, v, env, interp);
        return;
      }
      callValue(h, [t, k, v], env, interp);
      return;
    }
  }
  t.set(k, v);
}

function callValue(f: LuaValue, args: readonly LuaValue[], env: LuaTable, interp: Interp): LuaValue[] {
  if (f instanceof LuaClosure) return interp(f, args);
  if (typeof f === 'function') return (f as HostFunction)(args);
  if (f instanceof LuaTable) {
    const h = f.metatable?.get('__call');
    if (h && isCallable(h)) return callValue(h, [f, ...args], env, interp);
  }
  throw new LuaError(`attempt to call a ${typeName(f)} value`);
}

function rawEq(a: LuaValue, b: LuaValue, env: LuaTable, interp: Interp): boolean {
  if (a === b) return true;
  if (a instanceof LuaTable && b instanceof LuaTable) {
    const mm = a.metatable?.get('__eq') ?? b.metatable?.get('__eq');
    if (mm && isCallable(mm)) {
      return truthy(callValue(mm, [a, b], env, interp)[0] ?? null);
    }
  }
  return false;
}

function lessThan(a: LuaValue, b: LuaValue, env: LuaTable, interp: Interp): boolean {
  if (typeof a === 'number' && typeof b === 'number') return a < b;
  if (typeof a === 'string' && typeof b === 'string') return a < b;
  const mm = metaOf(a, '__lt') ?? metaOf(b, '__lt');
  if (mm) return truthy(callValue(mm, [a, b], env, interp)[0] ?? null);
  throw new LuaError(`attempt to compare ${typeName(a)} with ${typeName(b)}`);
}

function lessEq(a: LuaValue, b: LuaValue, env: LuaTable, interp: Interp): boolean {
  if (typeof a === 'number' && typeof b === 'number') return a <= b;
  if (typeof a === 'string' && typeof b === 'string') return a <= b;
  const mm = metaOf(a, '__le') ?? metaOf(b, '__le');
  if (mm) return truthy(callValue(mm, [a, b], env, interp)[0] ?? null);
  const ltmm = metaOf(a, '__lt') ?? metaOf(b, '__lt');
  if (ltmm && (a instanceof LuaTable || b instanceof LuaTable)) {
    // 5.1 fallback: a <= b  ==  not (b < a)
    return !truthy(callValue(ltmm, [b, a], env, interp)[0] ?? null);
  }
  throw new LuaError(`attempt to compare ${typeName(a)} with ${typeName(b)}`);
}

function lengthOp(v: LuaValue, env: LuaTable, interp: Interp): LuaValue {
  if (typeof v === 'string') return v.length;
  if (v instanceof LuaTable) {
    const mm = v.metatable?.get('__len');
    if (mm) return callValue(mm, [v], env, interp)[0] ?? null;
    return v.length();
  }
  throw new LuaError(`attempt to get length of a ${typeName(v)} value`);
}
