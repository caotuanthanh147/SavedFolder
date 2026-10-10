import { describe, expect, test } from "bun:test";
import { fromHex, toHex } from "../src/contracts";
import { aeadOpen, aeadSeal, chacha20Block, chacha20Xor, poly1305, poly1305KeyGen } from "../src/chacha";
import { randomBytes } from "../src/crypto";

const KEY_00_1F = fromHex("000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f");
const NONCE_2_3_2 = fromHex("000000090000004a00000000");
const KEY_80_9F = fromHex("808182838485868788898a8b8c8d8e8f909192939495969798999a9b9c9d9e9f");

describe("chacha20 RFC 8439 block vectors", () => {
  test("§2.3.2 ChaCha20 block function (counter = 1)", () => {
    const out = chacha20Block(KEY_00_1F, 1, NONCE_2_3_2);
    expect(toHex(out)).toBe("10f1e7e4d13b5915500fdd1fa32071c4c7d1f4c733c068030422aa9ac3d46c4ed2826446079faa0914c2d705d98b02a2b5129cd1de164eb9cbd083e8a2503c4e");
  });

  test("Appendix A.1 test vector 1 (key zero, counter 0)", () => {
    const out = chacha20Block(new Uint8Array(32), 0, new Uint8Array(12));
    expect(toHex(out)).toBe("76b8e0ada0f13d90405d6ae55386bd28bdd219b8a08ded1aa836efcc8b770dc7da41597c5157488d7724e03fb8d84a376a43b8f41518a11cc387b669b2ee6586");
  });

  test("Appendix A.1 test vector 2 (key zero, counter 1)", () => {
    const out = chacha20Block(new Uint8Array(32), 1, new Uint8Array(12));
    expect(toHex(out)).toBe("9f07e7be5551387a98ba977c732d080dcb0f29a048e3656912c6533e32ee7aed29b721769ce64e43d57133b074d839d531ed1f28510afb45ace10a1f4b794d6f");
  });

  test("Appendix A.1 test vector 3 (key 00..01, counter 1)", () => {
    const key = new Uint8Array(32);
    key[31] = 1;
    const out = chacha20Block(key, 1, new Uint8Array(12));
    expect(toHex(out)).toBe("3aeb5224ecf849929b9d828db1ced4dd832025e8018b8160b82284f3c949aa5a8eca00bbb4a73bdad192b5c42f73f2fd4e273644c8b36125a64addeb006c13a0".replace(/ /g, ""));
  });
});

describe("chacha20 cipher", () => {
  test("§2.4.2 sunscreen keystream applies (first 64 bytes of ciphertext)", () => {
    // §2.4.2: key 00..1f, nonce 00 00 00 00 00 00 00 4a 00 00 00 00, counter 1.
    // The RFC's example ciphertext is the plaintext XORed with the two
    // keystream blocks; the AEAD §2.8.2 vector exercises the same cipher with
    // a different key, so here we check the roundtrip plus the known first
    // keystream block from the §2.4.2 figure (block setup 2 = counter 2).
    const nonce = fromHex("000000000000004a00000000");
    const plaintext = new TextEncoder().encode(
      "Ladies and Gentlemen of the class of '99: If I could offer you only one tip for the future, sunscreen would be it.",
    );
    const ct = chacha20Xor(KEY_00_1F, 1, nonce, plaintext);
    expect(ct.length).toBe(plaintext.length);
    const back = chacha20Xor(KEY_00_1F, 1, nonce, ct);
    expect(new TextDecoder().decode(back)).toBe(new TextDecoder().decode(plaintext));
    // First 16 ciphertext bytes per RFC §2.4.2 figure (third state = first
    // block after ChaCha20 operation): keystream word d3 1a 8d 34 ... is for
    // the AEAD vector, not this one; the §2.4.2 ciphertext begins
    // 6e 2e 35 9a 25 68 f9 80 41 ba 07 28 dd 0d 69 81 (figure "ChaCha20
    // Encryption" — captured from the RFC text during fetch).
    expect(toHex(ct)).toBe("6e2e359a2568f98041ba0728dd0d6981e97e7aec1d4360c20a27afccfd9fae0bf91b65c5524733ab8f593dabcd62b3571639d624e65152ab8f530c359f0861d807ca0dbf500d6a6156a38e088a22b65e52bc514d16ccf806818ce91ab77937365af90bbf74a35be6b40b8eedf2785e42874d");
  });
});

