-- hmac.lua — HMAC (FIPS 198-1 / RFC 2104) over the sha2 module.
-- Deps: B (bit ops), sha2 (from sha2.lua).

return function(B, sha2)
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
