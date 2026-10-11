/**
 * Cache-validation hash primitives shared by the stub generator (TS, build time)
 * and mirrored in the generated Lua stub (runtime). FNV-1a 32-bit vectors come
 * from draft-eastlake-fnv; DJB2 is the classic Bernstein hash. Both are
 * non-cryptographic by design: they filter corruption and casual tampering of
 * the on-disk init cache. The trust anchors are server-side (doc.md §3, §5.2).
 */

const MOD32 = 4294967296;

/** Exact multiplication mod 2^32 for IEEE-754 doubles (53-bit safe, 16-bit split). */
export function mul32(a: number, b: number): number {
  const al = a % 65536;
  const ah = (a - al) / 65536;
  const bl = b % 65536;
  const bh = (b - bl) / 65536;
  return (al * bl + ((al * bh + ah * bl) % 65536) * 65536) % MOD32;
}

/** FNV-1a 32-bit (draft-eastlake-fnv: prime 16777619, offset 2166136261). */
export function fnv1a32(data: Uint8Array): number {
  let h = 2166136261;
  for (let i = 0; i < data.length; i++) {
    h = mul32((h ^ data[i]) >>> 0, 16777619);
  }
  return h;
}

/** DJB2 (Bernstein): h = h*33 + byte, mod 2^32. */
export function djb2a32(data: Uint8Array): number {
  let h = 5381;
  for (let i = 0; i < data.length; i++) {
    h = (mul32(h, 33) + data[i]) % MOD32;
  }
  return h;
}
