import { describe, expect, test } from "bun:test";
import { readFileSync, existsSync } from "node:fs";
import { join } from "node:path";
import { canonicalJson, b64urlDecode, b64urlEncode, fromHex, toHex } from "../src/contracts";
import { hmacSha256, hkdfSha256, sha256, utf8 } from "../src/crypto";
import { chacha20Block, chacha20Xor, poly1305, aeadSeal, aeadOpen } from "../src/chacha";

// Cross-implementation verification (doc.md §22.1: "second implementation"):
// these vectors were produced by glm1's M3 Lua implementation
// (contracts/test_vectors.json, Public 53525bb re-land) and by their
// loader/sdk/library.lua canonical_json. The TypeScript side must reproduce
// them byte-for-byte before M1↔M3 interop can be claimed.

const vectorsPath = join(import.meta.dir, "..", "..", "contracts", "test_vectors.json");
const have = existsSync(vectorsPath);
const V: Record<string, unknown> = have ? (JSON.parse(readFileSync(vectorsPath, "utf8")) as Record<string, unknown>) : {};

function hex(s: string): Uint8Array {
  return fromHex(s);
}

function expectEqualHex(actual: Uint8Array, expected: string, label: string): void {
  expect(toHex(actual), label).toBe(expected.toLowerCase());
}

describe.skipIf(!have)("M3 cross-vectors: SHA-256 / HMAC-SHA256 / HKDF (RFC 5869/4231)", () => {
  test("sha256 basics", async () => {
    expectEqualHex(await sha256(new Uint8Array(0)), V.sha256_empty as string, "empty");
    expectEqualHex(await sha256(utf8("abc")), V.sha256_abc as string, "abc");
    expectEqualHex(await sha256(utf8("a".repeat(1000))), V.sha256_1000a as string, "1000a");
    expectEqualHex(await sha256(utf8("a".repeat(200))), V.sha256_200a as string, "200a");
  });

  test("hmac-sha256 (RFC 4231 TC1 + TC6)", async () => {
    expectEqualHex(await hmacSha256(hex(V.hmac1_key as string), utf8("Hi There")), V.hmac1 as string, "tc1");
    expectEqualHex(await hmacSha256(hex(V.hmac_tc6_key as string), utf8(atobHex(V.hmac_tc6_data as string))), V.hmac_tc6_256 as string, "tc6");
  });

  test("hkdf-sha256 (RFC 5869 TC1-TC3)", async () => {
    for (const tc of ["hkdf_tc1", "hkdf_tc2", "hkdf_tc3"] as const) {
      const v = V[tc] as { ikm: string; salt: string; info: string; L: number; okm: string };
      const okm = await hkdfSha256(hex(v.ikm), hex(v.salt), hex(v.info), v.L);
      expectEqualHex(okm, v.okm, tc);
    }
  });
});

describe.skipIf(!have)("M3 cross-vectors: ChaCha20 / Poly1305 / AEAD (RFC 8439)", () => {
  test("chacha20 block + keystream + encrypt", () => {
    // first keystream block (counter 1) = first 64 bytes of chacha_ks
    const block1 = chacha20Block(hex(V.chacha_key as string), 1, hex(V.chacha_nonce as string));
    expectEqualHex(block1, (V.chacha_ks as string).slice(0, 128), "block1");
    // §2.4.2 keystream vs plaintext
    const ct = chacha20Xor(hex(V.chacha_key as string), 1, hex(V.chacha_nonce as string), utf8(V.chacha_pt as string));
    expectEqualHex(ct, V.chacha_ct as string, "ct");
  });

  test("poly1305 (RFC 8439 §2.5.2 + carry-propagation edge cases a31-a39)", async () => {
    const pairs: [string, string, string][] = [
      ["a31_key", "a31_text", "a31_tag"],
      ["a32_key", "a32_text", "a32_tag"],
      ["a33_key", "a33_text", "a33_tag"],
      ["a34_key", "a34_text", "a34_tag"],
      ["a35_key", "a35_data", "a35_tag"],
      ["a36_key", "a36_data", "a36_tag"],
      ["a37_key", "a37_data", "a37_tag"],
      ["a38_key", "a38_data", "a38_tag"],
      ["a39_key", "a39_data", "a39_tag"],
    ];
    for (const [k, t, tag] of pairs) {
      if (V[k] === undefined) continue;
      const textKey = V[t] !== undefined ? t : "a" + t.slice(1, 3) + "_text";
      void textKey;
      expectEqualHex(poly1305(hex(V[k] as string), hex(V[t] as string)), V[tag] as string, tag);
    }
  });

  test("aead seal/open (RFC 8439 §2.8.2)", () => {
    const key = hex(V.aead_key as string);
    // RFC §2.8.2 nonce: common prefix (07 00 00 00) || IV (40 41 … 47)
    const nonce = hex((V.aead_common as string) + (V.aead_iv as string));
    const aad = hex(V.aead_aad as string);
    const sealed = aeadSeal(key, nonce, hex(V.aead_pt as string), aad);
    expectEqualHex(sealed.ciphertext, V.aead_ct as string, "ct");
    expectEqualHex(sealed.tag, (V as Record<string, unknown>).aead_tag as string, "tag");
    const opened = aeadOpen(key, nonce, aad, sealed.ciphertext, sealed.tag);
    expect(opened).not.toBeNull();
    expectEqualHex(opened!, V.aead_pt as string, "roundtrip");
  });
});

