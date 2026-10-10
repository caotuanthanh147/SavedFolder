/**
 * Structural AST equality for round-trip verification
 * (parse → print → parse ⇒ astEqual(a, b)).
 *
 * - `location` / `nameLocation` keys are ignored (re-printed text has
 *   different positions by construction).
 * - Local identity is positional: parallel DFS pairs binding sites in
 *   visit order (both trees come from the same parser, so the order is
 *   identical). A Local object seen again (LocalExpr.local, FunctionExpr
 *   .self/.args references) must map to its established pair.
 * - RepeatStat is special-cased to walk the BODY before the CONDITION:
 *   the condition references body locals (Lua scoping) but the object's
 *   key order puts `condition` first — a generic walk would see unmapped
 *   references.
 */

import type { Chunk, Local } from '../src/ast';

export function astEqual(a: Chunk, b: Chunk): boolean {
  const pairs = new Map<Local, Local>();
  return walk(a, b, pairs);
}

function walk(a: unknown, b: unknown, pairs: Map<Local, Local>): boolean {
  if (a === b) return true;
  if (a === null || b === null) return a === b;
  if (typeof a !== 'object' || typeof b !== 'object') return a === b;
  if (Array.isArray(a) || Array.isArray(b)) {
    if (!Array.isArray(a) || !Array.isArray(b) || a.length !== b.length) return false;
    return a.every((x, i) => walk(x, b[i], pairs));
  }
  const ao = a as Record<string, unknown>;
  const bo = b as Record<string, unknown>;
  // Local objects: identity pairing (bindings and references alike —
  // map.set is idempotent because parallel DFS reaches the same pair)
  if (ao.kind === 'Local') {
    if (bo.kind !== 'Local' || ao.name !== bo.name) return false;
    const paired = pairs.get(a as Local);
    if (paired) return paired === (b as Local);
    pairs.set(a as Local, b as Local);
    return true;
  }
  // Repeat: body locals must be paired before the condition references them
  if (ao.kind === 'Repeat') {
    if (bo.kind !== 'Repeat') return false;
    return (
      walk(ao.body, bo.body, pairs) &&
      walk(ao.condition, bo.condition, pairs)
    );
  }
  const keysA = Object.keys(ao).filter((k) => k !== 'location' && k !== 'nameLocation');
  const keysB = Object.keys(bo).filter((k) => k !== 'location' && k !== 'nameLocation');
  if (keysA.length !== keysB.length) return false;
  return keysA.every((k) =>
    Object.prototype.hasOwnProperty.call(bo, k) && walk(ao[k], bo[k], pairs),
  );
}
