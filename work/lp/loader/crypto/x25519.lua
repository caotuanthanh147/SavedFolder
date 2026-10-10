-- x25519.lua — X25519 Diffie-Hellman (RFC 7748 §5).
-- Montgomery ladder with arithmetic cswap; scalar clamped per RFC 7748.
-- Deps: B (bit ops), F (field25519).

return function(B, F)
        local band = B.band
        local floor = math.floor
        local a24 = F.from_small(121665)

        local function cswap(swap, a, b)
                for i = 0, 15 do
                        local t = swap * (b[i] - a[i])
                        a[i] = a[i] + t
                        b[i] = b[i] - t
                end
        end

        local function bit(kk, t)
                if band(kk[floor(t / 8) + 1], 2 ^ (t % 8)) ~= 0 then
                        return 1
                end
                return 0
        end

        -- RFC 7748 §5 ladder; k and u are 32-byte strings.
        local function scalarmult(k, u)
                local kk = { k:byte(1, 32) }
                kk[1] = band(kk[1], 248)
                kk[32] = B.bor(band(kk[32], 127), 64)

                local x1 = F.frombytes(u)
                local x2 = F.one()
                local z2 = F.zero()
                local x3 = F.copy(x1)
                local z3 = F.one()
                local swap = 0

                for t = 254, 0, -1 do
                        local kt = bit(kk, t)
                        local d = (swap + kt) % 2
                        cswap(d, x2, x3)
                        cswap(d, z2, z3)
                        swap = kt

                        local a = F.add(x2, z2)
                        local aa = F.mul(a, a)
                        local b = F.sub(x2, z2)
                        local bb = F.mul(b, b)
                        local e = F.sub(aa, bb)
                        local c = F.add(x3, z3)
                        local dd = F.sub(x3, z3)
                        local da = F.mul(dd, a)
                        local cb = F.mul(c, b)
                        local s1 = F.add(da, cb)
                        x3 = F.mul(s1, s1)
                        local s2 = F.sub(da, cb)
                        z3 = F.mul(x1, F.mul(s2, s2))
                        x2 = F.mul(aa, bb)
                        local s3 = F.add(aa, F.mul(a24, e))
                        z2 = F.mul(e, s3)
                end

                cswap(swap, x2, x3)
                cswap(swap, z2, z3)
                return F.tobytes(F.mul(x2, F.invert(z2)))
        end

        local BASE = string.char(9) .. string.rep("\0", 31)

        local function public_key(sk)
                return scalarmult(sk, BASE)
        end

        local function shared(sk, their_pk)
                return scalarmult(sk, their_pk)
        end

        return {
                scalarmult = scalarmult,
                public_key = public_key,
                shared = shared,
        }
end
