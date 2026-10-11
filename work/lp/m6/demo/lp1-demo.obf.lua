local entry = (function()
local _q0z = 56869
local _q1z = 28430

local Lg500d, Kob2a, ranmf2, api2i5, cc15, C1j, Oo3t

local _q0z = 3117
local _q1z = 0x2461

local ie0dt = function()
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

local O6t = function(B)
        local band, bor, bxor = B.band, B.bor, B.bxor
        local lshift, rshift, lrotate = B.lshift, B.rshift, B.lrotate
        local floor = math.floor

        local K256 = {
                0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
                0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
                0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
                0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
                0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
                0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
                0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
                0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
        }

        local function sha256(msg)
                local h = {
                        0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
                        0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19,
                }
                local len = #msg
                local bitlen = len * 8
                local pad = 64 - ((len + 9) % 64)
                if pad == 64 then
                        pad = 0
                end
                local hi = floor(bitlen / 2 ^ 32)
                local lo = bitlen % 2 ^ 32
                local tail = "\128" .. string.rep("\0", pad)
                        .. string.char(
                                floor(hi / 2 ^ 24) % 256, floor(hi / 2 ^ 16) % 256, floor(hi / 2 ^ 8) % 256, hi % 256,
                                floor(lo / 2 ^ 24) % 256, floor(lo / 2 ^ 16) % 256, floor(lo / 2 ^ 8) % 256, lo % 256)

                local w = {}
                local block = msg .. tail
                local pos = 1
                while pos <= #block do
                        for i = 0, 15 do
                                local o = pos + i * 4
                                w[i + 1] = block:byte(o) * 2 ^ 24 + block:byte(o + 1) * 2 ^ 16 + block:byte(o + 2) * 2 ^ 8 + block:byte(o + 3)
                        end
                        for i = 17, 64 do
                                local x = w[i - 15]
                                local y = w[i - 2]
                                local s0 = bxor(bxor(lrotate(x, 25), lrotate(x, 14)), rshift(x, 3))
                                local s1 = bxor(bxor(lrotate(y, 15), lrotate(y, 13)), rshift(y, 10))
                                w[i] = (w[i - 16] + s0 + w[i - 7] + s1) % 4294967296
                        end
                        local a, b, c, d, e, f, g, hh = h[1], h[2], h[3], h[4], h[5], h[6], h[7], h[8]
                        for i = 1, 64 do
                                local S1 = bxor(bxor(lrotate(e, 26), lrotate(e, 21)), lrotate(e, 7))
                                local ch = bxor(band(e, f), band(bxor(e, 4294967295), g))
                                local t1 = (hh + S1 + ch + K256[i] + w[i]) % 4294967296
                                local S0 = bxor(bxor(lrotate(a, 30), lrotate(a, 19)), lrotate(a, 10))
                                local maj = bxor(bxor(band(a, b), band(a, c)), band(b, c))
                                local t2 = (S0 + maj) % 4294967296
                                hh, g, f = g, f, e
                                e = (d + t1) % 4294967296
                                d, c, b = c, b, a
                                a = (t1 + t2) % 4294967296
                        end
                        h[1] = (h[1] + a) % 4294967296
                        h[2] = (h[2] + b) % 4294967296
                        h[3] = (h[3] + c) % 4294967296
                        h[4] = (h[4] + d) % 4294967296
                        h[5] = (h[5] + e) % 4294967296
                        h[6] = (h[6] + f) % 4294967296
                        h[7] = (h[7] + g) % 4294967296
                        h[8] = (h[8] + hh) % 4294967296
                        pos = pos + 64
                end

                local out = {}
                for i = 1, 8 do
                        local v = h[i]
                        out[#out + 1] = string.char(floor(v / 2 ^ 24) % 256, floor(v / 2 ^ 16) % 256, floor(v / 2 ^ 8) % 256, v % 256)
                end
                return table.concat(out)
        end

        local K512HI = {
                0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
                0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
                0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
                0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
                0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
                0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
                0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
                0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
                0xca273ece, 0xd186b8c7, 0xeada7dd6, 0xf57d4f7f, 0x06f067aa, 0x0a637dc5, 0x113f9804, 0x1b710b35,
                0x28db77f5, 0x32caab7b, 0x3c9ebe0a, 0x431d67c4, 0x4cc5d4be, 0x597f299c, 0x5fcb6fab, 0x6c44198c,
        }
        local K512LO = {
                0xd728ae22, 0x23ef65cd, 0xec4d3b2f, 0x8189dbbc, 0xf348b538, 0xb605d019, 0xaf194f9b, 0xda6d8118,
                0xa3030242, 0x45706fbe, 0x4ee4b28c, 0xd5ffb4e2, 0xf27b896f, 0x3b1696b1, 0x25c71235, 0xcf692694,
                0x9ef14ad2, 0x384f25e3, 0x8b8cd5b5, 0x77ac9c65, 0x592b0275, 0x6ea6e483, 0xbd41fbd4, 0x831153b5,
                0xee66dfab, 0x2db43210, 0x98fb213f, 0xbeef0ee4, 0x3da88fc2, 0x930aa725, 0xe003826f, 0x0a0e6e70,
                0x46d22ffc, 0x5c26c926, 0x5ac42aed, 0x9d95b3df, 0x8baf63de, 0x3c77b2a8, 0x47edaee6, 0x1482353b,
                0x4cf10364, 0xbc423001, 0xd0f89791, 0x0654be30, 0xd6ef5218, 0x5565a910, 0x5771202a, 0x32bbd1b8,
                0xb8d2d0c8, 0x5141ab53, 0xdf8eeb99, 0xe19b48a8, 0xc5c95a63, 0xe3418acb, 0x7763e373, 0xd6b2b8a3,
                0x5defb2fc, 0x43172f60, 0xa1f0ab72, 0x1a6439ec, 0x23631e28, 0xde82bde9, 0xb2c67915, 0xe372532b,
                0xea26619c, 0x21c0c207, 0xcde0eb1e, 0xee6ed178, 0x72176fba, 0xa2c898a6, 0xbef90dae, 0x131c471b,
                0x23047d84, 0x40c72493, 0x15c9bebc, 0x9c100d4c, 0xcb3e42b6, 0xfc657e2a, 0x3ad6faec, 0x4a475817,
        }
        local H512HI = {
                0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19,
        }
        local H512LO = {
                0xf3bcc908, 0x84caa73b, 0xfe94f82b, 0x5f1d36f1, 0xade682d1, 0x2b3e6c1f, 0xfb41bd6b, 0x137e2179,
        }

        local function add64(ahi, alo, bhi, blo)
                local lo = alo + blo
                local carry = 0
                if lo >= 4294967296 then
                        lo = lo - 4294967296
                        carry = 1
                end
                return (ahi + bhi + carry) % 4294967296, lo
        end

        local function rotr64(hi, lo, n)
                local r = n % 64
                if r == 0 then
                        return hi, lo
                end
                if r >= 32 then
                        hi, lo = lo, hi
                        r = r - 32
                        if r == 0 then
                                return hi, lo
                        end
                end
                return bor(rshift(hi, r), lshift(lo, 32 - r)), bor(rshift(lo, r), lshift(hi, 32 - r))
        end

        local function shr64(hi, lo, n)
                if n == 0 then
                        return hi, lo
                end
                if n >= 32 then
                        return 0, rshift(hi, n - 32)
                end
                local nhi = rshift(hi, n)
                local nhi_bits = hi - nhi * 2 ^ n
                return nhi, bor(lshift(nhi_bits, 32 - n), rshift(lo, n))
        end

        local function sha512(msg)
                local hh, hl = {}, {}
                for i = 1, 8 do
                        hh[i], hl[i] = H512HI[i], H512LO[i]
                end
                local len = #msg
                local bitlen = len * 8
                local pad = 128 - ((len + 17) % 128)
                if pad == 128 then
                        pad = 0
                end
                local blo = bitlen % 2 ^ 64
                local bl2hi = floor(blo / 2 ^ 32)
                local bl2lo = blo % 2 ^ 32
                local tail = "\128" .. string.rep("\0", pad) .. string.rep("\0", 8)
                        .. string.char(
                                floor(bl2hi / 2 ^ 24) % 256, floor(bl2hi / 2 ^ 16) % 256, floor(bl2hi / 2 ^ 8) % 256, bl2hi % 256,
                                floor(bl2lo / 2 ^ 24) % 256, floor(bl2lo / 2 ^ 16) % 256, floor(bl2lo / 2 ^ 8) % 256, bl2lo % 256)

                local whi, wlo = {}, {}
                local block = msg .. tail
                local pos = 1
                while pos <= #block do
                        for i = 0, 15 do
                                local o = pos + i * 8
                                whi[i + 1] = block:byte(o) * 2 ^ 24 + block:byte(o + 1) * 2 ^ 16 + block:byte(o + 2) * 2 ^ 8 + block:byte(o + 3)
                                wlo[i + 1] = block:byte(o + 4) * 2 ^ 24 + block:byte(o + 5) * 2 ^ 16 + block:byte(o + 6) * 2 ^ 8 + block:byte(o + 7)
                        end
                        for i = 17, 80 do
                                local xh, xl = whi[i - 15], wlo[i - 15]
                                local a1h, a1l = rotr64(xh, xl, 1)
                                local a2h, a2l = rotr64(xh, xl, 8)
                                local a3h, a3l = shr64(xh, xl, 7)
                                local s0h = bxor(bxor(a1h, a2h), a3h)
                                local s0l = bxor(bxor(a1l, a2l), a3l)
                                local yh, yl = whi[i - 2], wlo[i - 2]
                                local b1h, b1l = rotr64(yh, yl, 19)
                                local b2h, b2l = rotr64(yh, yl, 61)
                                local b3h, b3l = shr64(yh, yl, 6)
                                local s1h = bxor(bxor(b1h, b2h), b3h)
                                local s1l = bxor(bxor(b1l, b2l), b3l)
                                local th, tl = add64(whi[i - 16], wlo[i - 16], s0h, s0l)
                                th, tl = add64(th, tl, whi[i - 7], wlo[i - 7])
                                whi[i], wlo[i] = add64(th, tl, s1h, s1l)
                        end
                        local ah, al, bh, bl, ch, cl, dh, dl, eh, el, fh, fl, gh, gl, ih, il
                        ah, al = hh[1], hl[1]
                        bh, bl = hh[2], hl[2]
                        ch, cl = hh[3], hl[3]
                        dh, dl = hh[4], hl[4]
                        eh, el = hh[5], hl[5]
                        fh, fl = hh[6], hl[6]
                        gh, gl = hh[7], hl[7]
                        ih, il = hh[8], hl[8]
                        for i = 1, 80 do
                                local r1h, r1l = rotr64(eh, el, 14)
                                local r2h, r2l = rotr64(eh, el, 18)
                                local r3h, r3l = rotr64(eh, el, 41)
                                local S1h = bxor(bxor(r1h, r2h), r3h)
                                local S1l = bxor(bxor(r1l, r2l), r3l)
                                local chh = bxor(band(eh, fh), band(bxor(eh, 4294967295), gh))
                                local chl = bxor(band(el, fl), band(bxor(el, 4294967295), gl))
                                local t1h, t1l = add64(ih, il, S1h, S1l)
                                t1h, t1l = add64(t1h, t1l, chh, chl)
                                t1h, t1l = add64(t1h, t1l, K512HI[i], K512LO[i])
                                t1h, t1l = add64(t1h, t1l, whi[i], wlo[i])
                                local q1h, q1l = rotr64(ah, al, 28)
                                local q2h, q2l = rotr64(ah, al, 34)
                                local q3h, q3l = rotr64(ah, al, 39)
                                local S0h = bxor(bxor(q1h, q2h), q3h)
                                local S0l = bxor(bxor(q1l, q2l), q3l)
                                local mjh = bxor(bxor(band(ah, bh), band(ah, ch)), band(bh, ch))
                                local mjl = bxor(bxor(band(al, bl), band(al, cl)), band(bl, cl))
                                local t2h, t2l = add64(S0h, S0l, mjh, mjl)
                                ih, il = gh, gl
                                gh, gl = fh, fl
                                fh, fl = eh, el
                                eh, el = add64(dh, dl, t1h, t1l)
                                dh, dl = ch, cl
                                ch, cl = bh, bl
                                bh, bl = ah, al
                                ah, al = add64(t1h, t1l, t2h, t2l)
                        end
                        hh[1], hl[1] = add64(hh[1], hl[1], ah, al)
                        hh[2], hl[2] = add64(hh[2], hl[2], bh, bl)
                        hh[3], hl[3] = add64(hh[3], hl[3], ch, cl)
                        hh[4], hl[4] = add64(hh[4], hl[4], dh, dl)
                        hh[5], hl[5] = add64(hh[5], hl[5], eh, el)
                        hh[6], hl[6] = add64(hh[6], hl[6], fh, fl)
                        hh[7], hl[7] = add64(hh[7], hl[7], gh, gl)
                        hh[8], hl[8] = add64(hh[8], hl[8], ih, il)
                        pos = pos + 128
                end

                local out = {}
                for i = 1, 8 do
                        local vhi, vlo = hh[i], hl[i]
                        out[#out + 1] = string.char(
                                floor(vhi / 2 ^ 24) % 256, floor(vhi / 2 ^ 16) % 256, floor(vhi / 2 ^ 8) % 256, vhi % 256,
                                floor(vlo / 2 ^ 24) % 256, floor(vlo / 2 ^ 16) % 256, floor(vlo / 2 ^ 8) % 256, vlo % 256)
                end
                return table.concat(out)
        end

        return { sha256 = sha256, sha512 = sha512 }
end

local jooax8l = function(B, sha2)
	local bxor = B.bxor

	local function hmac(hash, blocksize, key, msg)
		if #key > blocksize then
			key = hash(key)
		end
		local ipad = {}
		local opad = {}
		for i = 1, blocksize do
			local kb = 0
			if i <= #key then
				kb = key:byte(i)
			end
			ipad[i] = string.char(bxor(kb, 0x36))
			opad[i] = string.char(bxor(kb, 0x5C))
		end
		return hash(table.concat(opad) .. hash(table.concat(ipad) .. msg))
	end

	local function hmac_sha256(key, msg)
		return hmac(sha2.sha256, 64, key, msg)
	end

	local function hmac_sha512(key, msg)
		return hmac(sha2.sha512, 128, key, msg)
	end

	return { hmac_sha256 = hmac_sha256, hmac_sha512 = hmac_sha512 }
end

local t6em = function(hmac)
        local function extract(salt, ikm)
                if not salt or #salt == 0 then
                        salt = string.rep("\0", 32)
                end
                return hmac.hmac_sha256(salt, ikm)
        end

        local function expand(prk, info, length)
                if length > 255 * 32 then
                        return nil
                end
                local t = ""
                local out = {}
                local total = 0
                local n = 0
                while total < length do
                        n = n + 1
                        t = hmac.hmac_sha256(prk, t .. info .. string.char(n))
                        out[#out + 1] = t
                        total = total + #t
                end
                return table.concat(out):sub(1, length)
        end

        local function hkdf_sha256(ikm, salt, info, length)
                return expand(extract(salt, ikm), info, length)
        end

        return { extract = extract, expand = expand, hkdf_sha256 = hkdf_sha256 }
end

local N4g = function(B)
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

local F9g = function(B)
        local band, bor = B.band, B.bor
        local rshift, lshift = B.rshift, B.lshift
        local floor = math.floor

        local PLIMB = { [0] = 0xFFFB, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0x0003 }
        local RMASK = { [0] = 0xFFFF, 0x0FFF, 0xFFFC, 0x0FFF, 0xFFFC, 0x0FFF, 0xFFFC, 0x0FFF }

        local function ge(a, b)
                for i = 8, 0, -1 do
                        local av = a[i] or 0
                        local bv = b[i] or 0
                        if av ~= bv then
                                return av > bv
                        end
                end
                return true
        end

        local function sub_inplace(a, b)
                local borrow = 0
                for i = 0, 8 do
                        local v = a[i] - b[i] - borrow
                        if v < 0 then
                                v = v + 65536
                                borrow = 1
                        else
                                borrow = 0
                        end
                        a[i] = v
                end
        end

        local function fold130(a)
                local out = {}
                local carry = 0
                for i = 0, 8 do
                        local low = a[i]
                        if i == 8 then
                                low = band(low, 3)
                        end
                        local hi5 = 0
                        if i < 8 then
                                local lo = a[8 + i] or 0
                                local hi = a[9 + i] or 0
                                hi5 = 5 * band(bor(rshift(lo, 2), lshift(hi, 14)), 0xFFFF)
                        end
                        local v = low + hi5 + carry
                        out[i] = v % 65536
                        carry = floor(v / 65536)
                end
                for i = 0, 8 do
                        a[i] = out[i]
                end
                for i = 9, 17 do
                        a[i] = 0
                end
        end

        local function reduce_p(a)
                fold130(a)
                fold130(a)
                while ge(a, PLIMB) do
                        sub_inplace(a, PLIMB)
                end
        end

        local function mac(key, msg)
                local r = {}
                for i = 0, 7 do
                        r[i] = bor(key:byte(2 * i + 1), lshift(key:byte(2 * i + 2), 8))
                        r[i] = band(r[i], RMASK[i])
                end
                r[8] = 0

                local acc = {}
                for i = 0, 8 do
                        acc[i] = 0
                end

                local len = #msg
                local pos = 1
                while pos <= len do
                        local take = len - pos + 1
                        if take > 16 then
                                take = 16
                        end
                        local block = {}
                        for i = 0, 8 do
                                block[i] = 0
                        end
                        for i = 0, take - 1 do
                                local li = floor(i / 2)
                                local bi = (i % 2) * 8
                                block[li] = block[li] + lshift(msg:byte(pos + i), bi)
                        end
                        block[floor(take / 2)] = block[floor(take / 2)] + 2 ^ ((take % 2) * 8)
                        local carry = 0
                        for i = 0, 8 do
                                local v = block[i] + acc[i] + carry
                                block[i] = v % 65536
                                carry = floor(v / 65536)
                        end
                        if carry > 0 then
                                block[8] = block[8] + carry
                        end

                        local prod = {}
                        for i = 0, 17 do
                                prod[i] = 0
                        end
                        for i = 0, 8 do
                                local bi = block[i]
                                if bi ~= 0 then
                                        for j = 0, 8 do
                                                local rj = r[j]
                                                if rj ~= 0 then
                                                        prod[i + j] = prod[i + j] + bi * rj
                                                end
                                        end
                                end
                        end
                        for i = 0, 16 do
                                local v = prod[i]
                                prod[i] = v % 65536
                                prod[i + 1] = prod[i + 1] + floor(v / 65536)
                        end
                        reduce_p(prod)
                        acc = prod
                        pos = pos + 16
                end

                reduce_p(acc)
                local out = {}
                local carry = 0
                for i = 0, 7 do
                        local v = acc[i] + key:byte(17 + 2 * i) + lshift(key:byte(18 + 2 * i), 8) + carry
                        out[i] = v % 65536
                        carry = floor(v / 65536)
                end
                local bytes = {}
                for i = 0, 7 do
                        bytes[#bytes + 1] = string.char(band(out[i], 255), rshift(out[i], 8))
                end
                return table.concat(bytes)
        end

        return { mac = mac }
end

local v70mjvv = function(B, chacha20, poly1305)
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

local irc = function(B)
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

local H24v = ie0dt()
local Nsxpkvx = O6t(H24v)
local yxu8 = jooax8l(H24v, Nsxpkvx)
local bjgucm1 = t6em(yxu8)
local Kscolyi = N4g(H24v)
local Qr2lgg = F9g(H24v)
local r0k08 = v70mjvv(H24v, Kscolyi, Qr2lgg)
local Bg9 = irc(H24v)

local _q0s = -39088
local _q1z = 63767
local _q2o = 5
if _q2o % 9 == 0 then local _q2w = 0x8f end

local d0ii = H24v.band
local fak1y8 = math.floor
local c1rcgm = math.huge
local fqi5hh = type
local da2sx = getmetatable
local myfew70 = math.tointeger
local w6a9n = tonumber
local Az2 = table.pack or function(...) return { n = select("#", ...), ... } end
local Kga8g6 = table.unpack or unpack
local ar0hd3 = { n = 0 }
local function Zm9() error("load failed", 0) end

local function Tzfka(h)
	h = (h:gsub("\n", ""))
	local o = {}
	local n = #h
	local k = 0
	for i = 1, n, 2 do
		k = k + 1
		o[k] = string.char(w6a9n(h:sub(i, i + 1), 16) or 0)
	end
	return table.concat(o)
end

local function S6s3(fmt, ...)
	if fqi5hh(fmt) ~= "string" then return string.format(fmt, ...) end
	if fmt:find("%*", 1, true) == nil then return string.format(fmt, ...) end
	local na = { n = select("#", ...), ... }
	local out = {}
	local a2 = {}
	local n2 = 0
	local ai = 1
	local i = 1
	local len = #fmt
	while i <= len do
		local c = fmt:byte(i)
		if c == 37 and i < len and fmt:byte(i + 1) == 42 then
			out[#out + 1] = tostring(na[ai])
			ai = ai + 1
			i = i + 2
		elseif c == 37 and i < len then
			out[#out + 1] = fmt:sub(i, i + 1)
			i = i + 2
		else
			out[#out + 1] = fmt:sub(i, i)
			i = i + 1
		end
	end
	for k = ai, na.n do
		n2 = n2 + 1
		a2[n2] = na[k]
	end
	return string.format(table.concat(out), Kga8g6(a2, 1, n2))
end
local Nx1p = setmetatable({ format = S6s3 }, { __index = string })

local _q0s = -31967
local _q1s = 2457
local _q2z = 58115

local D6gp =
"\045\231\044\087\136\083\041\130\140\150\077\049\058\252\088\152\056\225\154\031\160\016\252\101\216\013\106\152\139\047\044\079"
local Yd1a5oq =
Tzfka([[4c505642012de72c57885329828c964d313afc589838e19a1fa010fc65d80d6a988b2f2c4f1400340194040d0100002d010100000000801f020000140001001f010000140000001201010011020100210301000b02020112020200120303002a
0400000307010003053c00030601001b05050011090400110a0800140b0100100b090a0005fbff110504000306010014070000100705060307020003053c00030601001b051c00110a0400110b08001c090a0b370901001f160000110a080011
0b08003c090a0b110b0900030c3c003b0b01000c0000001f020000140a01001f010000140a0000370a01001f090000110a0400110b0900140c0000100c0a0b110b0900110c0800180a0b0c11090a001feeffff1f0000000005e4ff2a05000003
08010003063c00030701001b060d00110b0400110c09001c0a0b0c370a01001f070000110a0500110d05000f0c0d00320b0c02110c0900100c0a0b1f0000000006f3ff0d0603000d08040019070800050000002108060011090200030a16000b
090202110a0300030b2f04030cce010b0a03000b0700000b0600010d06030021080700030a3c00210c08000d0e0900190d0e000a000000110e0500210f0b000b0d03020a0b0c0d0a090a0b0a0708090b0602012a06040021070c0021080d0021
090e00210a0f0024060400000000000d070300210910000d0b0400190a0b00110000000d0c0900190b0c000a000000110c0600210d12000b0b03000b0a00020a08090a0b0702010d080400190708001300000021081400030901000b0703020d
090400190809001300000021091400030a02000b0803020d0a040019090a0013000000210a1400030b03000b0903020d0a0300210c1500110e070021100b001112080021140b00111509000a1314150a1112130a0f10110a0d0e0f0a0b0c0d0b
0a02010d0a0300210c16000d0e0400190d0e0017000000030e4c00030f50000310560003114d000b0d05020a0b0c0d0b0a02010d0a0300210c18000d0e0400190d0e0019000000210e1a000b0d02020a0b0c0d0b0a02010d0a03000d0c040019
0b0c0005000000210c1b000d0f1d00190e0f001e000000220d0e1c030e2a00210f1f00211020000b0b06000b0a00010d0a0300210c21000d0d22000d0f0400190e0f0023000000210f24002110250003110100141201000b0e05000b0d00020a
0b0c0d0b0a0201120a0400110b0a00030c0000030d03000b0b0302110c0a00030d6400030f0700090e0f000b0c03022a0d000003100100030e0500030f01001b0e0b0011120d001113110011150b000b1501022117260011180c000b1801020a
1617180a14151610141213000ef5ff0d0e0300211027000d120900191112000a00000011120d00211328000b1103020a0f10110b0e0201120e0600110f0e000b0f010311110f000b11010111110f000b11010111110f000b1101010d11030021
132900111410000b1401020a1213140b1102012a11000011121100111311001a1312002a00000011121100121309001a1312002b0000001112110012130a001a1312002c0000001112110012130b001a1312002d0000001112110012130c001a
1312002e00000011141100191314002d00000003140300031504000b13030211151100191415002d00000003150100031601000b140302181213140d132200111412000b1302020d150400191415000500000021152f00111712002b1617002e
0000000b1602000b1400020d1503002117300011191300211b3100111c14000a1a1b1c0a18191a0a1617180b15020112150d001116150003170a000318140003191e00031a28000b1605030d1803000d1a040019191a0005000000211a320011
1b1600111c17000b1904000b1800010d18330012190e000b1802030d1a3300121b0f000b1a02030d1c2200111d18000b1c02020d1d2200111e19000b1d02020d1e03002120340011221c002124350011251d000a2324250a2122230a1f20210b
1e02010d1e2200111f1a000b1e02020d1f03002121360011231e002125370011261b000a2425260a2223240a2021220b1f02012a1f05000320050003210300032209000323010003240700241f0500000000000d210900192021003800000011
211f000b2002010d200300212239000d240900192324000a00000011241f0021250b000b2303020a2122230b2002010d211d00192021003a00000003210300032207000b2003020d221d00192122003b00000003220300032307000b2103020d
231d00192223003c00000021233d000b2202020d241d00192324003e00000003250500092425000b2302020d24030021263f0011282000212a0b00112c2100212e0b001130220021320b00113323000a3132330a2f30310a2d2e2f0a2b2c2d0a
292a2b0a2728290a2526270b24020111240000372401001f71000011240100212540000b2402010d243300122510000b24020311262400112725003f262627372601001f1e00000d263300122711000b26020311282600112927003f28282937
2801001f1200000d282200112a270019292a00410000000b2802020d292200112b2700192a2b00420000000b2902020d2a0300212c4300112e280021304400113129000a2f30310a2d2e2f0a2b2c2d0b2a02011f0300000d280300212945000b
2802011f0000000d263300122712000b26020311282600112927003f282829372801001f150000032800000d294600112b27002b2a2b00470000000b2a02000b29000408290700112e2d00372e01001f040000112f2800322e2f0211282e001f
0000002f29f8ff020000000d290300212b4800112c28000a2a2b2c0b2902011f0000000d280300212a49000d2b22000d2d0000192c2d004a0000000b2b02020a292a2b0b2802010d283300122913000b2802020d290300212b4b000d2c220011
2d28000b2c02020a2a2b2c0b290201032b010003290300032a01001b2913000d2d4c000d2f4c00192e2f004d0000003f2d2d2e372d01001f0500000d2e4c00192d2e004d000000032e01000b2d02011f0000000d2d0300212f4e0011312c0021
324f000a3031320a2e2f300b2d02010029edff272400001f12000011240100212550000b2402010d240300212551000b2402010326010003240300032501001b2408000d280300212a4e00112c2700212d4f000a2b2c2d0a292a2b0b28020100
24f8ff11240100212552000b24020127000000330000000500020000010500150d0100000d03010019020300020000002103030003042e000b0203000b0100010d01000021030400110400000a0203040b0102010d0100000d03010019020300
020000002103030003042e000b0203000b01000133010000050102000001060018110200000303020036020100030000001f020000140101001f01000014010000370101001f03000011010000050102001f0000000202000011040000230304
000b0202020203000011050000230405010b03020218010203050102003301000005010200010102020700141103010034030100000000001f020000140201001f01000014020000370201001f03000011020000050202001f00000002020000
1103010011050000110601002e0405060b02030005020000330200000502020001010302040006110200001203050005030200270200003302000005020200000003000802010000020201001800010201000000020000000500020033000000
050002000201020101000500090300000012010700120208001103010011040200050303002700000033000000050002000000020007020100003200010001000000020000000500020033000000050002000101000002000402000000050002
0033000000050002000101000208001002030000190203000000000011050000190405000100000011060100190506000100000018030405110600001905060002000000110701001906070002000000180405060b0203000502000033020000
05020200010111010b000e2102000011060000190406000100000021060200110a000019080a0003000000210904000a0708090a0506070a0304050a010203050102003301000005010200000205000b0d0200002a030002110400001a040300
01000000110401001a04030002000000020400000b020300050200003302000005020200010111010800110d02000019010200010000001105000019040500020000001106000019050600020000003c03040511060000190506000300000011
07000019060700030000003c040506180203040b01020005010000330100000501020000000b01160d00000021010100130200000b000002030100000304010011020000030301001b020800110701000d08000011090500130a00000b080002
18060708110106000002f8ff110200001103010005020300330000000500020000000300060d00000021010100030200000b000301330000000500020000000200042100000005000200330000000500020000000300070d0100002b00010001
000000210202000b0003000500000033000000050002000000020005020100001900010000000000050002003300000005000200010125000300070d0100002b00010001000000210202000b0003000500000033000000050002000000050010
0d0200002b01020001000000210302000b0103022b00010003000000210204002a030003210406001a04030005000000210408001a04030007000000030406001a040300090000000b000401330000000500020000e006e9f2dd570fd4379232
9c70964d14b845f114fd407689984d31cae3eca0909b0ccb3525336ed7e1ac811b683fc3d278520db4f7d6b6e34b6ef83b2f1aa4b574fba6f03d3993cae6d6554c17bd635c7721d871e2e01823c9de0d1bad5c0009c1c0d022e33baa0677ad8c
42b482ed16d66a36538931da8170995dcebb6059b0a7459b1dba694367d1ebdadef96567f704c16d8dc99d7164d91e40e4107935eb8c08a1ef627dad9ab01a6c0f21ea2a580040704c88c07faab7242a9fcb35d30afb264092becb304552dcf2
8de0a1551006e6753ffd308d583f2fa7c4dc15ab993405ad445b9d10cfc7ecf28e800ade495491a4145b658065af7a373371ec0fa36306fb1f4f0ec41db5f4a450d8a1ce8e05583e0d0331c3b248d85d996635e959ec4b4a46a246b890ed715a
496d761e7d381251668528c712a80ccdcd662ae0b86453ff77f415b45d6e4072d3615668d985bd6c92906ff2c6902852eeff9e82f3703b6d69d23d631db17fabde3a3809a470e1118bb6a792bbffcc7cad2ad3737c34e18bff831f6fc7addcf1
5ca305e69dbafc06372de28f71f369ea0b64364d8e8802f1e92142cb678cc49b01583a48b37d3de5f8c89b81ebf25f778f5881ae599b094c1a5b7533f9bd312d2a986b8a0dfd030e67baf02d76bdf599df4144ccb8bd058594b73eb8e57452be
d4b0c1712e94b9496b938fef43910ead95f7e1bcd3ec94aaa99b57671a6b3d9d7059cec49bcaaf66e7d47850b93a8ae1215482da004d5abf8c1718afca612444d0c56a156163432f47c3a3201fbee66486f7f501f6068b3a7abc26f68be0a254
70e3ae58305b284a6091c27c65f83ab69ce2e87950844e44612547c203e8a028b2a06dc1d880ef7c247aa514e8afc748cd546b914a10aedd6210e8b3348e02db61a9a5d9a7b84fbd9cafaae1b537ab8b755a22f7cf7921163e7f0b0a8182cbda
c0f2f2fc72e4fdb1867c3e9ca521a707c7f41f03502c772308c47969f08214491691dce7f50667d563a58e8f58f000e6b60b18449dcae9f9979f6bad3f55d28122cc1276daa58d024753f6f922cd3d981cbc13ba50465e8edddf968e86cdec25
0778dcd6704d00c52bb75a5d5d35e1de46d0f316bf2e0b6200d59b93c943ac3e9fe2fd3e000dd21a5196961502726e5f8b1c80dd478b4b84001330b0d1dd98a2e5f2b1065423e567765bcf2ba958efe9a66ff7221dcc50a4a76621e84ba0c004
e5ea59cfe5f4f3026ea0ccfcce1648eeacb8de1c36e8dcc2de7b6dff5752b33212ad2bea7cb67239ffa04e2e85f7de7f3eeb5835d6655d0d994cff6f8b2ca0674b830b7bdb880954b55356e513ce2eab043c8d278d7cc8b18fa8a0a075e818b0
f29827620792353f72e0238d7fda1c9edd6e344988e5980bc9ac681a0af9142ecccc49be8905d761ba419af18654f05c0afb64f36cdaa3f0058307c25f13151d7902c50175295385cf4f2b2b4f18fcbc3a84b2ea1b083097538e0d7ff64f2491
af01c55ef4d4d968cb35b48502011de8117c0cd120747d1e471225f9b117eb0133de4de421097cecf5f5bc5fb21285c3d163a0b68f1860d85a15dba7a40a786a312a97a51a418df377f58f7114dc90cb5d847dfe6e5e975b360acba6231f3024
4c6eed2b017f6857205ca5a1ea68eb111eae13e5656d14034f81aa9351cc2b28b4030ce629a75e027a623ac6f22b74222fab2174377079d34209092525257df98fced2e0b2933bd6a5dce71097c246925d4e2563cf679baab6894719b073e72e
122d1bd25bd051d69205bc9e44798fdd2eca953a8c16909715775d4f14c856d7469a87ce69a9701c05948614c8fcdc1e6b4c0a503a2897099b86e71ed3f2dd57a3fe2c4ff627868f6f9513a6d040ba99cd02ff3022616e64311e7832e7f1395e
21b8a3e4955414cd14bf0045fd61c6074f3fb72ebbeaa69d49da0c2526c7731d963ad7f8e9d971ce3fb0020db1c94f18c8ee3ae73f2acf166d2d95d0b68ee4fe9467c91439f890fe5f68809864838534935459b543b5d5b1c8692ba5bf430400
46cc4db327408d32b641b00cc200de431e6eda770cca18abe646e65307deffc820517e9ba8476d130ede4dcf7c3a0a7b4b387b6256d5873835b41c2d3f1c5382dfee178ff455e81f3a13220098f6b9f8c0266147dcaf81554121177f4b1b0c6f
06e2c70abbef55d855df4ea4e0ff24c6a15521ea20710ec146fea1b8a57b398b6f6386e40a6b6a0deb84eb7cb27533333a69b68d31d685f53bbecb920adb6e32661e053fb2ea7a755077e8246377e00b4a2ce4182802da14d3704bc86b021500
74d9eeb188d2ec230ce3484f63d9f789e6f7f29e5dc5e3c3b3668fb577647fabca59afea232935ede8f168c4a3c3b7ff633a1bac35338ee4ab05aae577e69936ba14c1c37da63f24130bfa421002be66b5538d1929e3f7f9a70456392d43706c
169f03aa628d1f98bcd027b616b4970b7853b22e8ccf5c4826076f02f1803d90d92f55477422b01fe83cd47ff55a1913f6e0a5c80e331f643d8dc6d08955c6ed52a0ee6abba86fd9952d99a020cdcbb4d61b94f7]])
local m31u6n = {[1] = 0x36, [2] = 10, [3] = 9, [4] = 3, [6] = 0x32, [7] = 0x16, [9] = 55, [10] = 0x25, [11] = 35, [12] = 0x31, [13] = 30, [14] = 7, [15] = 41, [16] = 0x26, [17] = 14, [18] = 6, [19] = 0x34, [20] = 51, [21] = 2, [23] = 20, [24] = 0x2a, [25] = 0x13, [26] = 13, [27] = 15, [28] = 0x35, [29] = 12, [30] = 25, [31] = 17, [32] = 39, [33] = 34, [34] = 4, [35] = 28, [36] = 27, [37] = 57, [39] = 48, [40] = 11, [42] = 5, [43] = 16, [44] = 18, [45] = 0, [46] = 45, [47] = 0x17, [48] = 0x38, [49] = 8, [50] = 46, [51] = 26, [52] = 1, [53] = 0x2f, [55] = 43, [56] = 0x28, [57] = 32, [58] = 0x1d, [59] = 0x1f, [60] = 44, [61] = 0x15, [62] = 24, [63] = 36, [64] = 0x21}

local tpo85d9 = {[0] = 2, [1] = 1, [2] = 0, [3] = 1, [4] = 1, [5] = 1, [6] = 0, [7] = 1, [8] = 1, [9] = 0, [10] = 0, [11] = 1, [12] = 0, [13] = 0, [14] = 0, [15] = 0, [16] = 0, [17] = 0, [18] = 0, [19] = 0, [20] = 0, [21] = 0, [22] = 0, [23] = 0, [24] = 0, [25] = 0, [26] = 0, [27] = 0, [28] = 0, [29] = 0, [30] = 0, [31] = 0, [32] = 0, [33] = 0, [34] = 0, [35] = 0, [36] = 0, [37] = 0, [38] = 0, [39] = 2, [40] = 1, [41] = 1, [42] = 1, [43] = 1, [44] = 1, [45] = 1, [46] = 1, [47] = 1, [48] = 1, [49] = 0, [50] = 0, [51] = 0, [52] = 1, [53] = 1, [54] = 1, [55] = 1, [56] = 1, [57] = 0}

local Yfdqa = {[5] = true, [13] = true, [15] = true, [18] = true, [42] = true, [43] = true, [44] = true, [45] = true, [46] = true, [47] = true, [48] = true, [56] = true, [57] = true}



local function Omw(s, i)
	local r = 0
	local sh = 0
	while true do
		local b = s:byte(i)
		if b == nil then Zm9() end
		i = i + 1
		r = r + (b % 128) * 2 ^ sh
		if b < 128 then return r, i end
		sh = sh + 7
	end
end

local function M69(s, i)
	local b1, b2, b3, b4, b5, b6, b7, b8 = s:byte(i, i + 7)
	local lo = b1 + b2 * 256 + b3 * 65536 + b4 * 16777216
	local hi = b5 + b6 * 256 + b7 * 65536 + b8 * 16777216
	local t = fak1y8(hi / 1048576)
	local e = t % 2048
	local m = (hi % 1048576) * 4294967296 + lo
	local v
	if e == 2047 then
		if m == 0 then
			if t >= 2048 then v = -c1rcgm else v = c1rcgm end
		else
			v = 0 / 0
		end
	elseif e == 0 then
		v = m * 2 ^ -1074
	else
		v = (4503599627370496 + m) * 2 ^ (e - 1075)
	end
	if t >= 2048 then v = -v end
	if myfew70 ~= nil then
		local iv = myfew70(v)
		if iv ~= nil then return iv end
	end
	return v
end

local function e8f5(n)
	return string.char(fak1y8(n / 16777216) % 256, fak1y8(n / 65536) % 256, fak1y8(n / 256) % 256, n % 256)
end



local function Boes9y()
	local s = Yd1a5oq
	if s:byte(1) ~= 76 or s:byte(2) ~= 80 or s:byte(3) ~= 86 or s:byte(4) ~= 66 then Zm9() end
	if s:byte(5) ~= 1 then Zm9() end
	local fcount, i = Omw(s, 38)
	local i0 = i
	local aadh = s:sub(1, 5) .. s:sub(38, i0 - 1)
	local protos = {}
	local poofs = {}
	local poofl = {}
	for f = 1, fcount do
		local np, mr
		np, i = Omw(s, i)
		mr, i = Omw(s, i)
		local flags = s:byte(i)
		i = i + 1
		local ninst
		ninst, i = Omw(s, i)
		local code = {}
		for k = 1, ninst do
			local w1, w2, w3, w4 = s:byte(i, i + 3)
			if w1 == nil or w2 == nil or w3 == nil or w4 == nil then Zm9() end
			local w = w1 + w2 * 256 + w3 * 65536 + w4 * 16777216
			i = i + 4
			local canon = m31u6n[w % 256 + 1]
			if canon == nil then Zm9() end
			local sh = tpo85d9[canon]
			local ins = { canon, fak1y8(w / 256) % 256, 0, 0, 0, 0 }
			if sh == 0 then
				ins[3] = fak1y8(w / 65536) % 256
				ins[4] = fak1y8(w / 16777216) % 256
			elseif sh == 1 then
				local d = fak1y8(w / 65536)
				if d >= 32768 then d = d - 65536 end
				ins[5] = d
			else
				local d = fak1y8(w / 256)
				if d >= 8388608 then d = d - 16777216 end
				ins[5] = d
			end
			if Yfdqa[canon] then
				local a1, a2, a3, a4 = s:byte(i, i + 3)
				if a1 == nil or a2 == nil or a3 == nil or a4 == nil then Zm9() end
				ins[6] = a1 + a2 * 256 + a3 * 65536 + a4 * 16777216
				i = i + 4
			end
			code[k] = ins
		end
		local nup
		nup, i = Omw(s, i)
		local upv = {}
		for k = 1, nup do
				local kd = s:byte(i)
				i = i + 1
				local src
				src, i = Omw(s, i)
				upv[k] = { kd, src }
		end
		protos[f] = { np = np, mr = mr, isv = flags % 2 == 1, code = code, upv = upv, f = f, ks = nil }
	end
	local fnsEnd = i - 1
	for f = 1, fcount do
		local cl
		cl, i = Omw(s, i)
		poofs[f] = i + 12
		poofl[f] = cl
		i = i + 12 + cl + 16
	end
	local aads = aadh .. Nsxpkvx.sha256(s:sub(i0, fnsEnd))
	return protos, poofs, poofl, aads
end



local function ons5(P)
	local f = P.f
	local key = Oo3t[f]
	if key == nil then
		local i = Oo3t.w
		while i < f do
			Oo3t[i + 1] = bjgucm1.hkdf_sha256(Oo3t[i], e8f5(i), "const-key", 32)
			i = i + 1
		end
		Oo3t.w = f
		key = Oo3t[f]
	end
	local off = api2i5[f]
	local cl = cc15[f]
	local pt = r0k08.open(key, Yd1a5oq:sub(off - 12, off - 1), C1j, Yd1a5oq:sub(off, off + cl + 15))
	if pt == nil then Zm9() end
	local n, j = Omw(pt, 1)
	local cs = {}
	for k = 1, n do
		local tg = pt:byte(j)
		j = j + 1
		if tg == 1 then
			cs[k] = pt:byte(j) ~= 0
			j = j + 1
		elseif tg == 2 then
			cs[k] = M69(pt, j)
			j = j + 8
		else
			local ln
			ln, j = Omw(pt, j)
			cs[k] = pt:sub(j, j + ln - 1)
			j = j + ln
		end
	end
	P.ks = cs
	return cs
end
local function oq25(P, idx)
	local cs = P.ks
	if cs == nil then cs = ons5(P) end
	return cs[idx + 1]
end



local function Y45c(c) if c[1] == 1 then return c[2].R[c[3] + 1] end return c[2] end
local function M5q(c, v) if c[1] == 1 then c[2].R[c[3] + 1] = v else c[2] = v end end
local function Idis(c) if c[1] == 1 then c[2] = c[2].R[c[3] + 1] c[1] = 0 end end
local function gmtwy43(fr, a)
	local oc = fr.oc
	local w = 0
	for i = 1, #oc do
		local c = oc[i]
		if c[3] < a then
			w = w + 1
			oc[w] = c
		else
			Idis(c)
			fr.uv[c[3]] = nil
		end
	end
	for i = #oc, w + 1, -1 do oc[i] = nil end
end

local _q0z = 2204

local v3j948 = setmetatable({}, { __mode = "k" })
local function Sewajl(rec)
	local f = function(...)
		local r = Lg500d(rec, Az2(...))
		return Kga8g6(r, 1, r.n)
	end
	v3j948[f] = rec
	return f
end
Kob2a = function(f, ap)
	local rec = v3j948[f]
	if rec ~= nil then return Lg500d(rec, ap) end
	return Az2(f(Kga8g6(ap, 1, ap.n)))
end

local _q0o = 1
if _q0o % 12 == 5 then local _q0w = 152 end
local _q1s = -17283

local hD1 = function(fr, I, rec, pcb)
	M5q(rec.u[I[3] + 1], fr.R[I[2] + 1])
end
local hD2 = function(fr, I, rec, pcb)
	local x = fr.R[I[3] + 1]
	local y = oq25(fr.P, I[4])
	if fqi5hh(x) == "number" and fqi5hh(y) == "number" then
	  if y ~= 0 then fr.R[I[2] + 1] = fak1y8(x / y)
	  elseif x == 0 then fr.R[I[2] + 1] = 0 / 0
	  elseif x > 0 then fr.R[I[2] + 1] = c1rcgm
	  else fr.R[I[2] + 1] = -c1rcgm end
	else
	  local m = da2sx(x)
	  if m ~= nil then m = m.__idiv end
	  if m == nil then
	    m = da2sx(y)
	    if m ~= nil then m = m.__idiv end
	  end
	  if m == nil then Zm9() end
	  fr.R[I[2] + 1] = Kob2a(m, Az2(x, y))[1]
	end
end
local hD3 = function(fr, I, rec, pcb)
	fr.R[I[2] + 1] = I[3] ~= 0
end
local hD4 = function(fr, I, rec, pcb)
	fr.R[I[2] + 1] = oq25(fr.P, I[5])
end
local hD5 = function(fr, I, rec, pcb)
	if fr.R[I[2] + 1] ~= nil and fr.R[I[2] + 1] ~= false then pcb[1] = pcb[1] + I[5] end
end
local hD6 = function(fr, I, rec, pcb)
	if fr.R[I[2] + 1] <= fr.R[I[6] + 1] then pcb[1] = pcb[1] + I[5] end
end
local hD7 = function(fr, I, rec, pcb)
	gmtwy43(fr, I[2])
end
local hD8 = function(fr, I, rec, pcb)
	local a = I[2]
	local b = I[3]
	local aux = I[6]
	local t = fr.R[a + 1]
	local n
	if b == 0 then n = fr.top - a - 1 else n = b end
	for k = 1, n do t[aux + k] = fr.R[a + 1 + k] end
end
local hD9 = function(fr, I, rec, pcb)
	fr.R[I[2] + 1] = fr.R[I[3] + 1] % oq25(fr.P, I[4])
end
local hD10 = function(fr, I, rec, pcb)
	local a = I[2]
	local st = fr.R[a + 2]
	local ix = fr.R[a + 3] + st
	fr.R[a + 3] = ix
	local lim = fr.R[a + 1]
	local cont
	if st > 0 then cont = ix <= lim
	elseif st < 0 then cont = ix >= lim
	else cont = true end
	if cont then
	  fr.R[a + 4] = ix
	  pcb[1] = pcb[1] + I[5]
	end
end
local hD11 = function(fr, I, rec, pcb)
	pcb[1] = pcb[1] + I[5]
end
local hD12 = function(fr, I, rec, pcb)
	local a = I[2]
	local lim = fr.R[a + 1]
	local st = fr.R[a + 2]
	local ix = fr.R[a + 3]
	fr.R[a + 4] = ix
	local cont
	if st > 0 then cont = ix <= lim
	elseif st < 0 then cont = ix >= lim
	else cont = true end
	if not cont then pcb[1] = pcb[1] + I[5] end
end
local hD13 = function(fr, I, rec, pcb)
	fr.R[I[2] + 1] = fr.R[I[3] + 1] - oq25(fr.P, I[4])
end
local hD14 = function(fr, I, rec, pcb)
	local acc = fr.R[I[4] + 1]
	for k = I[4] - 1, I[3], -1 do acc = fr.R[k + 1] .. acc end
	fr.R[I[2] + 1] = acc
end
local hD15 = function(fr, I, rec, pcb)
	local aux = I[6]
	if (fr.R[I[2] + 1] == fr.R[d0ii(aux, 2147483647) + 1]) ~= (aux >= 2147483648) then pcb[1] = pcb[1] + I[5] end
end
local hD16 = function(fr, I, rec, pcb)
	fr.R[I[2] + 1] = fr.R[I[3] + 1] + oq25(fr.P, I[4])
end
local hD17 = function(fr, I, rec, pcb)
	fr.env[oq25(fr.P, I[5])] = fr.R[I[2] + 1]
end
local hD18 = function(fr, I, rec, pcb)
	local x = fr.R[I[3] + 1]
	local y = fr.R[I[4] + 1]
	if fqi5hh(x) == "number" and fqi5hh(y) == "number" then
	  if y ~= 0 then fr.R[I[2] + 1] = fak1y8(x / y)
	  elseif x == 0 then fr.R[I[2] + 1] = 0 / 0
	  elseif x > 0 then fr.R[I[2] + 1] = c1rcgm
	  else fr.R[I[2] + 1] = -c1rcgm end
	else
	  local m = da2sx(x)
	  if m ~= nil then m = m.__idiv end
	  if m == nil then
	    m = da2sx(y)
	    if m ~= nil then m = m.__idiv end
	  end
	  if m == nil then Zm9() end
	  fr.R[I[2] + 1] = Kob2a(m, Az2(x, y))[1]
	end
end
local hD19 = function(fr, I, rec, pcb)
	local a = I[2]
	local b = I[3]
	local va = fr.va
	if b == 0 then
	  for k = 1, va.n do fr.R[a + k] = va[k] end
	  fr.top = a + va.n
	else
	  local n = b - 1
	  for k = 1, n do fr.R[a + k] = va[k] end
	end
end
local hD20 = function(fr, I, rec, pcb)
	fr.R[I[2] + 1] = fr.R[I[3] + 1][oq25(fr.P, I[6])]
end
local hD21 = function(fr, I, rec, pcb)
	local a = I[2]
	local g = fr.R[a + 1]
	if fqi5hh(g) == "table" then
	  local m = da2sx(g)
	  local it = nil
	  if m ~= nil then it = m.__iter end
	  if it ~= nil then
	    local ap = { g, fr.R[a + 2] }
	    ap.n = 2
	    local r2 = Kob2a(it, ap)
	    fr.R[a + 1] = r2[1]
	    fr.R[a + 2] = r2[2]
	    fr.R[a + 3] = r2[3]
	  else
	    fr.R[a + 1] = fr.env.next
	    fr.R[a + 2] = g
	    fr.R[a + 3] = nil
	  end
	end
	pcb[1] = pcb[1] + I[5]
end
local hD22 = function(fr, I, rec, pcb)
	fr.R[I[2] + 1] = I[5]
end
local hD23 = function(fr, I, rec, pcb)
	if fr.R[I[2] + 1] < fr.R[I[6] + 1] then pcb[1] = pcb[1] + I[5] end
end
local hD24 = function(fr, I, rec, pcb)
	fr.R[I[2] + 1] = {}
end
local hD25 = function(fr, I, rec, pcb)
	fr.R[I[2] + 1] = fr.R[I[3] + 1] + fr.R[I[4] + 1]
end
local hD26 = function(fr, I, rec, pcb)
	fr.R[I[2] + 1] = fr.R[I[3] + 1] * oq25(fr.P, I[4])
end
local hD27 = function(fr, I, rec, pcb)
	if fr.R[I[2] + 1] == nil or fr.R[I[2] + 1] == false then pcb[1] = pcb[1] + I[5] end
end
local hD28 = function(fr, I, rec, pcb)
	fr.R[I[3] + 1][oq25(fr.P, I[6])] = fr.R[I[2] + 1]
end
local hD29 = function(fr, I, rec, pcb)
	local a = I[2]
	local b = I[3]
	local c = I[4]
	local n
	if b == 0 then n = fr.top - a - 1 else n = b - 1 end
	local ap = {}
	for k = 1, n do ap[k] = fr.R[a + 1 + k] end
	ap.n = n
	local res = Kob2a(fr.R[a + 1], ap)
	local rn = res.n
	if c == 0 then
	  for k = 1, rn do fr.R[a + k] = res[k] end
	  fr.top = a + rn
	else
	  local m = c - 1
	  for k = 1, m do fr.R[a + k] = res[k] end
	  fr.top = a + m
	end
end
local hD30 = function(fr, I, rec, pcb)
	fr.R[I[2] + 1] = Y45c(rec.u[I[3] + 1])
end
local hD31 = function(fr, I, rec, pcb)
	local a = I[2]
	local ap = { fr.R[a + 2], fr.R[a + 3] }
	ap.n = 2
	local res = Kob2a(fr.R[a + 1], ap)
	local f1 = res[1]
	if f1 ~= nil then
	  fr.R[a + 3] = f1
	  local nv = I[6]
	  for k = 1, nv do fr.R[a + 3 + k] = res[k] end
	  pcb[1] = pcb[1] + I[5]
	end
end
local hD32 = function(fr, I, rec, pcb)
	fr.R[I[2] + 1] = -fr.R[I[3] + 1]
end
local hD33 = function() end
local hD34 = function(fr, I, rec, pcb)
	fr.R[I[2] + 1] = fr.R[I[3] + 1] / oq25(fr.P, I[4])
end
local hD35 = function(fr, I, rec, pcb)
	fr.R[I[2] + 1] = fr.R[I[3] + 1][fr.R[I[4] + 1]]
end
local hD36 = function(fr, I, rec, pcb)
	fr.R[I[2] + 1] = #fr.R[I[3] + 1]
end
local hD37 = function(fr, I, rec, pcb)
	fr.R[I[2] + 1] = fr.R[I[3] + 1]
end
local hD38 = function(fr, I, rec, pcb)
	fr.R[I[2] + 1] = fr.env[oq25(fr.P, I[5])]
end
local hD39 = function(fr, I, rec, pcb)
	fr.R[I[3] + 1][fr.R[I[4] + 1]] = fr.R[I[2] + 1]
end
local hD40 = function(fr, I, rec, pcb)
	local v = fr.R[I[3] + 1]
	if v == nil or v == false then fr.R[I[2] + 1] = v else fr.R[I[2] + 1] = fr.R[I[4] + 1] end
end
local hD41 = function(fr, I, rec, pcb)
	local aux = I[6]
	if (fr.R[I[2] + 1] == (d0ii(I[6], 1) == 1)) ~= (aux >= 2147483648) then pcb[1] = pcb[1] + I[5] end
end
local hD42 = function(fr, I, rec, pcb)
	local t = fr.R[I[3] + 1]
	fr.R[I[2] + 2] = t
	fr.R[I[2] + 1] = t[fr.R[I[4] + 1]]
end
local hD43 = function(fr, I, rec, pcb)
	fr.R[I[2] + 1] = oq25(fr.P, I[6])
end
local hD44 = function(fr, I, rec, pcb)
	local aux = I[6]
	if (fr.R[I[2] + 1] == oq25(fr.P, d0ii(I[6], 2147483647))) ~= (aux >= 2147483648) then pcb[1] = pcb[1] + I[5] end
end
local hD45 = function(fr, I, rec, pcb)
	fr.R[I[2] + 1] = fr.R[I[3] + 1] ^ fr.R[I[4] + 1]
end
local hD46 = function(fr, I, rec, pcb)
	fr.R[I[2] + 1] = fr.R[I[3] + 1] % fr.R[I[4] + 1]
end
local hD47 = function(fr, I, rec, pcb)
	local t = fr.R[I[3] + 1]
	fr.R[I[2] + 2] = t
	fr.R[I[2] + 1] = t[oq25(fr.P, I[6])]
end
local hD48 = function(fr, I, rec, pcb)
	fr.R[I[2] + 1] = fr.R[I[3] + 1] - fr.R[I[4] + 1]
end
local hD49 = function(fr, I, rec, pcb)
	fr.R[I[2] + 1] = fr.R[I[3] + 1] ^ oq25(fr.P, I[4])
end
local hD50 = function(fr, I, rec, pcb)
	local v = fr.R[I[3] + 1]
	if v == nil or v == false then fr.R[I[2] + 1] = fr.R[I[4] + 1] else fr.R[I[2] + 1] = v end
end
local hD51 = function(fr, I, rec, pcb)
	fr.R[I[2] + 1] = nil
end
local hD52 = function(fr, I, rec, pcb)
	fr.R[I[2] + 1] = fr.R[I[3] + 1] * fr.R[I[4] + 1]
end
local hD53 = function(fr, I, rec, pcb)
	fr.R[I[2] + 1] = not fr.R[I[3] + 1]
end
local hD54 = function(fr, I, rec, pcb)
	local aux = I[6]
	if (fr.R[I[2] + 1] == nil) ~= (aux >= 2147483648) then pcb[1] = pcb[1] + I[5] end
end
local hD55 = function(fr, I, rec, pcb)
	local aux = I[6]
	if (fr.R[I[2] + 1] == oq25(fr.P, d0ii(I[6], 2147483647))) ~= (aux >= 2147483648) then pcb[1] = pcb[1] + I[5] end
end
local hD56 = function(fr, I, rec, pcb)
	local a = I[2]
	local b = I[3]
	local n
	if b == 0 then n = fr.top - a else n = b - 1 end
	local oc = fr.oc
	for k = 1, #oc do Idis(oc[k]) end
	local p = {}
	for k = 1, n do p[k] = fr.R[a + k] end
	p.n = n
	return p
end
local hD57 = function(fr, I, rec, pcb)
	local d = I[5]
	local cp = ranmf2[d + 1]
	local ds = cp.upv
	local ups = {}
	for k = 1, #ds do
	  local e = ds[k]
	  local kd = e[1]
	  if kd == 1 then
	    local cc = fr.uv[e[2]]
	    if cc == nil or cc[1] ~= 1 then
	      cc = { 1, fr, e[2] }
	      fr.uv[e[2]] = cc
	      local ocx = fr.oc
	      ocx[#ocx + 1] = cc
	    end
	    ups[k] = cc
	  elseif kd == 2 then
	    ups[k] = rec.u[e[2] + 1]
	  else
	    ups[k] = { 0, fr.R[e[2] + 1] }
	  end
	end
	fr.R[I[2] + 1] = Sewajl({ p = d + 1, u = ups, env = fr.env })
end
local hD58 = function(fr, I, rec, pcb)
	fr.R[I[2] + 1] = fr.R[I[3] + 1] / fr.R[I[4] + 1]
end
local La27 = {}
La27[48] = hD44
La27[39] = hD36
La27[31] = hD9
La27[30] = hD34
La27[12] = hD7
La27[23] = hD58
La27[19] = hD47
La27[11] = hD1
La27[49] = hD55
La27[50] = hD29
La27[28] = hD13
La27[17] = hD24
La27[20] = hD25
La27[16] = hD28
La27[18] = hD42
La27[22] = hD52
La27[37] = hD53
La27[24] = hD46
La27[54] = hD12
La27[26] = hD18
La27[8] = hD38
La27[51] = hD56
La27[33] = hD2
La27[2] = hD51
La27[58] = hD8
La27[9] = hD17
La27[21] = hD48
La27[35] = hD50
La27[46] = hD54
La27[53] = hD57
La27[4] = hD22
La27[38] = hD32
La27[5] = hD4
La27[13] = hD35
La27[34] = hD40
La27[15] = hD39
La27[6] = hD43
La27[3] = hD3
La27[7] = hD37
La27[36] = hD14
La27[44] = hD23
La27[25] = hD45
La27[1] = hD33
La27[42] = hD27
La27[56] = hD21
La27[14] = hD20
La27[45] = hD6
La27[40] = hD11
La27[57] = hD31
La27[52] = hD19
La27[41] = hD5
La27[47] = hD41
La27[10] = hD30
La27[43] = hD15
La27[29] = hD26
La27[32] = hD49
La27[27] = hD16
La27[55] = hD10
local Ecp7 = La27

local _q0z = 49749
local _q1s = -57472

Lg500d = function(rec, ap)
	local P = ranmf2[rec.p]
	local np = P.np
	local R = {}
	for k = 1, np do R[k] = ap[k] end
	local va = ar0hd3
	if P.isv then
		local m = ap.n - np
		if m > 0 then
			va = {}
			for k = 1, m do va[k] = ap[np + k] end
			va.n = m
		end
	end
	local fr = { P = P, R = R, top = np, va = va, oc = {}, uv = {}, env = rec.env }
	local pcb = { 1 }
	local code = P.code
	while true do
		local I = code[pcb[1]]
		pcb[1] = pcb[1] + 1
		local r = Ecp7[I[1] + 1](fr, I, rec, pcb)
		if r ~= nil then return r end
	end
end

local _q0o = 4
if _q0o % 8 == 0 then local _q0w = 0x54 end
local _q1s = 30041

local Sq0y9wq = function(e)
	local renv = e.env
	if renv == nil then renv = _G end
	local ENVV = setmetatable({ string = Nx1p }, { __index = renv, __newindex = function(_, k, v) rawset(renv, k, v) end })
	local ck = e.c
	local sv = e.s
	local good = fqi5hh(ck) == "string" and #ck == 32
	if good and sv ~= nil and (fqi5hh(sv) ~= "string" or #sv > 64) then good = false end
	local bh = Nsxpkvx.sha256(Yd1a5oq:sub(1, 5) .. Yd1a5oq:sub(38, #Yd1a5oq - 4))
	if bh ~= D6gp then good = false end
	if not good then
		ck = bjgucm1.hkdf_sha256(bh, bh:sub(1, 8), "const-key", 32)
	end
	Oo3t = { bjgucm1.hkdf_sha256(ck, "", "const-key", 32), w = 1 }
	local protos, poofs, poofl, aads = Boes9y()
	ranmf2 = protos
	api2i5 = poofs
	cc15 = poofl
	C1j = aads
	local ap = {}
	local aa = e.args
	local an = 0
	if aa ~= nil then
		an = e.nargs
		if an == nil then an = #aa end
		for k = 1, an do ap[k] = aa[k] end
	end
	ap.n = an
	local res = Lg500d({ p = 1, u = {}, env = ENVV }, ap)
	return Kga8g6(res, 1, res.n)
end

local _q0z = 62165
local _q1z = 31315
local _q2s = -48187

return Sq0y9wq
end)()
local ok, err = pcall(entry, {
  c = "\224\142\114\216\019\059\130\160\068\107\200\014\101\229\192\150\203\020\145\045\103\079\237\204\188\187\052\080\186\076\149\229",
  s = "lp1-standalone",
  args = {}, nargs = 0,
})
if not ok then error(err, 0) end
