-- run.lua — M3 test suite (lua5.4).
-- Usage: lua5.4 tests/run.lua   (from the repo root)
-- Covers: every crypto primitive against RFC vectors, the SDK flow
-- against a mock API, and the init/payload handshake end to end.

local ROOT = "."
if arg and arg[0] and arg[0]:match("tests") then
        local f = io.open("loader/crypto/sha2.lua", "r")
        if f then
                f:close()
        else
                ROOT = ".."
        end
end
package.path = ROOT .. "/?.lua;" .. ROOT .. "/tests/?.lua;" .. package.path

local json = require("tests.json_test")
local V = require("tests.vectors")
local vectors = V

local bit_chunk = assert(loadfile(ROOT .. "/loader/crypto/bit.lua"), "bit.lua")
local B = bit_chunk()()

local function load_module(path)
        local f = assert(loadfile(ROOT .. "/" .. path))
        return f()
end

local sha2 = load_module("loader/crypto/sha2.lua")(B)
local hmac = load_module("loader/crypto/hmac.lua")(B, sha2)
local encoding = load_module("loader/crypto/encoding.lua")()
local chacha20 = load_module("loader/crypto/chacha20.lua")(B)
local poly1305 = load_module("loader/crypto/poly1305.lua")(B)
local aead = load_module("loader/crypto/aead.lua")(B, chacha20, poly1305)
local hkdf = load_module("loader/crypto/hkdf.lua")(hmac)
local field = load_module("loader/crypto/field25519.lua")(B)
local x25519 = load_module("loader/crypto/x25519.lua")(B, field)
local ed25519 = load_module("loader/crypto/ed25519.lua")(B, field, sha2)

local Crypto = {
        sha2 = sha2,
        hmac = hmac,
        encoding = encoding,
        chacha20 = chacha20,
        poly1305 = poly1305,
        aead = aead,
        hkdf = hkdf,
        x25519 = x25519,
        ed25519 = ed25519,
}

local Signer = require("tests.ed25519_sign")(B, field, sha2, ed25519)
local MockServer = require("tests.mock_server")

local pass, fail = 0, 0
local failures = {}

