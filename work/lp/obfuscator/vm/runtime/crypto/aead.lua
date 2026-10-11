-- aead.lua — ChaCha20-Poly1305 AEAD (RFC 8439 §2.6-2.8).
-- seal/open(key, nonce, aad, plaintext) with the RFC construction:
-- poly key = first 32 bytes of chacha20 block 0; ciphertext from
-- counter 1; tag over aad || pad || ct || pad || lens.
-- Deps: B (bit ops), chacha20, poly1305.

return function(B, chacha20, poly1305)
	local floor = math.floor

	local function pad16(data)
		local rem = #data % 16
		if rem == 0 then
			return ""
		end
		return string.rep("\0", 16 - rem)
	end

	local function le64(n)
		local t = {}
		for i = 0, 7 do
			t[#t + 1] = string.char(floor(n / 2 ^ (8 * i)) % 256)
		end
		return table.concat(t)
	end

	local function mac_data(aad, ct)
		return aad .. pad16(aad) .. ct .. pad16(ct) .. le64(#aad) .. le64(#ct)
	end

	local function seal(key, nonce, aad, plaintext)
		if #key ~= 32 or #nonce ~= 12 then
			return nil
		end
		local otk = chacha20.block(key, 0, nonce):sub(1, 32)
		local ct = chacha20.xor_stream(key, 1, nonce, plaintext)
		local tag = poly1305.mac(otk, mac_data(aad, ct))
		return ct .. tag
	end

	local function open(key, nonce, aad, data)
		if #key ~= 32 or #nonce ~= 12 or #data < 16 then
			return nil
		end
		local ct = data:sub(1, #data - 16)
		local tag = data:sub(#data - 15)
		local otk = chacha20.block(key, 0, nonce):sub(1, 32)
		local expect = poly1305.mac(otk, mac_data(aad, ct))
		if expect ~= tag then
			return nil
		end
		return chacha20.xor_stream(key, 1, nonce, ct)
	end

	return { seal = seal, open = open }
end
