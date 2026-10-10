-- gen_vectors_ext.lua — extends contracts/test_vectors.json with the
-- x25519 + ed25519 cross-implementation sections requested by M1
-- (cross-m3.test.ts). Machine transfer: ed25519 comes from
-- tests/vectors.lua (RFC 8032 §7.1, machine-extracted + suite-verified),
-- x25519 uses the same RFC 7748 §5.2/§6.1 literals run.lua checks.
-- Every entry is VERIFIED against the shipped implementations BEFORE
-- the file is written — a mistyped byte aborts generation.
-- Usage: lua5.4 tests/gen_vectors_ext.lua   (from the repo root)

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
local vectors = require("tests.vectors")

local bit_chunk = assert(loadfile(ROOT .. "/loader/crypto/bit.lua"), "bit.lua")
local B = bit_chunk()()

local function load_module(path)
        local f = assert(loadfile(ROOT .. "/" .. path))
        return f()
end

local sha2 = load_module("loader/crypto/sha2.lua")(B)
local hmac = load_module("loader/crypto/hmac.lua")(B, sha2)
local encoding = load_module("loader/crypto/encoding.lua")()
local field = load_module("loader/crypto/field25519.lua")(B)
local x25519 = load_module("loader/crypto/x25519.lua")(B, field)
local ed25519 = load_module("loader/crypto/ed25519.lua")(B, field, sha2)

local function dhx(s)
        return assert(encoding.hex_decode(s), "bad hex literal")
end
local function hx(s)
        return string.lower(encoding.hex_encode(s))
end

-- RFC 7748 §5.2 scalar-multiplication vectors (same literals run.lua checks).
local scalarmult = {
        {
                scalar = "a546e36bf0527c9d3b16154b82465edd62144c0ac1fc5a18506a2244ba449ac4",
                u = "e6db6867583030db3594c1a424b15f7c726624ec26b3353b10a903a6d0ab1c4c",
                out = "c3da55379de9c6908e94ea4df28d084f32eccf03491c71f754b4075577a28552",
        },
        {
                scalar = "4b66e9d4d1b4673c5ad22691957d6af5c11b6421e0ea01d42ca4169e7918ba0d",
                u = "e5210f12786811d3f4b7959d0538ae2c31dbe7106fc03c3efc4cd549c715a493",
                out = "95cbde9476e8907d7aade45cb4b873f88b595a68799fa152e6f8f7647aac7957",
        },
}

-- RFC 7748 §6.1 Diffie-Hellman example.
local dh = {
        alice_sk = "77076d0a7318a57d3c16c17251b26645df4c2f87ebc0992ab177fba51db92c2a",
        alice_pk = "8520f0098930a754748b7ddcb43ef75a0dbf3a0d26381af4eba4a98eaa9b4e6a",
        bob_sk = "5dab087e624a8a4b79e17f8b83800ee66f3bb1292618b6fd1c2f8b27ff88e0eb",
        bob_pk = "de9edb7d7b7dc1b4d35b61c2ece435373f8343c85b78674dadfc7e146f882b4f",
        shared = "4a5d9d5ba4ce2de1728e3bf480350f25e07e21c947d19e3376f09b3c1e161742",
}

-- RFC 7748 §6.1 iterated scalar multiplication, 1 iteration.
local iterated_1 = {
        input_u = "09" .. string.rep("00", 31),
        output_u = "422c8e7a6227d7bca1350b3e2bb7279f7897b87bb6854b783c60e80311ae3079",
}

local failures = 0
local function assert_eq(what, got, want)
        if got ~= want then
                print("VERIFY FAIL " .. what .. ": got " .. tostring(got) .. " want " .. tostring(want))
                failures = failures + 1
        end
end

for i, v in ipairs(scalarmult) do
        assert_eq("x25519 scalarmult #" .. i, hx(x25519.scalarmult(dhx(v.scalar), dhx(v.u))), v.out)
end
assert_eq("x25519 alice pk", hx(x25519.public_key(dhx(dh.alice_sk))), dh.alice_pk)
assert_eq("x25519 bob pk", hx(x25519.public_key(dhx(dh.bob_sk))), dh.bob_pk)
assert_eq("x25519 shared (alice)", hx(x25519.shared(dhx(dh.alice_sk), dhx(dh.bob_pk))), dh.shared)
assert_eq("x25519 shared (bob)", hx(x25519.shared(dhx(dh.bob_sk), dhx(dh.alice_pk))), dh.shared)
assert_eq("x25519 iterated I=1", hx(x25519.scalarmult(dhx(iterated_1.input_u), dhx(iterated_1.input_u))), iterated_1.output_u)
for i, tv in ipairs(vectors.ed25519) do
        if not ed25519.verify(dhx(tv.pk), dhx(tv.msg), dhx(tv.sig)) then
                print("VERIFY FAIL ed25519 #" .. i)
                failures = failures + 1
        end
end

if failures > 0 then
        print(failures .. " verification failures — NOT writing")
        os.exit(1)
end

local path = ROOT .. "/contracts/test_vectors.json"
local f = assert(io.open(path, "r"))
local data = json.decode(f:read("*a"))
f:close()
assert(type(data) == "table", "existing test_vectors.json did not decode")

data.x25519_7748_52_scalarmult = scalarmult
data.x25519_7748_61_dh = dh
data.x25519_7748_61_iterated_1 = iterated_1
data.ed25519_8032_71 = vectors.ed25519

local out = json.encode(data)
assert(out ~= nil, "encode failed")
f = assert(io.open(path, "w"))
f:write(out)
f:close()

print(string.format("verified + written: 2 scalarmult + dh + iterated + %d ed25519 vectors", #vectors.ed25519))
