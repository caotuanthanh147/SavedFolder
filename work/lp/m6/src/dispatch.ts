/**
 * M6 dispatch strategy generators (D-M6-1/2/3, doc §10.2 item 5).
 *
 * Three portfolio strategies over the canonical opcode id, plus the
 * runtime-built handler-table variant (D-M6-3) for the closure strategy:
 *   chain  — if/elseif chain, RANDOM branch order (D-M6-2: never
 *            frequency-sorted; a sorted chain is the most recognizable
 *            dispatch shape for the public Luraph lifters)
 *   tree   — balanced binary comparison tree, random split pivots
 *   closure— per-opcode handler table; optional runtime-built materialization
 *            through a per-build index permutation (the numeric re-indexing
 *            shape that still defeats the published v14.8/9 lifters)
 * All goto-free and Lua-5.1-syntax-safe (no `//`, no compound assignment).
 *
 * Every strategy consumes the SAME handler body strings (handlers.ts), so
 * strategy choice cannot change semantics — the differential suite asserts
 * this on real fixtures with several seeds per strategy.
 */

import { OPCODE_COUNT } from '../../compiler/src/opcode';
import { Rng } from './rng';
import type { HandlerNs } from './handlers';

export type DispatchKind = 'chain' | 'tree' | 'closure';

export interface DispatchGenNs {
  readonly I: string; readonly pcb: string; readonly fr: string; readonly rec: string;
  readonly ERRM: string; readonly HDIS: string; readonly IDX: string; readonly HDL: string;
  /** Statement inserted at the fetch step (instruction-count parity gate)
   * or null. May reference I. */
  readonly countHook: string | null;
}

function pad(body: string, ind: string): string {
  if (!body) return '';
  return body
    .split('\n')
    .map((l) => (l.length ? ind + l : l))
    .join('\n');
}

/**
 * Closure-strategy handler materialization.
 *
 * Handler definitions are named by DEFINITION position (hD1..hD58) in a
 * random definition order — the name carries no canonical-opcode meaning;
 * binding slots to semantics requires reading handler bodies.
 *
 * Direct variant: HDL[canon+1] = hD<k> assignments in shuffled order, then
 * HDIS = HDL (the loop dispatches HDIS[canonical id]).
 *
 * Runtime-built variant (D-M6-3): HDL[k] = hD<k] identity slots (numerically
 * meaningless), then a baked index table re-binds HDIS at RUNTIME:
 *   for j = 1, 58 do HDIS[IDX[j]] = HDL[j] end
 * with IDX[j] = canonical id (1-based) of the j-th definition — the table
 * the dispatch loop reads has no static slot↔definition binding at all.
 */
function emitHandlerTable(
  rng: Rng,
  ns: HandlerNs,
  gen: DispatchGenNs,
  bodies: readonly string[],
  runtimeBuilt: boolean,
): string {
  const ids = Array.from({ length: OPCODE_COUNT }, (_, i) => i);
  const defOrder = rng.shuffled(ids); // defOrder[k-1] = canon defined as hDk
  const defs: string[] = [];
  for (let k = 0; k < defOrder.length; k++) {
    const canon = defOrder[k]!;
    const hname = `hD${k + 1}`;
    const body = bodies[canon]!;
    defs.push(body
      ? `local ${hname} = function(${ns.fr}, ${ns.I}, ${ns.rec}, ${ns.pcb})\n${pad(body, '\t')}\nend`
      : `local ${hname} = function() end`);
  }
  const out: string[] = [`local ${gen.HDL} = {}`];
  if (!runtimeBuilt) {
    // Direct binding: canonical slot (1-based) ← definition name, shuffled
    // assignment order. canon c (0-based) is defined as hD<defPos>.
    const defPosOf = new Map<number, number>();
    defOrder.forEach((canon, idx) => defPosOf.set(canon, idx + 1));
    const assignOrder = rng.shuffled(ids);
    for (const canon of assignOrder) {
      out.push(`${gen.HDL}[${canon + 1}] = hD${defPosOf.get(canon)}`);
    }
    out.push(`local ${gen.HDIS} = ${gen.HDL}`);
  } else {
    // Identity (decoy) slots + runtime re-index through IDX.
    for (let k = 1; k <= defOrder.length; k++) {
      out.push(`${gen.HDL}[${k}] = hD${k}`);
    }
    // IDX[j] = canonical slot (canon+1) of the j-th definition.
    const idx = defOrder.map((canon) => canon + 1);
    out.push(`local ${gen.IDX} = {${idx.join(', ')}}`);
    out.push(`local ${gen.HDIS} = {}`);
    out.push(`for j = 1, ${OPCODE_COUNT} do ${gen.HDIS}[${gen.IDX}[j]] = ${gen.HDL}[j] end`);
  }
  return [...defs, ...out].join('\n');
}

