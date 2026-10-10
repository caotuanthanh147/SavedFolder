/**
 * M6 seeded RNG — deterministic per-build randomization source.
 *
 * SHA-256 DRBG in the same style as M5's opcodeMapFromSeed draws
 * (opcode.ts): blocks = SHA-256(seed || u32le(counter)), consumed as
 * needed. Reproducible builds: same vmSeed => same emitted runtime
 * (manifest carries the seed).
 */

import { sha256Raw } from '../../compiler/src/opcode';

export class Rng {
  private blocks: number[] = [];
  private draw = 0;
  private blockCount = 0;

  constructor(readonly seed: Uint8Array) {
    if (seed.length !== 32) throw new Error('vmSeed must be 32 bytes');
    this.refill(8);
  }

  private refill(n: number): void {
    for (let i = 0; i < n; i++) {
      const c = this.blockCount++;
      const ctr = new Uint8Array(4);
      ctr[0] = c & 0xff; ctr[1] = (c >>> 8) & 0xff; ctr[2] = (c >>> 16) & 0xff; ctr[3] = (c >>> 24) & 0xff;
      const block = sha256Raw(concat(this.seed, ctr));
      for (const b of block) this.blocks.push(b);
    }
  }

  /** Next byte. */
  byte(): number {
    while (this.draw >= this.blocks.length) this.refill(8);
    return this.blocks[this.draw++]!;
  }

  /** Uniform integer in [0, n). */
  int(n: number): number {
    // Modulo of a 32-bit draw (bias < 2^-9 for n <= 500; determinism is the
    // property that matters here, not uniformity).
    let v = 0;
    for (let k = 0; k < 4; k++) v = (v * 256 + this.byte()) >>> 0;
    return v % n;
  }

  pick<T>(arr: readonly T[]): T {
    return arr[this.int(arr.length)]!;
  }

  /** Fisher-Yates shuffle (returns a copy). */
  shuffled<T>(arr: readonly T[]): T[] {
    const out = [...arr];
    for (let i = out.length - 1; i > 0; i--) {
      const j = this.int(i + 1);
      const t = out[i]!;
      out[i] = out[j]!;
      out[j] = t;
    }
    return out;
  }

  /** True with probability p. */
  chance(p: number): boolean {
    return this.int(1_000_000) < Math.floor(p * 1_000_000);
  }
}

function concat(a: Uint8Array, b: Uint8Array): Uint8Array {
  const out = new Uint8Array(a.length + b.length);
  out.set(a);
  out.set(b, a.length);
  return out;
}

/** n random bytes (build inputs that must be unique, not reproducible). */
export function randomBytes(n: number): Uint8Array {
  const out = new Uint8Array(n);
  crypto.getRandomValues(out);
  return out;
}
