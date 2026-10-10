import { describe, expect, test } from "bun:test";
import { CODES, b64urlDecode, b64urlEncode, canonicalJson, fromHex, isKnownCode, toHex } from "../src/contracts";

describe("contract codes", () => {
  test("the SDK-visible code list matches doc.md §5.4 exactly", () => {
    expect([...CODES].sort()).toEqual([
      "BAD_REQUEST",
      "HWID_MISMATCH",
      "KEY_BLACKLISTED",
      "KEY_EXPIRED",
      "KEY_INVALID",
      "KEY_VALID",
      "RATE_LIMITED",
      "SCRIPT_NOT_ALLOWED",
      "SERVER_ERROR",
      "UPDATE_REQUIRED",
    ]);
  });

  test("unknown codes are denied", () => {
    expect(isKnownCode("KEY_VALID")).toBe(true);
    expect(isKnownCode("TOTALLY_NEW_CODE")).toBe(false);
    expect(isKnownCode("")).toBe(false);
  });
});

describe("canonical JSON", () => {
  test("keys are sorted recursively and separators are tight", () => {
    expect(canonicalJson({ b: 1, a: "x" })).toBe('{"a":"x","b":1}');
    expect(canonicalJson({ z: { d: 2, c: [3, 1, null] }, a: true })).toBe('{"a":true,"z":{"c":[3,1,null],"d":2}}');
  });

  test("array order is preserved", () => {
    expect(canonicalJson(["b", "a"])).toBe('["b","a"]');
  });

  test("non-integer numbers are rejected", () => {
    expect(() => canonicalJson({ x: 1.5 })).toThrow();
  });
});

describe("base64url", () => {
  test("roundtrip without padding", () => {
    for (const n of [0, 1, 2, 3, 15, 16, 31, 32]) {
      const bytes = new Uint8Array(n).map((_, i) => (i * 37 + 11) & 0xff);
      const enc = b64urlEncode(bytes);
      expect(enc.includes("=")).toBe(false);
      expect(b64urlDecode(enc)).toEqual(bytes);
    }
  });

  test("invalid characters are rejected", () => {
    expect(() => b64urlDecode("a+b/c")).toThrow();
    expect(() => b64urlDecode("")).not.toThrow();
  });
});

describe("hex", () => {
  test("roundtrip and validation", () => {
    const bytes = new Uint8Array([0, 1, 15, 16, 255, 254]);
    expect(toHex(bytes)).toBe("00010f10fffe");
    expect(fromHex("00010f10fffe")).toEqual(bytes);
    expect(() => fromHex("0g")).toThrow();
    expect(() => fromHex("abc")).toThrow();
  });
});
