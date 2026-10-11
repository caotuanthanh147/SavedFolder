-- fnv.lua — FNV-1a 32-bit + DJB2 dual hash (M13 stub family, D-M6-5).
-- Vectors: draft-eastlake-fnv (prime 16777619, offset 2166136261);
-- DJB2 (Bernstein) h = h*33 + byte, both mod 2^32.
-- Deps: B (bit ops, for bxor).

return function(B)
	local bxor = B and B.bxor or nil

	local function mul32(a, b)
		local al = a % 65536
		local ah = (a - al) / 65536
		local bl = b % 65536
		local bh = (b - bl) / 65536
		return (al * bl + ((al * bh + ah * bl) % 65536) * 65536) % 4294967296
	end

	local function djb2(data)
		local h = 5381
		for i = 1, #data do
			h = (mul32(h, 33) + string.byte(data, i)) % 4294967296
		end
		return h
	end

	local function fnv1a(data)
		local h = 2166136261
		for i = 1, #data do
			h = mul32(bxor(h, string.byte(data, i)), 16777619)
		end
		return h
	end

	return { fnv1a = fnv1a, djb2 = djb2, mul32 = mul32 }
end
