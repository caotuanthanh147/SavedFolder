import { describe, expect, test } from "bun:test";
import { fnv1a32, djb2a32, mul32 } from "../src/hashes";

const enc = (s: string) => new TextEncoder().encode(s);

// Independent BigInt ground-truth formulations (second implementation for
// cross-checking, per doc.md §9/§22.1).
function fnvBig(data: Uint8Array): number {
  let h = 0x811c9dc5n;
  for (const b of data) h = ((h ^ BigInt(b)) * 16777619n) & 0xffffffffn;
  return Number(h);
}

function djbBig(data: Uint8Array): number {
  let h = 5381n;
  for (const b of data) h = (h * 33n + BigInt(b)) & 0xffffffffn;
  return Number(h);
}

// FNV-1a 32-bit known-answer vectors from draft-eastlake-fnv
// (teststring[] = { "", "a", "foobar", "Hello!\x01\xFF\xED" }).
// The 4th string contains non-ASCII bytes, so it must be built as raw bytes
// (TextEncoder would re-encode code points > 0x7F into UTF-8 sequences).
const HELLO_RAW = new Uint8Array([72, 101, 108, 108, 111, 33, 1, 0xff, 0xed]);

describe("FNV-1a 32-bit (draft-eastlake-fnv vectors)", () => {
  test('"" -> 0x811c9dc5', () => {
    expect(fnv1a32(enc(""))).toBe(0x811c9dc5);
  });
  test('"a" -> 0xe40c292c', () => {
    expect(fnv1a32(enc("a"))).toBe(0xe40c292c);
  });
  test('"foobar" -> 0xbf9cf968', () => {
    expect(fnv1a32(enc("foobar"))).toBe(0xbf9cf968);
  });
  test('"Hello!\\x01\\xFF\\xED" -> 0xfd9d3881', () => {
    expect(fnv1a32(HELLO_RAW)).toBe(0xfd9d3881);
  });
});

describe("mul32 exactness", () => {
  test("agrees with BigInt across the FNV prime and sweep", () => {
    expect(mul32(4294967295, 16777619)).toBe(Number((4294967295n * 16777619n) & 0xffffffffn));
    let a = 1;
    while (a <= 2 ** 31) {
      const b = 16777619;
      const big = Number((BigInt(a) * BigInt(b)) & 0xffffffffn);
      expect(mul32(a, b)).toBe(big);
      a = a * 3 + 5;
    }
  });
});

describe("DJB2", () => {
  test("known small values (hand-derivable, below 2^32)", () => {
    expect(djb2a32(enc(""))).toBe(5381);
    // "a": (5381*33)+97 = 177670
    expect(djb2a32(enc("a"))).toBe(177670);
  });
  test("matches the independent BigInt formulation on a sweep", () => {
    for (const s of ["hello", "foobar", "The quick brown fox", "x", "0123456789", "\u00ff\u00fe edge"]) {
      const data = enc(s);
      expect(djb2a32(data)).toBe(djbBig(data));
      expect(fnv1a32(data)).toBe(fnvBig(data));
    }
  });
  test("distinct inputs do not collide trivially", () => {
    expect(djb2a32(enc("foo"))).not.toBe(djb2a32(enc("bar")));
    expect(fnv1a32(enc("foo"))).not.toBe(fnv1a32(enc("bar")));
  });
});

describe("binary safety", () => {
  test("hashes arbitrary byte strings including NULs", () => {
    const withNul = new Uint8Array([0, 1, 0, 255, 0, 128, 0, 7]);
    expect(fnv1a32(withNul)).toBe(fnvBig(withNul));
    expect(djb2a32(withNul)).toBe(djbBig(withNul));
  });
});
