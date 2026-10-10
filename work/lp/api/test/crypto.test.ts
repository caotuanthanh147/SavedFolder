import { describe, expect, test } from "bun:test";
import { b64urlEncode, fromHex, toHex } from "../src/contracts";
import { utf8 } from "../src/crypto";
import { constantTimeEqual, generateSigningKeys, hkdfSha256, hmacSha256, hmacVerify, makeSigner, makeVerifier, randomId, sha256Hex } from "../src/crypto";

function hexOf(bytes: Uint8Array): string {
  return toHex(bytes);
}

describe("SHA-256", () => {
  test("known answer vectors", async () => {
    expect(await sha256Hex("abc")).toBe("ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad");
    expect(await sha256Hex("")).toBe("e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855");
  });
});

describe("HMAC-SHA-256 (RFC 4231)", () => {
  test("test case 1: 20-byte 0x0b key over 'Hi There'", async () => {
    const key = new Uint8Array(20).fill(0x0b);
    const mac = await hmacSha256(key, utf8("Hi There"));
    expect(hexOf(mac)).toBe("b0344c61d8db38535ca8afceaf0bf12b881dc200c9833da726e9376c2e32cff7");
  });

  test("test case 2: 'Jefe' key over 'what do ya want for nothing?'", async () => {
    const mac = await hmacSha256(utf8("Jefe"), utf8("what do ya want for nothing?"));
    expect(hexOf(mac)).toBe("5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843");
  });

  test("verify accepts the right mac and rejects tampering", async () => {
    const key = new Uint8Array(20).fill(0x0b);
    const data = utf8("Hi There");
    const mac = await hmacSha256(key, data);
    expect(await hmacVerify(key, data, mac)).toBe(true);
    const tampered = new Uint8Array(mac);
    tampered[0] ^= 1;
    expect(await hmacVerify(key, data, tampered)).toBe(false);
    expect(await hmacVerify(key, data, mac.slice(0, 31))).toBe(false);
  });
});

describe("HKDF-SHA-256 (RFC 5869 A.1)", () => {
  test("42-byte OKM for the basic test case", async () => {
    const ikm = new Uint8Array(22).fill(0x0b);
    const salt = fromHex("000102030405060708090a0b0c");
    const info = fromHex("f0f1f2f3f4f5f6f7f8f9");
    const okm = await hkdfSha256(ikm, salt, info, 42);
    expect(hexOf(okm)).toBe("3cb25f25faacd57a90434f64d0362f2a2d2d0a90cf1a5a4c5db02d56ecc4c5bf34007208d5b887185865");
  });
});

describe("Ed25519 signing", () => {
  test("sign then verify roundtrip, tampering rejected", async () => {
    const pair = await generateSigningKeys();
    const signer = await makeSigner(b64urlEncode(pair.privateKeyPkcs8));
    const verifier = await makeVerifier(b64urlEncode(pair.publicKeyRaw));
    const payload = utf8("code|message|data|ts");
    const sig = await signer.sign(payload);
    expect(await verifier.verify(payload, sig)).toBe(true);
    const tampered = utf8("code|message|data|ts!");
    expect(await verifier.verify(tampered, sig)).toBe(false);
    expect(await verifier.verify(payload, sig.slice(0, 63))).toBe(false);
  });

  test("signatures from another key are rejected", async () => {
    const pairA = await generateSigningKeys();
    const pairB = await generateSigningKeys();
    const signerA = await makeSigner(b64urlEncode(pairA.privateKeyPkcs8));
    const verifierB = await makeVerifier(b64urlEncode(pairB.publicKeyRaw));
    const sig = await signerA.sign(utf8("payload"));
    expect(await verifierB.verify(utf8("payload"), sig)).toBe(false);
  });
});

describe("helpers", () => {
  test("constantTimeEqual", () => {
    expect(constantTimeEqual(new Uint8Array([1, 2, 3]), new Uint8Array([1, 2, 3]))).toBe(true);
    expect(constantTimeEqual(new Uint8Array([1, 2, 3]), new Uint8Array([1, 2, 4]))).toBe(false);
    expect(constantTimeEqual(new Uint8Array([1, 2]), new Uint8Array([1, 2, 3]))).toBe(false);
    expect(constantTimeEqual(new Uint8Array(0), new Uint8Array(0))).toBe(true);
  });

  test("randomId is 32 lowercase hex chars and unique", () => {
    const seen = new Set<string>();
    for (let i = 0; i < 64; i++) {
      const id = randomId();
      expect(id).toMatch(/^[0-9a-f]{32}$/);
      seen.add(id);
    }
    expect(seen.size).toBe(64);
  });
});
