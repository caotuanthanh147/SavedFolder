-- ed25519.lua — Ed25519 signature verification (RFC 8032 §5.1.7),
-- following the RFC's reference implementation structure.
-- Point arithmetic: extended twisted Edwards coordinates; doubling is
-- expressed as point_add(P, P) exactly as in the reference. The curve
-- constant d, sqrt(-1), and the base point are derived from p at init.
-- Deps: B (bit ops), F (field25519), sha2.

return function(B, F, sha2)
	local band = B.band
	local floor = math.floor

	-- L = 2^252 + 27742317777372353535851937790883648493
	local LLIMB = { [0] = 0xD3ED, 0x5CF5, 0x631A, 0x5812, 0x9CD6, 0xA2F7, 0xF9DE, 0x14DE,
		0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x1000 }

	local d = F.mul(F.neg(F.from_small(121665)), F.invert(F.from_small(121666)))
	local sqrt_m1 = F.pow(F.from_small(2), F.PM14)

	-- (p+3)/8 = 2^252 - 2
	local P38 = { [0] = 0xFFFE }
	for i = 1, 14 do
		P38[i] = 0xFFFF
	end
	P38[15] = 0x0FFF

	-- point = { x, y, z, t }
	local function point_add(P, Q)
		local a1 = F.mul(F.sub(P[2], P[1]), F.sub(Q[2], Q[1]))
		local b1 = F.mul(F.add(P[2], P[1]), F.add(Q[2], Q[1]))
		local c1 = F.mul(d, F.mul_small(F.mul(P[4], Q[4]), 2))
		local d1 = F.mul_small(F.mul(P[3], Q[3]), 2)
		local e = F.sub(b1, a1)
		local f = F.sub(d1, c1)
		local g = F.add(d1, c1)
		local h = F.add(b1, a1)
		return { F.mul(e, f), F.mul(g, h), F.mul(f, g), F.mul(e, h) }
	end

	local function point_equal(P, Q)
		if not F.eq(F.mul(P[1], Q[3]), F.mul(Q[1], P[3])) then
			return false
		end
		if not F.eq(F.mul(P[2], Q[3]), F.mul(Q[2], P[3])) then
			return false
		end
		return true
	end

	local function scalar_ge_L(s)
		for i = 15, 0, -1 do
			local sv = s[i] or 0
			if sv ~= LLIMB[i] then
				return sv > LLIMB[i]
			end
		end
		return true
	end

	local function scalar_sub_L_inplace(s)
		local borrow = 0
		for i = 0, 15 do
			local v = s[i] - LLIMB[i] - borrow
			if v < 0 then
				v = v + 65536
				borrow = 1
			else
				borrow = 0
			end
			s[i] = v
		end
	end

	-- s: limb array (LE, 16-bit limbs) of any size; reduce mod L
	-- by processing bits from the top (values stay < 2*L per step).
	local function scalar_mod_L(bytes)
		local r = {}
		for i = 0, 15 do
			r[i] = 0
		end
		local n = #bytes
		for byte_i = n, 1, -1 do
			local byte = bytes:byte(byte_i)
			for bit_i = 7, 0, -1 do
				local bit = band(B.rshift(byte, bit_i), 1)
				local carry = bit
				for i = 0, 15 do
					local v = r[i] * 2 + carry
					r[i] = v % 65536
					carry = floor(v / 65536)
				end
				if scalar_ge_L(r) then
					scalar_sub_L_inplace(r)
				end
			end
		end
		return r
	end

	local function point_mul(s, P)
		local q = { F.zero(), F.one(), F.one(), F.zero() }
		local p = { P[1], P[2], P[3], P[4] }
		local top = 15
		while top > 0 and s[top] == 0 do
			top = top - 1
		end
		local total = top * 16
		local probe = s[top]
		while probe > 0 do
			probe = floor(probe / 2)
			total = total + 1
		end
		for i = 0, total - 1 do
			local limb = s[floor(i / 16)]
			local bit = band(B.rshift(limb, i % 16), 1)
			if bit == 1 then
				q = point_add(q, p)
			end
			p = point_add(p, p)
		end
		return q
	end

	local function recover_x(y, sign)
		if F.is_zero(y) then
			if sign == 1 then
				return nil
			end
			return F.zero()
		end
		local y2 = F.mul(y, y)
		local u = F.sub(y2, F.one())
		local v = F.add(F.mul(d, y2), F.one())
		local x2 = F.mul(u, F.invert(v))
		local x = F.pow(x2, P38)
		if not F.eq(F.mul(x, x), x2) then
			x = F.mul(x, sqrt_m1)
		end
		if not F.eq(F.mul(x, x), x2) then
			return nil
		end
		if band(x[0], 1) ~= sign then
			x = F.neg(x)
		end
		return x
	end

	local function point_decompress(s)
		if #s ~= 32 then
			return nil
		end
		local sign = band(B.rshift(s:byte(32), 7), 1)
		local y = {}
		for i = 0, 15 do
			local lo = s:byte(2 * i + 1)
			local hi = s:byte(2 * i + 2)
			if i == 15 then
				hi = band(hi, 0x7F)
			end
			y[i] = lo + hi * 256
		end
		-- canonical check: masked y must be < p (equality rejected)
		local ge = true
		for i = 15, 0, -1 do
			local pv = F.PLIMBS[i]
			if y[i] ~= pv then
				ge = y[i] > pv
				break
			end
		end
		if ge then
			return nil
		end
		y = F.reduce(y)
		local x = recover_x(y, sign)
		if not x then
			return nil
		end
		return { x, y, F.one(), F.mul(x, y) }
	end

	local function point_compress(P)
		local zinv = F.invert(P[3])
		local x = F.mul(P[1], zinv)
		local y = F.mul(P[2], zinv)
		local out = F.tobytes(y)
		if band(x[0], 1) == 1 then
			return out:sub(1, 31) .. string.char(out:byte(32) + 128)
		end
		return out
	end

	-- G
	local gy = F.mul(F.from_small(4), F.invert(F.from_small(5)))
	local gx = recover_x(gy, 0)
	local G = { gx, gy, F.one(), F.mul(gx, gy) }

	-- sha512(bytes) interpreted LE, reduced mod L
	local function sha512_modq(data)
		return scalar_mod_L(sha2.sha512(data))
	end

	local function verify(public, msg, signature)
		if #public ~= 32 then
			return false
		end
		if #signature ~= 64 then
			return false
		end
		local A = point_decompress(public)
		if not A then
			return false
		end
		local Rs = signature:sub(1, 32)
		local R = point_decompress(Rs)
		if not R then
			return false
		end
		local s = {}
		for i = 0, 15 do
			s[i] = signature:byte(2 * i + 33) + signature:byte(2 * i + 34) * 256
		end
		if scalar_ge_L(s) then
			return false
		end
		local h = sha512_modq(Rs .. public .. msg)
		local sB = point_mul(s, G)
		local hA = point_mul(h, A)
		return point_equal(sB, point_add(R, hA))
	end

	return {
		verify = verify,
		L = LLIMB,
		scalar_ge_L = scalar_ge_L,
		point_compress = point_compress,
		point_decompress = point_decompress,
		point_add = point_add,
		point_mul = point_mul,
		sha512_modq = sha512_modq,
		scalar_mod_L = scalar_mod_L,
		G = G,
	}
end
