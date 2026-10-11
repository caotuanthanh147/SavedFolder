-- chacha20.lua — ChaCha20 stream cipher (RFC 8439 §2.3-2.4).
-- Key 32 bytes, nonce 12 bytes, 32-bit block counter.
-- Deps: B (bit ops).

return function(B)
	local band, bxor = B.band, B.bxor
	local lrotate = B.lrotate
	local floor = math.floor

	local function quarter(s, a, b, c, d)
		s[a] = (s[a] + s[b]) % 4294967296
		s[d] = lrotate(bxor(s[d], s[a]), 16)
		s[c] = (s[c] + s[d]) % 4294967296
		s[b] = lrotate(bxor(s[b], s[c]), 12)
		s[a] = (s[a] + s[b]) % 4294967296
		s[d] = lrotate(bxor(s[d], s[a]), 8)
		s[c] = (s[c] + s[d]) % 4294967296
		s[b] = lrotate(bxor(s[b], s[c]), 7)
	end

	-- Returns the 64-byte keystream block for (key, counter, nonce).
	local function block(key, counter, nonce)
		local st = {
			0x61707865, 0x3320646e, 0x79622d32, 0x6b206574,
			key:byte(1) + key:byte(2) * 256 + key:byte(3) * 65536 + key:byte(4) * 16777216,
			key:byte(5) + key:byte(6) * 256 + key:byte(7) * 65536 + key:byte(8) * 16777216,
			key:byte(9) + key:byte(10) * 256 + key:byte(11) * 65536 + key:byte(12) * 16777216,
			key:byte(13) + key:byte(14) * 256 + key:byte(15) * 65536 + key:byte(16) * 16777216,
			key:byte(17) + key:byte(18) * 256 + key:byte(19) * 65536 + key:byte(20) * 16777216,
			key:byte(21) + key:byte(22) * 256 + key:byte(23) * 65536 + key:byte(24) * 16777216,
			key:byte(25) + key:byte(26) * 256 + key:byte(27) * 65536 + key:byte(28) * 16777216,
			key:byte(29) + key:byte(30) * 256 + key:byte(31) * 65536 + key:byte(32) * 16777216,
			counter % 4294967296,
			nonce:byte(1) + nonce:byte(2) * 256 + nonce:byte(3) * 65536 + nonce:byte(4) * 16777216,
			nonce:byte(5) + nonce:byte(6) * 256 + nonce:byte(7) * 65536 + nonce:byte(8) * 16777216,
			nonce:byte(9) + nonce:byte(10) * 256 + nonce:byte(11) * 65536 + nonce:byte(12) * 16777216,
		}
		local w = {}
		for i = 1, 16 do
			w[i] = st[i]
		end
		for _ = 1, 10 do
			quarter(w, 1, 5, 9, 13)
			quarter(w, 2, 6, 10, 14)
			quarter(w, 3, 7, 11, 15)
			quarter(w, 4, 8, 12, 16)
			quarter(w, 1, 6, 11, 16)
			quarter(w, 2, 7, 12, 13)
			quarter(w, 3, 8, 9, 14)
			quarter(w, 4, 5, 10, 15)
		end
		local out = {}
		for i = 1, 16 do
			local v = (w[i] + st[i]) % 4294967296
			out[#out + 1] = string.char(v % 256, floor(v / 256) % 256, floor(v / 65536) % 256, floor(v / 16777216) % 256)
		end
		return table.concat(out)
	end

	local function xor_stream(key, counter, nonce, data)
		local out = {}
		local n = #data
		local pos = 1
		local ctr = counter
		while pos <= n do
			local ks = block(key, ctr, nonce)
			local take = n - pos + 1
			if take > 64 then
				take = 64
			end
			local chunk = {}
			for i = 1, take do
				chunk[i] = string.char(bxor(data:byte(pos + i - 1), ks:byte(i)))
			end
			out[#out + 1] = table.concat(chunk)
			pos = pos + 64
			ctr = ctr + 1
		end
		return table.concat(out)
	end

	return { block = block, xor_stream = xor_stream }
end