describe("poly1305 RFC 8439 vectors", () => {
  test("§2.6.2 Poly1305 key generation", () => {
    const nonce = fromHex("000000000001020304050607");
    const key = poly1305KeyGen(KEY_80_9F, nonce);
    expect(toHex(key)).toBe("8ad5a08b905f81cc815040274ab29471a833b637e3fd0da508dbb8e2fdd1a646");
  });

  test("§2.5.2 Poly1305 tag", () => {
    const key = fromHex("85d6be7857556d337f4452fe42d506a80103808afb0db2fd4abff6af4149f51b");
    const msg = new TextEncoder().encode("Cryptographic Forum Research Group");
    const tag = poly1305(key, msg);
    expect(toHex(tag)).toBe("a8061dc1305136c6c22b8baf0c0127a9");
  });
});

describe("AEAD_CHACHA20_POLY1305 RFC 8439 §2.8.2", () => {
  const plaintext = new TextEncoder().encode(
    "Ladies and Gentlemen of the class of '99: If I could offer you only one tip for the future, sunscreen would be it.",
  );
  const aad = fromHex("50515253c0c1c2c3c4c5c6c7");
  const nonce = fromHex("070000004041424344454647");

  test("seal produces the RFC ciphertext and tag", () => {
    const sealed = aeadSeal(KEY_80_9F, nonce, plaintext, aad);
    expect(toHex(sealed.ciphertext)).toBe(
      "d31a8d34648e60db7b86afbc53ef7ec2a4aded51296e08fea9e2b5a736ee62d63dbea45e8ca9671282fafb69da92728b1a71de0a9e060b2905d6a5b67ecd3b3692ddbd7f2d778b8c9803aee328091b58fab324e4fad675945585808b4831d7bc3ff4def08e4b7a9de576d26586cec64b6116",
    );
    expect(toHex(sealed.tag)).toBe("1ae10b594f09e26a7e902ecbd0600691");
  });

  test("open verifies and decrypts the RFC vector", () => {
    const ct = fromHex(
      "d31a8d34648e60db7b86afbc53ef7ec2a4aded51296e08fea9e2b5a736ee62d63dbea45e8ca9671282fafb69da92728b1a71de0a9e060b2905d6a5b67ecd3b3692ddbd7f2d778b8c9803aee328091b58fab324e4fad675945585808b4831d7bc3ff4def08e4b7a9de576d26586cec64b6116",
    );
    const tag = fromHex("1ae10b594f09e26a7e902ecbd0600691");
    const opened = aeadOpen(KEY_80_9F, nonce, aad, ct, tag);
    expect(opened).not.toBeNull();
    expect(new TextDecoder().decode(opened!)).toBe(new TextDecoder().decode(plaintext));
  });

  test("tampered tag is rejected", () => {
    const ct = fromHex(
      "d31a8d34648e60db7b86afbc53ef7ec2a4aded51296e08fea9e2b5a736ee62d63dbea45e8ca9671282fafb69da92728b1a71de0a9e060b2905d6a5b67ecd3b3692ddbd7f2d778b8c9803aee328091b58fab324e4fad675945585808b4831d7bc3ff4def08e4b7a9de576d26586cec64b6116",
    );
    const tag = fromHex("1ae10b594f09e26a7e902ecbd0600691");
    tag[0] ^= 0x01;
    expect(aeadOpen(KEY_80_9F, nonce, aad, ct, tag)).toBeNull();
  });

  test("wrong aad is rejected", () => {
    const sealed = aeadSeal(KEY_80_9F, nonce, plaintext, aad);
    expect(aeadOpen(KEY_80_9F, nonce, fromHex("50515253c0c1c2c3c4c5c6c8"), sealed.ciphertext, sealed.tag)).toBeNull();
  });
});

describe("AEAD roundtrip properties", () => {
  test("random keys/nonces/messages roundtrip, empty aad and long messages", () => {
    for (let i = 0; i < 8; i++) {
      const key = randomBytes(32);
      const nonce = randomBytes(12);
      const lengths = [0, 1, 15, 16, 17, 63, 64, 65, 200, 1000];
      const len = lengths[i % lengths.length];
      const msg = randomBytes(len);
      const aad = randomBytes(i * 7);
      const sealed = aeadSeal(key, nonce, msg, aad);
      const opened = aeadOpen(key, nonce, aad, sealed.ciphertext, sealed.tag);
      expect(opened).not.toBeNull();
      expect(Buffer.from(opened!).equals(Buffer.from(msg))).toBe(true);
    }
  });
});
