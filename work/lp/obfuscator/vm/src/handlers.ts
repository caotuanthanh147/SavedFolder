/**
 * M6 handler bodies — the ONE semantic source for all 58 canonical opcodes
 * (BYTECODE-M5.md §3). The same body text is inlined by every dispatch
 * strategy (chain branches, tree leaves, closure handlers), so semantic
 * identity across strategies holds by construction; the differential +
 * instruction-count parity gates (tests/differential.test.ts) verify it.
 *
 * Runtime identifier contract (must be in scope wherever a body is placed):
 *   I    — instruction array {op, a, b, c, d, aux} (1-based, op = I[1])
 *   pcb  — pc box {n}; pcb[1] is the next instruction index
 *   fr   — frame {P, R (regs, R[k+1] = reg k), top, va, oc, env}
 *   rec  — running closure record {p, u, env}
 * Module-scope helpers referenced: CONTS, CALLIT, MKFN, CELLC, CLOSEUP,
 *   CELLG, CELLS, PROTOS, BAND, FLR, HUGE, TYP, GTM, ERRM, PK.
 */

import { Op } from '../../compiler/src/opcode';

export interface HandlerNs {
  readonly I: string; readonly pcb: string; readonly fr: string; readonly rec: string;
  readonly CONTS: string; readonly CALLIT: string; readonly MKFN: string;
  readonly CELLC: string; readonly CLOSEUP: string;
  readonly CELLG: string; readonly CELLS: string; readonly PROTOS: string;
  readonly BAND: string; readonly FLR: string; readonly HUGE: string;
  readonly TYP: string; readonly GTM: string; readonly ERRM: string; readonly PK: string;
}

const S = (n: HandlerNs) => n;

/** Numeric-constant (K) operand for the K-arith family (C = const index). */
function kOp(n: HandlerNs): string {
  return `${S(n).CONTS}(${n.fr}.P, ${n.I}[4])`;
}

/** reg r as array index (reg k lives at R[k+1]). */
const r = (n: HandlerNs, k: number): string => `${n.fr}.R[${n.I}[${k}] + 1]`;

/** The IDIV semantics (mirrors M5 interpreter arith('idiv'): y==0 →
 * x==0?NaN : x>0?+inf : -inf; numbers via floor(x/y) — 5.1-syntax-safe,
 * no `//` operator dependency; __idiv manual dispatch). */
function idivBody(n: HandlerNs, yExpr: string): string {
  const N = S(n);
  return `local x = ${r(n, 3)}
local y = ${yExpr}
if ${N.TYP}(x) == "number" and ${N.TYP}(y) == "number" then
  if y ~= 0 then ${r(n, 2)} = ${N.FLR}(x / y)
  elseif x == 0 then ${r(n, 2)} = 0 / 0
  elseif x > 0 then ${r(n, 2)} = ${N.HUGE}
  else ${r(n, 2)} = -${N.HUGE} end
else
  local m = ${N.GTM}(x)
  if m ~= nil then m = m.__idiv end
  if m == nil then
    m = ${N.GTM}(y)
    if m ~= nil then m = m.__idiv end
  end
  if m == nil then ${N.ERRM}() end
  ${r(n, 2)} = ${N.CALLIT}(m, ${N.PK}(x, y))[1]
end`;
}

/** Jump-if-with-neg-bit family (AUX bit 31 = negate). `cmp` may reference
 * the local `aux` (declared by the emitted prologue). */
function eqJump(n: HandlerNs, cmp: string): string {
  const N = S(n);
  return `local aux = ${N.I}[6]
if (${cmp}) ~= (aux >= 2147483648) then ${N.pcb}[1] = ${N.pcb}[1] + ${N.I}[5] end`;
}

