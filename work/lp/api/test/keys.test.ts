import { describe, expect, test } from "bun:test";
import { KEY_PATTERN, base32Decode, base32Encode, checksumChar, generateKey, hashHwid, hashKey, keyPassesChecksum, normalizeKey, projectHwidSalt } from "../src/keys";

describe("key generation", () => {
  test("format is PREFIX-XXXXX-XXXXX-XXXXX-XXXXX-XXXXXC", () => {
    for (let i = 0; i < 32; i++) {
      const { plaintext } = generateKey();
      expect(plaintext).toMatch(KEY_PATTERN);
      expect(plaintext.startsWith("YURI-")).toBe(true);
      const groups = plaintext.split("-");
      expect(groups.length).toBe(6);
      expect(groups[0]).toBe("YURI");
      expect(groups[1]).toHaveLength(5);
      expect(groups[5]).toHaveLength(6);
    }
  });

  test("generated keys are unique", () => {
    const seen = new Set<string>();
    for (let i = 0; i < 128; i++) seen.add(generateKey().plaintext);
    expect(seen.size).toBe(128);
  });

  test("checksum catches single-character corruption", () => {
    for (let i = 0; i < 16; i++) {
      const { plaintext } = generateKey();
      expect(keyPassesChecksum(plaintext)).toBe(true);
      const chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567";
      const idx = 4 + 3 * 5 + 2;
      const replacement = chars[(chars.indexOf(plaintext[idx]) + 7) % 32];
      const corrupted = plaintext.slice(0, idx) + replacement + plaintext.slice(idx + 1);
      expect(keyPassesChecksum(corrupted)).toBe(false);
    }
  });

  test("checksum is deterministic and derivable", () => {
    const { plaintext } = generateKey("YURI");
    const body = plaintext.split("-").slice(1).join("");
    expect(checksumChar(body.slice(0, 25), "YURI")).toBe(body[25]);
    expect(checksumChar(body.slice(0, 25), "YURI")).toBe(body[25]);
  });
});

describe("base32", () => {
  test("roundtrip", () => {
    for (const n of [1, 8, 16, 20]) {
      const bytes = new Uint8Array(n).map((_, i) => (i * 53 + 7) & 0xff);
      expect(base32Decode(base32Encode(bytes))).toEqual(bytes);
    }
  });
});

describe("hashing", () => {
  test("key hash is deterministic and pepper-sensitive", async () => {
    const k = generateKey().plaintext;
    expect(await hashKey(k, "pepper-a")).toBe(await hashKey(k, "pepper-a"));
    expect(await hashKey(k, "pepper-a")).not.toBe(await hashKey(k, "pepper-b"));
    expect(await hashKey(k, "pepper-a")).toMatch(/^[0-9a-f]{64}$/);
  });

  test("hwid salt differs per project and hashes stably", async () => {
    const saltA = await projectHwidSalt("pepper", "project-a");
    const saltB = await projectHwidSalt("pepper", "project-b");
    expect(saltA).toHaveLength(32);
    expect(saltB).not.toEqual(saltA);
    expect(await hashHwid("hwid-1", saltA)).toBe(await hashHwid("hwid-1", saltA));
    expect(await hashHwid("hwid-1", saltA)).not.toBe(await hashHwid("hwid-1", saltB));
    expect(await hashHwid("hwid-1", saltA)).not.toBe(await hashHwid("hwid-2", saltA));
  });
});

describe("normalization", () => {
  test("lowercase and whitespace are corrected before hashing", () => {
    const k = generateKey().plaintext;
    expect(normalizeKey("  " + k.toLowerCase() + "  ")).toBe(k);
  });
});
