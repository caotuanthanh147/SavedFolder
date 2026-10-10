import { describe, expect, test } from "bun:test";
import { fromHex } from "../src/contracts";
import { generateX25519KeyPair, isAllZero, x25519, x25519SharedSecret, X25519_BASEPOINT } from "../src/x25519";
import { randomBytes } from "../src/crypto";

describe("x25519 RFC 7748 vectors", () => {
  test("§5.2 test vector 1", () => {
    const scalar = fromHex("a546e36bf0527c9d3b16154b82465edd62144c0ac1fc5a18506a2244ba449ac4");
    const u = fromHex("e6db6867583030db3594c1a424b15f7c726624ec26b3353b10a903a6d0ab1c4c");
    const out = x25519(scalar, u);
    expect(Buffer.from(out).toString("hex")).toBe("c3da55379de9c6908e94ea4df28d084f32eccf03491c71f754b4075577a28552");
  });

  test("§5.2 test vector 2", () => {
    const scalar = fromHex("4b66e9d4d1b4673c5ad22691957d6af5c11b6421e0ea01d42ca4169e7918ba0d");
    const u = fromHex("e5210f12786811d3f4b7959d0538ae2c31dbe7106fc03c3efc4cd549c715a493");
    const out = x25519(scalar, u);
    expect(Buffer.from(out).toString("hex")).toBe("95cbde9476e8907d7aade45cb4b873f88b595a68799fa152e6f8f7647aac7957");
  });

  test("§6.1 Diffie-Hellman vector (both directions)", () => {
    const a = fromHex("77076d0a7318a57d3c16c17251b26645df4c2f87ebc0992ab177fba51db92c2a");
    const b = fromHex("5dab087e624a8a4b79e17f8b83800ee66f3bb1292618b6fd1c2f8b27ff88e0eb");
    const pubA = x25519(a, X25519_BASEPOINT);
    expect(Buffer.from(pubA).toString("hex")).toBe("8520f0098930a754748b7ddcb43ef75a0dbf3a0d26381af4eba4a98eaa9b4e6a");
    const pubB = x25519(b, X25519_BASEPOINT);
    expect(Buffer.from(pubB).toString("hex")).toBe("de9edb7d7b7dc1b4d35b61c2ece435373f8343c85b78674dadfc7e146f882b4f");
    const k1 = x25519(a, pubB);
    const k2 = x25519(b, pubA);
    expect(Buffer.from(k1).toString("hex")).toBe("4a5d9d5ba4ce2de1728e3bf480350f25e07e21c947d19e3376f09b3c1e161742");
    expect(Buffer.from(k1).toString("hex")).toBe(Buffer.from(k2).toString("hex"));
  });
});

describe("x25519 properties", () => {
  test("keypair generation: public = x25519(clamped priv, 9)", () => {
    for (let i = 0; i < 5; i++) {
      const pair = generateX25519KeyPair(randomBytes(32));
      expect(pair.privateKey.length).toBe(32);
      expect(pair.publicKey.length).toBe(32);
      const again = x25519(pair.privateKey, X25519_BASEPOINT);
      expect(Buffer.from(again).toString("hex")).toBe(Buffer.from(pair.publicKey).toString("hex"));
    }
  });

  test("agreement: shared(A, pubB) === shared(B, pubA) for random pairs", () => {
    for (let i = 0; i < 5; i++) {
      const alice = generateX25519KeyPair(randomBytes(32));
      const bob = generateX25519KeyPair(randomBytes(32));
      const k1 = x25519SharedSecret(alice.privateKey, bob.publicKey);
      const k2 = x25519SharedSecret(bob.privateKey, alice.publicKey);
      expect(Buffer.from(k1).toString("hex")).toBe(Buffer.from(k2).toString("hex"));
    }
  });

  test("small-order public key yields all-zero secret and is rejected", () => {
    const attacker = generateX25519KeyPair(randomBytes(32));
    const smallOrder = new Uint8Array(32); // u = 0
    expect(isAllZero(x25519(attacker.privateKey, smallOrder))).toBe(true);
    expect(() => x25519SharedSecret(attacker.privateKey, smallOrder)).toThrow();
  });

  test("reversed byte order inputs are rejected on length", () => {
    expect(() => x25519(new Uint8Array(31), new Uint8Array(32))).toThrow();
    expect(() => x25519(new Uint8Array(32), new Uint8Array(31))).toThrow();
  });
});