export function emitDispatch(
  rng: Rng,
  kind: DispatchKind,
  ns: HandlerNs,
  gen: DispatchGenNs,
  bodies: readonly string[],
  runtimeBuilt: boolean,
): string {
  if (kind === 'chain') {
    const order = rng.shuffled(Array.from({ length: OPCODE_COUNT }, (_, i) => i));
    const parts: string[] = [`local o = ${gen.I}[1]`];
    for (let k = 0; k < order.length; k++) {
      const canon = order[k]!;
      const kw = k === 0 ? 'if' : 'elseif';
      const body = bodies[canon]!;
      parts.push(body ? `${kw} o == ${canon} then\n${pad(body, '\t')}` : `${kw} o == ${canon} then`);
    }
    parts.push(`else ${gen.ERRM}() end`);
    return parts.join('\n');
  }

  if (kind === 'tree') {
    // Balanced comparison tree with random pivots over the sorted id list.
    const emitNode = (lo: number, hi: number, depth: number): string => {
      if (lo === hi) {
        const body = bodies[lo]!;
        const ind = '\t'.repeat(depth);
        if (!body) return `${ind}if o == ${lo} then end`;
        return `${ind}if o == ${lo} then\n${pad(body, ind + '\t')}\n${ind}end`;
      }
      const mid = lo + 1 + rng.int(hi - lo);
      const ind = '\t'.repeat(depth);
      const left = emitNode(lo, mid - 1, depth + 1);
      const right = emitNode(mid, hi, depth + 1);
      return `${ind}if o < ${mid} then\n${left}\n${ind}else\n${right}\n${ind}end`;
    };
    return `local o = ${gen.I}[1]\n${emitNode(0, OPCODE_COUNT - 1, 0)}`;
  }

  return emitHandlerTable(rng, ns, gen, bodies, runtimeBuilt);
}

/** The interpreter loop around the dispatch. For chain/tree the dispatch
 * core is inlined after the fetch; the closure loop fetches through HDIS
 * (the handler table itself is emitted at chunk level by the caller). */
export function emitLoop(
  kind: DispatchKind,
  gen: DispatchGenNs,
  dispatchCore: string,
): string {
  const count = gen.countHook ? `\t${gen.countHook}\n` : '';
  if (kind === 'closure') {
    return `while true do
\tlocal ${gen.I} = code[${gen.pcb}[1]]
${count}\t${gen.pcb}[1] = ${gen.pcb}[1] + 1
\tlocal r = ${gen.HDIS}[${gen.I}[1] + 1](${gen.fr}, ${gen.I}, ${gen.rec}, ${gen.pcb})
\tif r ~= nil then return r end
end`;
  }
  return `while true do
\tlocal ${gen.I} = code[${gen.pcb}[1]]
${count}\t${gen.pcb}[1] = ${gen.pcb}[1] + 1
${pad(dispatchCore, '\t')}
end`;
}

export const ALL_DISPATCH: readonly DispatchKind[] = ['chain', 'tree', 'closure'];
