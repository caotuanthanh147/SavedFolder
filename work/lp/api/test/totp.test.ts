import { describe, expect, test } from "bun:test";
import { base32Decode, base32Encode, hotp, otpauthUri, totp, utf8, verifyWindow } from "../src/totp";

// External oracle: RFC 6238 Appendix B, Table 1 (SHA1, 8 digits, T0=0, X=30,
// secret = ASCII "12345678901234567890"). Verified against the published
// table at tools.ietf.org/html/rfc6238#appendix-B.

const RFC_SECRET = utf8("12345678901234567890");

const RFC_VECTORS: { t: number; code: string }[] = [
  { t: 59, code: "94287082" },
  { t: 1111111109, code: "07081804" },
  { t: 1111111111, code: "14050471" },
  { t: 1234567890, code: "89005924" },
  { t: 2000000000, code: "69279037" },
  { t: 20000000000, code: "65353130" },
];

describe("TOTP against RFC 6238 Appendix B vectors", () => {
  for (const v of RFC_VECTORS) {
    test(`T=${v.t} → ${v.code}`, async () => {
      expect(await totp(RFC_SECRET, v.t, 30, 8)).toBe(v.code);
    });
  }
});

describe("HOTP (RFC 4226 §5.3 dynamic truncation shape)", () => {
  test("counter 0 and 1 differ; same counter repeats", async () => {
    const a = await hotp(RFC_SECRET, 0, 6);
    const b = await hotp(RFC_SECRET, 1, 6);
    const a2 = await hotp(RFC_SECRET, 0, 6);
    expect(a).not.toBe(b);
    expect(a).toBe(a2);
    expect(a).toMatch(/^\d{6}$/);
  });
});

describe("base32 (RFC 4648 alphabet, TOTP secret encoding)", () => {
  test("roundtrip of a 20-byte secret", () => {
    const secret = utf8("12345678901234567890");
    const b32 = base32Encode(secret);
    expect(b32).toBe("GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ");
    expect(Buffer.from(base32Decode(b32)).toString()).toBe("12345678901234567890");
  });

  test("invalid characters are rejected", () => {
    expect(() => base32Decode("1")).toThrow();
  });
});

describe("otpauth URI + verifyWindow", () => {
  test("URI carries issuer, account, secret, SHA1/6/30 params", () => {
    const uri = otpauthUri("GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ", "Yuri Hub", "admin@example");
    expect(uri).toBe("otpauth://totp/Yuri%20Hub:admin%40example?secret=GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ&issuer=Yuri%20Hub&algorithm=SHA1&digits=6&period=30");
  });

  test("verifyWindow is length-safe and exact", () => {
    expect(verifyWindow("123456", "123456")).toBe(true);
    expect(verifyWindow("123456", "123457")).toBe(false);
    expect(verifyWindow("12345", "123456")).toBe(false);
  });
});
