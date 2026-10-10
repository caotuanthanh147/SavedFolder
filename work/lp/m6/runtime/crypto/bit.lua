-- bit.lua — 32-bit operation resolver.
-- Resolution order: bit32 (Luau, executors) -> bit (LuaJIT) -> pure-Lua
-- arithmetic fallback (Lua 5.4 CI / exotic hosts).
-- Every returned function takes and returns integers in [0, 2^32).

return function()
	local source = nil
	local native = nil
	if type(bit32) == "table" and type(bit32.band) == "function" then
		source, native = "bit32", bit32
	elseif type(bit) == "table" and type(bit.band) == "function" then
		source, native = "bit", bit
	end

	if native then
		local band, bor, bxor = native.band, native.bor, native.bxor
		local lshift, rshift = native.lshift, native.rshift
		local lrotate = native.lrotate
		return {
			source = source,
			band = band,
			bor = bor,
			bxor = bxor,
			lshift = lshift,
			rshift = rshift,
			lrotate = lrotate,
		}
	end

	local floor = math.floor

	local function band(a, b)
		local r, p = 0, 1
		while a > 0 and b > 0 do
			if a % 2 == 1 and b % 2 == 1 then
				r = r + p
			end
			a = floor(a / 2)
			b = floor(b / 2)
			p = p * 2
		end
		return r
	end

	local function bor(a, b)
		local r, p = 0, 1
		while a > 0 or b > 0 do
			if a % 2 == 1 or b % 2 == 1 then
				r = r + p
			end
			a = floor(a / 2)
			b = floor(b / 2)
			p = p * 2
		end
		return r
	end

	local function bxor(a, b)
		local r, p = 0, 1
		while a > 0 or b > 0 do
			if a % 2 ~= b % 2 then
				r = r + p
			end
			a = floor(a / 2)
			b = floor(b / 2)
			p = p * 2
		end
		return r
	end

	local function lshift(a, n)
		return (a * 2 ^ n) % 4294967296
	end

	local function rshift(a, n)
		return floor(a / 2 ^ n)
	end

	local function lrotate(a, n)
		local lo = (a * 2 ^ n) % 4294967296
		local hi = floor(a / 2 ^ (32 - n))
		return (lo + hi) % 4294967296
	end

	return {
		source = "pure",
		band = band,
		bor = bor,
		bxor = bxor,
		lshift = lshift,
		rshift = rshift,
		lrotate = lrotate,
	}
end
