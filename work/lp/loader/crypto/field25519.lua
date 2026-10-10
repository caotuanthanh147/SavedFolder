-- field25519.lua — arithmetic in GF(2^255 - 19).
-- Representation: 16 little-endian 16-bit limbs (indices 0..15).
-- All intermediates bounded for double precision: schoolbook products
-- < 2^32, limb sums < 2^37, fold multipliers < 2^6.
-- 2^256 folds to 38 (2^256 = 2 * 2^255 = 2 * 19).
-- Deps: B (bit ops).

return function(B)
	local band, bor = B.band, B.bor
	local lshift, rshift = B.lshift, B.rshift
	local floor = math.floor

	-- p = 2^255 - 19 as limbs: 0xFFFB in limb 0, 0xFFFF elsewhere, 0x7FFF on top
	local PLIMBS = { [0] = 0xFFED }
	for i = 1, 14 do
		PLIMBS[i] = 0xFFFF
	end
	PLIMBS[15] = 0x7FFF

	local function copy(a)
		local r = {}
		for i = 0, 15 do
			r[i] = a[i]
		end
		return r
	end

	local function zero()
		local r = {}
		for i = 0, 15 do
			r[i] = 0
		end
		return r
	end

	local function one()
		local r = zero()
		r[0] = 1
		return r
	end

	local function from_small(n)
		local r = zero()
		r[0] = n % 65536
		r[1] = floor(n / 65536)
		return r
	end

	-- carry-propagate a[0..16] so a[0..15] < 2^16; returns nothing.
	-- a[16] may hold a small overflow that folds back as 38 * a[16].
	local function carry(a)
		local c = 0
		for i = 0, 15 do
			local v = a[i] + c
			a[i] = v % 65536
			c = floor(v / 65536)
		end
		if (a[16] or 0) > 0 then
			c = c + a[16]
			a[16] = 0
		end
		while c > 0 do
			local v = a[0] + 38 * c
			a[0] = v % 65536
			c = floor(v / 65536)
			for i = 1, 15 do
				if c == 0 then
					break
				end
				v = a[i] + c
				a[i] = v % 65536
				c = floor(v / 65536)
			end
		end
	end

	-- full reduction: carry + conditional subtraction of p (twice)
	local function reduce(a)
		carry(a)
		for _ = 1, 2 do
			local ge = true
			for i = 15, 0, -1 do
				local pv = PLIMBS[i]
				if a[i] ~= pv then
					ge = a[i] > pv
					break
				end
			end
			if not ge then
				break
			end
			local borrow = 0
			for i = 0, 15 do
				local v = a[i] - PLIMBS[i] - borrow
				if v < 0 then
					v = v + 65536
					borrow = 1
				else
					borrow = 0
				end
				a[i] = v
			end
		end
		return a
	end

	local function add(a, b)
		local r = {}
		for i = 0, 15 do
			r[i] = a[i] + b[i]
		end
		return reduce(r)
	end

	local function sub(a, b)
		-- a + 2p - b, then reduce
		local r = {}
		local c = 0
		for i = 0, 15 do
			local v = a[i] + PLIMBS[i] + PLIMBS[i] + c
			r[i] = v % 65536
			c = floor(v / 65536)
		end
		r[16] = c
		local borrow = 0
		for i = 0, 15 do
			local v = r[i] - b[i] - borrow
			if v < 0 then
				v = v + 65536
				borrow = 1
			else
				borrow = 0
			end
			r[i] = v
		end
		r[16] = r[16] - borrow
		return reduce(r)
	end
	local function neg(a)
		return sub(zero(), a)
	end

	local function mul(a, b)
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
		-- fold limbs 16..31 with 2^256 == 38 (mod p)
		for i = 31, 16, -1 do
			local v = t[i]
			if v ~= 0 then
				t[i] = 0
				t[i - 16] = t[i - 16] + v * 38
			end
		end
		local r = {}
		for i = 0, 15 do
			r[i] = t[i]
		end
		return reduce(r)
	end

	local function mul_small(a, n)
		local r = {}
		for i = 0, 15 do
			r[i] = a[i] * n
		end
		return reduce(r)
	end

	local function eq(a, b)
		local ra, rb = reduce(copy(a)), reduce(copy(b))
		for i = 0, 15 do
			if ra[i] ~= rb[i] then
				return false
			end
		end
		return true
	end

	local function is_zero(a)
		for i = 0, 15 do
			if a[i] ~= 0 then
				return false
			end
		end
		return true
	end

	local function frombytes(s)
		local r = {}
		for i = 0, 15 do
			r[i] = s:byte(2 * i + 1) + lshift(s:byte(2 * i + 2), 8)
		end
		r[15] = band(r[15], 0x7FFF)
		return reduce(r)
	end

	local function tobytes(a)
		local r = reduce(copy(a))
		local out = {}
		for i = 0, 15 do
			out[#out + 1] = string.char(band(r[i], 255), rshift(r[i], 8))
		end
		return table.concat(out)
	end

	-- exponent as limb array (16-bit LE limbs), MSB-first square-and-multiply
	local function pow(base, e)
		local result = one()
		local top = 15
		while top > 0 and e[top] == 0 do
			top = top - 1
		end
		local bits = 0
		local probe = e[top]
		while probe > 0 do
			probe = floor(probe / 2)
			bits = bits + 1
		end
		local total = top * 16 + bits
		for i = total - 1, 0, -1 do
			result = mul(result, result)
			local limb = e[floor(i / 16)]
			local bit = band(rshift(limb, i % 16), 1)
			if bit == 1 then
				result = mul(result, base)
			end
		end
		return result
	end

	-- modular inverse via Fermat: a^(p-2)
	local PM2 = { [0] = 0xFFEB }
	for i = 1, 14 do
		PM2[i] = 0xFFFF
	end
	PM2[15] = 0x7FFF

	local function invert(a)
		return pow(a, PM2)
	end

	-- (p-1)/4 for sqrt(-1) = 2^((p-1)/4)
	local PM14 = { [0] = 0xFFFB }
	for i = 1, 14 do
		PM14[i] = 0xFFFF
	end
	PM14[15] = 0x1FFF

	return {
		PLIMBS = PLIMBS,
		copy = copy,
		zero = zero,
		one = one,
		from_small = from_small,
		carry = carry,
		reduce = reduce,
		add = add,
		sub = sub,
		neg = neg,
		mul = mul,
		mul_small = mul_small,
		eq = eq,
		is_zero = is_zero,
		frombytes = frombytes,
		tobytes = tobytes,
		pow = pow,
		invert = invert,
		PM14 = PM14,
	}
end