describe("M3 canonical JSON alignment (contracts/canonical_json.md + sdk canonical_json)", () => {
  test("null-valued keys are dropped (Roblox JSONDecode semantics)", () => {
    expect(canonicalJson({ note: null, auth_expire: 0, total_executions: 3 })).toBe('{"auth_expire":0,"total_executions":3}');
    expect(canonicalJson({ discord_id: null, note: null })).toBe("{}");
  });

  test("null data signs as the empty object (SDK: envelope.data or {})", async () => {
    const { makeEnvelope } = await import("../src/contracts");
    const { signedResponse } = await import("../src/flow");
    const { generateSigningKeys, makeSigner, makeVerifier } = await import("../src/crypto");
    const pair = await generateSigningKeys();
    const signer = await makeSigner(b64urlEncode(pair.privateKeyPkcs8));
    const verifier = await makeVerifier(b64urlEncode(pair.publicKeyRaw));
    const res = await signedResponse(makeEnvelope("BAD_REQUEST", null), signer, 1791642000);
    const sig = res.headers.get("x-sig");
    const ts = res.headers.get("x-ts");
    const payload = utf8(`BAD_REQUEST|Malformed request.|{}|${ts}`);
    expect(await verifier.verify(payload, b64urlDecode(sig!))).toBe(true);
  });

  test("control bytes escape as \\u00xx only (no \\n shorthand)", () => {
    expect(canonicalJson("a\nb")).toBe('"a\\u000ab"');
    expect(canonicalJson("tab\t")).toBe('"tab\\u0009"');
    expect(canonicalJson("quote\"and\\slash")).toBe('"quote\\"and\\\\slash"');
  });

  test("keys sort by UTF-8 byte value", () => {
    expect(canonicalJson({ b: 1, a: 2 })).toBe('{"a":2,"b":1}');
    expect(canonicalJson({ "é": 1, z: 2 })).toBe('{"z":2,"é":1}');
  });

  test("numbers: integers only, ±2^53 bound like the SDK", () => {
    expect(canonicalJson(9007199254740992)).toBe("9007199254740992");
    expect(() => canonicalJson(9007199254740994)).toThrow();
    expect(() => canonicalJson(0.5)).toThrow();
  });

  test("booleans and nested objects", () => {
    expect(canonicalJson(true)).toBe("true");
    expect(canonicalJson({ outer: { y: null, x: "v" }, flag: false })).toBe('{"flag":false,"outer":{"x":"v"}}');
  });
});

describe.skipIf(!have)("M3 x-proof format (contracts/proof_spec.md)", () => {
  test("SDK formula: hex(HMAC(key, method|path|ts|nonce|hex(sha256(body)))) — no label, hex output", async () => {
    const { proofPayload } = await import("../src/flow");
    const key = utf8("proof-key-cross");
    const ts = "1791642000";
    const nonce = "AAAAAAAAAAAAAAAAAAAAAA";
    const body = utf8('{"key":"YURI-1"}');
    const bodyHashHex = toHex(await sha256(body));
    const payload = proofPayload("POST", "/check_key", ts, nonce, bodyHashHex);
    const expected = `POST|/check_key|${ts}|${nonce}|${bodyHashHex}`;
    expect(new TextDecoder().decode(payload)).toBe(expected);
    const mac = await hmacSha256(key, payload);
    expect(toHex(mac)).toMatch(/^[0-9a-f]{64}$/);
  });
});

function atobHex(h: string): string {
  const bytes = fromHex(h);
  return new TextDecoder().decode(bytes);
}
