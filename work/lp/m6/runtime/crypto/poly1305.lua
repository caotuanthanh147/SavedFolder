-- poly1305.lua — Poly1305 one-time authenticator (RFC 8439 §2.5).
-- Design for double-precision safety: 16-bit limbs, schoolbook multiply
-- (products < 2^33, sums < 2^37), reduction via A = low130 + 5*high
-- (2^130 == 5 mod p). No intermediate exceeds 2^53.
-- Deps: B (bit ops) for packing and masking.

return function(B)
        local band, bor = B.band, B.bor
        local rshift, lshift = B.rshift, B.lshift
        local floor = math.floor

        local PLIMB = { [0] = 0xFFFB, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0x0003 }
        -- RFC 8439 §2.5.1 clamp: r &= 0x0ffffffc0ffffffc0ffffffc0fffffff
        -- (bytewise: key[3],[7],[11],[15] &= 0x0F; key[4],[8],[12] &= 0xFC)
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

        -- a: limbs 0..17 (value < 2^272). Replaces a with
        -- (a mod 2^130) + 5 * (a >> 130), stored in a[0..8]; a[9..17] zeroed.
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