local function check(name, got, want)
        if got == want then
                pass = pass + 1
        else
                fail = fail + 1
                failures[#failures + 1] = name
                print("FAIL " .. name)
                print("  got  " .. tostring(got))
                print("  want " .. tostring(want))
        end
end

local function dhx(h)
        return (h:gsub("(%x%x)", function(x)
                        return string.char(tonumber(x, 16))
                end))
end

local function hx(s)
        return (s:gsub(".", function(c)
                        return string.format("%02x", c:byte())
                end))
end

-- ---------- sha2 ----------
check("sha256 empty", hx(sha2.sha256("")), V.sha256_empty)
check("sha256 abc", hx(sha2.sha256("abc")), V.sha256_abc)
check("sha256 200a", hx(sha2.sha256(string.rep("a", 200))), V.sha256_200a)
check("sha256 1000a", hx(sha2.sha256(string.rep("a", 1000))), V.sha256_1000a)
check("sha512 empty", hx(sha2.sha512("")), V.sha512_empty)
check("sha512 abc", hx(sha2.sha512("abc")), V.sha512_abc)
check("sha512 200a", hx(sha2.sha512(string.rep("a", 200))), V.sha512_200a)

-- ---------- hmac (RFC 4231, 20-byte key TC1; TC2; 131-byte key TC6) ----------
check("hmac256 tc1", hx(hmac.hmac_sha256(dhx(V.hmac1_key), "Hi There")), V.hmac1)
check("hmac256 tc2", hx(hmac.hmac_sha256("Jefe", "what do ya want for nothing?")), V.hmac2)
check("hmac512 tc1", hx(hmac.hmac_sha512(dhx(V.hmac1_key), "Hi There")), V.hmac1_512)
check("hmac256 tc6", hx(hmac.hmac_sha256(dhx(V.hmac_tc6_key), dhx(V.hmac_tc6_data))), V.hmac_tc6_256)
check("hmac512 tc6", hx(hmac.hmac_sha512(dhx(V.hmac_tc6_key), dhx(V.hmac_tc6_data))), V.hmac_tc6_512)

-- ---------- encoding ----------
check("b64url empty", encoding.b64url_encode(""), "")
check("b64url f", encoding.b64url_encode("f"), "Zg")
check("b64url fo", encoding.b64url_encode("fo"), "Zm8")
check("b64url foo", encoding.b64url_encode("foo"), "Zm9v")
check("b64url foob", encoding.b64url_encode("foob"), "Zm9vYg")
check("b64url fooba", encoding.b64url_encode("fooba"), "Zm9vYmE")
check("b64url foobar", encoding.b64url_encode("foobar"), "Zm9vYmFy")
local roundtrip = dhx("00112233445566778899aabbccddeeff0011")
check("b64url roundtrip", encoding.b64url_decode(encoding.b64url_encode(roundtrip)), roundtrip)
check("b64url bad char", encoding.b64url_decode("a=b"), nil)
check("hex roundtrip", encoding.hex_decode(encoding.hex_encode(roundtrip)), roundtrip)
check("hex bad char", encoding.hex_decode("zz"), nil)

-- ---------- chacha20 (RFC 8439 §2.3.2, §2.4.2) ----------
local ckey = dhx(V.chacha_key)
check("chacha block 2.3.2", hx(chacha20.block(ckey, 1, dhx(V.chacha232_nonce))), hx(dhx(V.chacha232_state)))
check("chacha keystream 2.4.2", hx(chacha20.xor_stream(ckey, 1, dhx(V.chacha_nonce), string.rep("\0", 114))), V.chacha_ks)
check("chacha ct 2.4.2", hx(chacha20.xor_stream(ckey, 1, dhx(V.chacha_nonce), V.chacha_pt)), V.chacha_ct)

-- ---------- poly1305 (RFC 8439 §2.5.2 + A.3 #1-#10) ----------
check("poly 2.5.2", hx(poly1305.mac(dhx(V.poly252_key), V.poly252_text)), V.poly252_tag)
for n = 1, 4 do
        check("poly a3#" .. n, hx(poly1305.mac(dhx(V["a3" .. n .. "_key"]), dhx(V["a3" .. n .. "_text"]))), V["a3" .. n .. "_tag"])
end
for n = 5, 10 do
        local r = V["a3" .. n .. "_r"]
        if r then
                check("poly a3#" .. n, hx(poly1305.mac(dhx(r) .. dhx(V["a3" .. n .. "_s"]), dhx(V["a3" .. n .. "_data"]))), V["a3" .. n .. "_tag"])
        end
end

-- ---------- aead (RFC 8439 §2.8.2) ----------
local akey = dhx(V.aead_key)
local nonce12 = dhx(V.aead_common .. V.aead_iv)
local aad = dhx(V.aead_aad)
local pt = dhx(V.aead_pt)
local sealed = aead.seal(akey, nonce12, aad, pt)
check("aead ct", hx(sealed:sub(1, #sealed - 16)), V.aead_ct)
check("aead tag", hx(sealed:sub(#sealed - 15)), V.aead_tag)
check("aead open", aead.open(akey, nonce12, aad, sealed), pt)
check("aead tamper ct", aead.open(akey, nonce12, aad, "x" .. sealed:sub(2)), nil)
check("aead tamper aad", aead.open(akey, nonce12, "y", sealed), nil)
check("aead short", aead.open(akey, nonce12, aad, "12345"), nil)

-- ---------- hkdf (RFC 5869) ----------
for n = 1, 3 do
        local tc = V["hkdf_tc" .. n]
        check("hkdf tc" .. n, hx(hkdf.hkdf_sha256(dhx(tc.ikm), dhx(tc.salt), dhx(tc.info), tc.L)), tc.okm)
end

-- ---------- x25519 (RFC 7748 §5.2 + §6.1) ----------
check("x25519 vec1", hx(x25519.scalarmult(
        dhx("a546e36bf0527c9d3b16154b82465edd62144c0ac1fc5a18506a2244ba449ac4"),
        dhx("e6db6867583030db3594c1a424b15f7c726624ec26b3353b10a903a6d0ab1c4c"))),
        "c3da55379de9c6908e94ea4df28d084f32eccf03491c71f754b4075577a28552")
check("x25519 vec2", hx(x25519.scalarmult(
        dhx("4b66e9d4d1b4673c5ad22691957d6af5c11b6421e0ea01d42ca4169e7918ba0d"),
        dhx("e5210f12786811d3f4b7959d0538ae2c31dbe7106fc03c3efc4cd549c715a493"))),
        "95cbde9476e8907d7aade45cb4b873f88b595a68799fa152e6f8f7647aac7957")
local a_sk = dhx("77076d0a7318a57d3c16c17251b26645df4c2f87ebc0992ab177fba51db92c2a")
local b_sk = dhx("5dab087e624a8a4b79e17f8b83800ee66f3bb1292618b6fd1c2f8b27ff88e0eb")
local a_pk = dhx("8520f0098930a754748b7ddcb43ef75a0dbf3a0d26381af4eba4a98eaa9b4e6a")
local b_pk = dhx("de9edb7d7b7dc1b4d35b61c2ece435373f8343c85b78674dadfc7e146f882b4f")
local shared = dhx("4a5d9d5ba4ce2de1728e3bf480350f25e07e21c947d19e3376f09b3c1e161742")
check("x25519 alice pk", hx(x25519.public_key(a_sk)), hx(a_pk))
check("x25519 bob pk", hx(x25519.public_key(b_sk)), hx(b_pk))
check("x25519 shared a", hx(x25519.shared(a_sk, b_pk)), hx(shared))
check("x25519 shared b", hx(x25519.shared(b_sk, a_pk)), hx(shared))
check("x25519 iterated I=1", hx(x25519.scalarmult(dhx("09" .. string.rep("00", 31)), dhx("09" .. string.rep("00", 31)))),
        "422c8e7a6227d7bca1350b3e2bb7279f7897b87bb6854b783c60e80311ae3079")

-- ---------- ed25519 (RFC 8032 §7.1, all 5 vectors + negatives) ----------
for i, tv in ipairs(vectors.ed25519) do
        check("ed25519 verify #" .. i, ed25519.verify(dhx(tv.pk), dhx(tv.msg), dhx(tv.sig)), true)
end
local tv1 = vectors.ed25519[1]
check("ed25519 wrong msg", ed25519.verify(dhx(tv1.pk), dhx(tv1.msg) .. "x", dhx(tv1.sig)), false)
check("ed25519 bad sig", ed25519.verify(dhx(tv1.pk), dhx(tv1.msg), dhx(tv1.sig):sub(1, 63) .. "x"), false)
check("ed25519 sig >= L", ed25519.verify(dhx(tv1.pk), dhx(tv1.msg),
        dhx(tv1.sig):sub(1, 64) .. "edaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa00"), false)

-- ---------- signer self-check (used by mock server) ----------
local sign_sk = dhx("833fe62409237b9d62ec77587520911e9a759cec1d19755b7da901b96dca3d42")
check("signer pubkey", hx(Signer.secret_to_public(sign_sk)), vectors.ed25519[5].pk)
check("signer sign/verify", ed25519.verify(Signer.secret_to_public(sign_sk), "hello", Signer.sign(sign_sk, "hello")), true)

-- ---------- SDK + mock server flow ----------
local files = {}
local TestEnv = {
        json_encode = json.encode,
        json_decode = json.decode,
        os_time = function()
                return 1791638000
        end,
        random_bytes = function(n)
                local t = {}
                for i = 1, n do
                        t[i] = string.char((i * 37 + 11) % 251)
                end
                return table.concat(t)
        end,
        file = {
                read = function(p)
                        return files[p]
                end,
                write = function(p, d)
                        files[p] = d
                end,
                exists = function(p)
                        return files[p] ~= nil
                end,
                mkdir = function() end,
        },
}

local signing_sk = dhx("9d61b19deffd5a60ba844af4927d2adf7817f8a7d9987c4bf0be36c17e94d0d2")
local server = MockServer(Crypto, TestEnv, Signer, {
        signing_sk = signing_sk,
        proof_key = "proof-secret-1",
        valid_key = "TEST-AAAAA-BBBBB-CCCCC-DDDDD",
        script_id = "0123456789abcdef0123456789abcdef",
        build = "build-42",
        build_hash = hx(sha2.sha256("bundle-v1")),
        bundle = "FAKE-BUNDLE-BYTES-0123456789",
        watermark_id = "wm-17",
        server_time = 1791638000 + 5,
        server_x25519_sk = dhx("5dab087e624a8a4b79e17f8b83800ee66f3bb1292618b6fd1c2f8b27ff88e0eb"),
        server_nonce = dhx("11111111111111111111111111111111"),
})
TestEnv.request = server.request

local SDK = load_module("loader/sdk/library.lua")(Crypto, TestEnv)
local sdk = SDK.new({
        script_id = "0123456789abcdef0123456789abcdef",
        base_url = "https://mock-api",
        proof_key = "proof-secret-1",
        verify_pk = server.server_pk,
        lv = "1.0.0",
})

local sync = sdk.sync()
check("sdk sync offset", sync ~= nil and sdk.time_offset, 5)
check("sdk sync nodes", sync ~= nil and #sdk.nodes, 1)
local status = sdk.status()
check("sdk status active", status ~= nil and status.active, true)

local res = sdk.check_key("TEST-AAAAA-BBBBB-CCCCC-DDDDD")
check("sdk check_key ok", res.ok, true)
check("sdk check_key code", res.code, "KEY_VALID")
check("sdk check_key note", res.data and res.data.note, "mock note")
check("sdk check_key executions", res.data and res.data.total_executions, 7)
local res_bad = sdk.check_key("TEST-WRONG")
check("sdk wrong key denied", res_bad.ok, false)
check("sdk wrong key code", res_bad.code, "KEY_INVALID")
check("sdk proof was verified serverside", server.state.proof_checked, true)
check("sdk nonce header present", server.state.check_key_headers["x-nonce"] ~= nil, true)
check("sdk x-lv sent", server.state.check_key_headers["x-lv"], "1.0.0")

sdk.save_key_cache("yuri/key.txt", "TEST-AAAAA-BBBBB-CCCCC-DDDDD")
check("sdk key cache roundtrip", sdk.load_key_cache("yuri/key.txt"), "TEST-AAAAA-BBBBB-CCCCC-DDDDD")
check("sdk key cache miss", sdk.load_key_cache("yuri/none.txt"), nil)

-- unknown code treated as denial
local orig_request = TestEnv.request
TestEnv.request = function(opts)
        local r = orig_request(opts)
        if opts.Url:find("/check_key") then
                r = {
                        StatusCode = 200,
                        Body = json.encode({ code = "SOME_NEW_CODE", message = "x", data = {} }),
                        Headers = { ["x-ts"] = "1", ["x-sig"] = "AAAA" },
                }
        end
        return r
end
local res_unknown = sdk.check_key("TEST-AAAAA-BBBBB-CCCCC-DDDDD")
TestEnv.request = orig_request
check("sdk unknown code denial", res_unknown.ok, false)

-- bad signature treated as denial
TestEnv.request = function(opts)
        local r = orig_request(opts)
        if opts.Url:find("/check_key") then
                local body = json.decode(r.Body)
                local sts = r.Headers["x-ts"]
                r = {
                        StatusCode = 200,
                        Body = json.encode({ code = "KEY_VALID", message = "forged", data = body.data }),
                        Headers = { ["x-ts"] = sts, ["x-sig"] = r.Headers["x-sig"] },
                }
                r.Headers["x-sig"] = encoding.b64url_encode(Signer.sign(signing_sk, "tampered|" .. sts))
        end
        return r
end
local res_forged = sdk.check_key("TEST-AAAAA-BBBBB-CCCCC-DDDDD")
TestEnv.request = orig_request
check("sdk forged sig denial", res_forged.ok, false)

-- ---------- handshake flow ----------
local Handshake = load_module("loader/init/handshake.lua")(Crypto, TestEnv)
local h = Handshake.new({
        script_id = "0123456789abcdef0123456789abcdef",
        base_url = "https://mock-api",
        proof_key = "proof-secret-1",
        verify_pk = server.server_pk,
        lv = "1.0.0",
        build = "build-42",
})
local session = h.init("TEST-AAAAA-BBBBB-CCCCC-DDDDD", 123, 456, 789)
check("handshake session token", session ~= nil and session.session_token, encoding.b64url_encode(dhx("11111111111111111111111111111111")))
check("handshake tier", session and session.tier, "paid")
check("handshake payload_ref", session and session.payload_ref, "ref-1")
check("handshake watermark from server", session and session.watermark_id, "wm-17")
local payload = h.payload(session)
check("handshake payload build_hash", payload and payload.build_hash, hx(sha2.sha256("bundle-v1")))
check("handshake payload bundle", payload and payload.bundle, "FAKE-BUNDLE-BYTES-0123456789")
check("handshake payload sig len", payload and #payload.bundle_sig, 64)

local bad_session = h.init("TEST-WRONG", 1, 2, 3)
check("handshake wrong key fails", bad_session, nil)

local tampered_server = MockServer(Crypto, TestEnv, Signer, {
        signing_sk = signing_sk,
        proof_key = "proof-secret-1",
        valid_key = "TEST-AAAAA-BBBBB-CCCCC-DDDDD",
        script_id = "0123456789abcdef0123456789abcdef",
        build = "build-42",
        build_hash = hx(sha2.sha256("bundle-v1")),
        bundle = "FAKE-BUNDLE-BYTES-0123456789",
        watermark_id = "wm-17",
        server_time = 1791638000 + 5,
        server_x25519_sk = dhx("5dab087e624a8a4b79e17f8b83800ee66f3bb1292618b6fd1c2f8b27ff88e0eb"),
        server_nonce = dhx("11111111111111111111111111111111"),
        fail_sig = true,
})
tampered_server.request = function(opts)
        local r = server.request(opts)
        if opts.Url:find("/payload$") then
                r = {
                        StatusCode = 200,
                        Body = r.Body:sub(1, #r.Body - 2) .. "AA",
                        Headers = r.Headers,
                }
        end
        return r
end
local saved_request = TestEnv.request
TestEnv.request = tampered_server.request
local bad_payload = h.payload(session)
TestEnv.request = saved_request
check("handshake tampered payload rejected", bad_payload, nil)

-- ---------- summary ----------
print(string.format("\n%d passed, %d failed", pass, fail))
if fail > 0 then
        print("failed: " .. table.concat(failures, ", "))
        os.exit(1)
end
