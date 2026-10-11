-- sha2.lua — SHA-256 and SHA-512 (FIPS 180-4).
-- SHA-512 uses 64-bit words emulated as (hi, lo) 32-bit halves.
-- Deps: B (bit ops table from bit.lua).

return function(B)
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
