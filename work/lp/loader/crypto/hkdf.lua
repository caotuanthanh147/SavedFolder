-- hkdf.lua — HKDF with SHA-256 (RFC 5869).
-- Deps: hmac (from hmac.lua).

return function(hmac)
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