export function handlerBody(op: Op, n: HandlerNs): string {
  const N = S(n);
  const R = r(n, 2), B = r(n, 3), C = r(n, 4);
  switch (op) {
    case Op.NOP: return '';
    case Op.LOADNIL: return `${R} = nil`;
    case Op.LOADBOOL: return `${R} = ${N.I}[3] ~= 0`;
    case Op.LOADINT: return `${R} = ${N.I}[5]`;
    case Op.LOADK: return `${R} = ${N.CONTS}(${N.fr}.P, ${N.I}[5])`;
    case Op.LOADKX: return `${R} = ${N.CONTS}(${N.fr}.P, ${N.I}[6])`;
    case Op.MOVE: return `${R} = ${B}`;
    case Op.GETGLOBAL: return `${R} = ${N.fr}.env[${N.CONTS}(${N.fr}.P, ${N.I}[5])]`;
    case Op.SETGLOBAL: return `${N.fr}.env[${N.CONTS}(${N.fr}.P, ${N.I}[5])] = ${R}`;
    case Op.GETUPVAL: return `${R} = ${N.CELLG}(${N.rec}.u[${N.I}[3] + 1])`;
    case Op.SETUPVAL: return `${N.CELLS}(${N.rec}.u[${N.I}[3] + 1], ${R})`;
    case Op.CLOSEUPVALS: return `${N.CLOSEUP}(${N.fr}, ${N.I}[2])`;
    case Op.GETTABLE: return `${R} = ${B}[${C}]`;
    case Op.GETTABLEKS: return `${R} = ${B}[${N.CONTS}(${N.fr}.P, ${N.I}[6])]`;
    case Op.SETTABLE: return `${B}[${C}] = ${R}`;
    case Op.SETTABLEKS: return `${B}[${N.CONTS}(${N.fr}.P, ${N.I}[6])] = ${R}`;
    case Op.NEWTABLE: return `${R} = {}`;
    case Op.SELF: return `local t = ${B}
${N.fr}.R[${N.I}[2] + 2] = t
${R} = t[${C}]`;
    case Op.SELFKS: return `local t = ${B}
${N.fr}.R[${N.I}[2] + 2] = t
${R} = t[${N.CONTS}(${N.fr}.P, ${N.I}[6])]`;
    case Op.ADD: return `${R} = ${B} + ${C}`;
    case Op.SUB: return `${R} = ${B} - ${C}`;
    case Op.MUL: return `${R} = ${B} * ${C}`;
    case Op.DIV: return `${R} = ${B} / ${C}`;
    case Op.MOD: return `${R} = ${B} % ${C}`;
    case Op.POW: return `${R} = ${B} ^ ${C}`;
    case Op.IDIV: return idivBody(n, C);
    case Op.ADDK: return `${R} = ${B} + ${kOp(n)}`;
    case Op.SUBK: return `${R} = ${B} - ${kOp(n)}`;
    case Op.MULK: return `${R} = ${B} * ${kOp(n)}`;
    case Op.DIVK: return `${R} = ${B} / ${kOp(n)}`;
    case Op.MODK: return `${R} = ${B} % ${kOp(n)}`;
    case Op.POWK: return `${R} = ${B} ^ ${kOp(n)}`;
    case Op.IDIVK: return idivBody(n, kOp(n));
    case Op.AND: return `local v = ${B}
if v == nil or v == false then ${R} = v else ${R} = ${C} end`;
    case Op.OR: return `local v = ${B}
if v == nil or v == false then ${R} = ${C} else ${R} = v end`;
    case Op.CONCAT: return `local acc = ${C}
for k = ${N.I}[4] - 1, ${N.I}[3], -1 do acc = ${N.fr}.R[k + 1] .. acc end
${R} = acc`;
    case Op.NOT: return `${R} = not ${B}`;
    case Op.MINUS: return `${R} = -${B}`;
    case Op.LENGTH: return `${R} = #${B}`;
    case Op.JUMP: return `${N.pcb}[1] = ${N.pcb}[1] + ${N.I}[5]`;
    case Op.JUMPIF: return `if ${N.fr}.R[${N.I}[2] + 1] ~= nil and ${N.fr}.R[${N.I}[2] + 1] ~= false then ${N.pcb}[1] = ${N.pcb}[1] + ${N.I}[5] end`;
    case Op.JUMPIFNOT: return `if ${N.fr}.R[${N.I}[2] + 1] == nil or ${N.fr}.R[${N.I}[2] + 1] == false then ${N.pcb}[1] = ${N.pcb}[1] + ${N.I}[5] end`;
    case Op.JUMPIFEQ: return eqJump(n, `${N.fr}.R[${N.I}[2] + 1] == ${N.fr}.R[${N.BAND}(aux, 2147483647) + 1]`);
    case Op.JUMPIFLT: return `if ${N.fr}.R[${N.I}[2] + 1] < ${N.fr}.R[${N.I}[6] + 1] then ${N.pcb}[1] = ${N.pcb}[1] + ${N.I}[5] end`;
    case Op.JUMPIFLE: return `if ${N.fr}.R[${N.I}[2] + 1] <= ${N.fr}.R[${N.I}[6] + 1] then ${N.pcb}[1] = ${N.pcb}[1] + ${N.I}[5] end`;
    case Op.JUMPIFEQKNIL: return eqJump(n, `${N.fr}.R[${N.I}[2] + 1] == nil`);
    case Op.JUMPIFEQKB: return eqJump(n, `${N.fr}.R[${N.I}[2] + 1] == (${N.BAND}(${N.I}[6], 1) == 1)`);
    case Op.JUMPIFEQKN:
    case Op.JUMPIFEQKS:
      return eqJump(n, `${N.fr}.R[${N.I}[2] + 1] == ${N.CONTS}(${N.fr}.P, ${N.BAND}(${N.I}[6], 2147483647))`);
    case Op.CALL: return `local a = ${N.I}[2]
local b = ${N.I}[3]
local c = ${N.I}[4]
local n
if b == 0 then n = ${N.fr}.top - a - 1 else n = b - 1 end
local ap = {}
for k = 1, n do ap[k] = ${N.fr}.R[a + 1 + k] end
ap.n = n
local res = ${N.CALLIT}(${N.fr}.R[a + 1], ap)
local rn = res.n
if c == 0 then
  for k = 1, rn do ${N.fr}.R[a + k] = res[k] end
  ${N.fr}.top = a + rn
else
  local m = c - 1
  for k = 1, m do ${N.fr}.R[a + k] = res[k] end
  ${N.fr}.top = a + m
end`;
    case Op.RETURN: return `local a = ${N.I}[2]
local b = ${N.I}[3]
local n
if b == 0 then n = ${N.fr}.top - a else n = b - 1 end
local oc = ${N.fr}.oc
for k = 1, #oc do ${N.CELLC}(oc[k]) end
local p = {}
for k = 1, n do p[k] = ${N.fr}.R[a + k] end
p.n = n
return p`;
    case Op.GETVARARGS: return `local a = ${N.I}[2]
local b = ${N.I}[3]
local va = ${N.fr}.va
if b == 0 then
  for k = 1, va.n do ${N.fr}.R[a + k] = va[k] end
  ${N.fr}.top = a + va.n
else
  local n = b - 1
  for k = 1, n do ${N.fr}.R[a + k] = va[k] end
end`;
    case Op.NEWCLOSURE: return `local d = ${N.I}[5]
local cp = ${N.PROTOS}[d + 1]
local ds = cp.upv
local ups = {}
for k = 1, #ds do
  local e = ds[k]
  local kd = e[1]
  if kd == 1 then
    local cc = { 1, ${N.fr}, e[2] }
    ups[k] = cc
    local ocx = ${N.fr}.oc
    ocx[#ocx + 1] = cc
  elseif kd == 2 then
    ups[k] = ${N.rec}.u[e[2] + 1]
  else
    ups[k] = { 0, ${N.fr}.R[e[2] + 1] }
  end
end
${N.fr}.R[${N.I}[2] + 1] = ${N.MKFN}({ p = d + 1, u = ups, env = ${N.fr}.env })`;
    case Op.FORNPREP: return `local a = ${N.I}[2]
local lim = ${N.fr}.R[a + 1]
local st = ${N.fr}.R[a + 2]
local ix = ${N.fr}.R[a + 3]
${N.fr}.R[a + 4] = ix
local cont
if st > 0 then cont = ix <= lim
elseif st < 0 then cont = ix >= lim
else cont = true end
if not cont then ${N.pcb}[1] = ${N.pcb}[1] + ${N.I}[5] end`;
    case Op.FORNLOOP: return `local a = ${N.I}[2]
local st = ${N.fr}.R[a + 2]
local ix = ${N.fr}.R[a + 3] + st
${N.fr}.R[a + 3] = ix
local lim = ${N.fr}.R[a + 1]
local cont
if st > 0 then cont = ix <= lim
elseif st < 0 then cont = ix >= lim
else cont = true end
if cont then
  ${N.fr}.R[a + 4] = ix
  ${N.pcb}[1] = ${N.pcb}[1] + ${N.I}[5]
end`;
    case Op.FORGPREP: return `local a = ${N.I}[2]
local g = ${N.fr}.R[a + 1]
if ${N.TYP}(g) == "table" then
  local m = ${N.GTM}(g)
  local it = nil
  if m ~= nil then it = m.__iter end
  if it ~= nil then
    local ap = { g, ${N.fr}.R[a + 2] }
    ap.n = 2
    local r2 = ${N.CALLIT}(it, ap)
    ${N.fr}.R[a + 1] = r2[1]
    ${N.fr}.R[a + 2] = r2[2]
    ${N.fr}.R[a + 3] = r2[3]
  else
    ${N.fr}.R[a + 1] = ${N.fr}.env.next
    ${N.fr}.R[a + 2] = g
    ${N.fr}.R[a + 3] = nil
  end
end
${N.pcb}[1] = ${N.pcb}[1] + ${N.I}[5]`;
    case Op.FORGLOOP: return `local a = ${N.I}[2]
local ap = { ${N.fr}.R[a + 2], ${N.fr}.R[a + 3] }
ap.n = 2
local res = ${N.CALLIT}(${N.fr}.R[a + 1], ap)
local f1 = res[1]
if f1 ~= nil then
  ${N.fr}.R[a + 3] = f1
  local nv = ${N.I}[6]
  for k = 1, nv do ${N.fr}.R[a + 3 + k] = res[k] end
  ${N.pcb}[1] = ${N.pcb}[1] + ${N.I}[5]
end`;
    case Op.SETLIST: return `local a = ${N.I}[2]
local b = ${N.I}[3]
local aux = ${N.I}[6]
local t = ${N.fr}.R[a + 1]
local n
if b == 0 then n = ${N.fr}.top - a - 1 else n = b end
for k = 1, n do t[aux + k] = ${N.fr}.R[a + 1 + k] end`;
  }
  throw new Error(`unhandled opcode ${op}`);
}
