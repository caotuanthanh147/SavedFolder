-- ed25519_sign.lua — TEST-ONLY Ed25519 signing (RFC 8032 §5.1.6).
-- The shipped SDK verifies only; the mock server needs to SIGN to
-- exercise the verification path end to end.

return function(B, F, sha2, ed25519)
	local floor = math.floor

	local function limbs_to_bytes(s)
		local out = {}
		for i = 0, 15 do
			local v = s[i] or 0
			out[#out + 1] = string.char(v % 256, floor(v / 256) % 256)
		end
		return table.concat(out)
	end

	local function bytes_to_limbs(b)
		local s = {}
		for i = 0, 15 do
			s[i] = b:byte(2 * i + 1) + b:byte(2 * i + 2) * 256
		end
		return s
	end

	local function scalar_add_mod_L(a, b)
		local r = {}
		local carry = 0
		for i = 0, 15 do
			local v = a[i] + b[i] + carry
			r[i] = v % 65536
			carry = floor(v / 65536)
		end
		local L = ed25519.L
	if carry > 0 or (r[15] > L[15]) or (r[15] == L[15] and scalar_ge_L(r)) then
			local borrow = 0
			for i = 0, 15 do
				local v = r[i] - L[i] - borrow
				if v < 0 then
					v = v + 65536
					borrow = 1
				else
					borrow = 0
				end
				r[i] = v
			end
		end
		return r
	end

	local function scalar_mul_mod_L(a, b)
		local t = {}
		for i = 0, 31 do
			t[i] = 0
		end
		for i = 0, 15 do
			local ai = a[i]
			if ai ~= 0 then
				for j = 0, 15 do
					t[i + j] = t[i + j] + ai * b[j]
				end
			end
		end
		for i = 0, 30 do
			local v = t[i]
			t[i] = v % 65536
			t[i + 1] = t[i + 1] + floor(v / 65536)
		end
		local bytes = {}
		for i = 0, 31 do
			bytes[#bytes + 1] = string.char(t[i] % 256, floor(t[i] / 256) % 256)
		end
		return ed25519.scalar_mod_L(table.concat(bytes))
	end

	-- clamp a = LE(h[0..31]) with bit 254 set, bits 255 and 0-2 clear
	local function secret_expand(secret)
		local h = sha2.sha512(secret)
		local a = bytes_to_limbs(h:sub(1, 32))
		a[0] = a[0] - (a[0] % 8)
		a[15] = a[15] % 32768
		a[15] = a[15] + 16384
		return a, h:sub(33)
	end

	local function secret_to_public(secret)
		local a = secret_expand(secret)
		local A = ed25519.point_mul(a, ed25519.G)
		return ed25519.point_compress(A)
	end

	local function sign(secret, msg)
		local a, prefix = secret_expand(secret)
		local A = ed25519.point_compress(ed25519.point_mul(a, ed25519.G))
		local r = ed25519.sha512_modq(prefix .. msg)
		local R = ed25519.point_compress(ed25519.point_mul(r, ed25519.G))
		local h = ed25519.sha512_modq(R .. A .. msg)
		local ha = scalar_mul_mod_L(h, a)
		local s = scalar_add_mod_L(r, ha)
		return R .. limbs_to_bytes(s)
	end

	return {
		secret_to_public = secret_to_public,
		sign = sign,
	}
end
