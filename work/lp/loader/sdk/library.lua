-- library.lua — Loader SDK (doc.md §5, §8 steps 1-4).
-- SDK.new(config) with config:
--   script_id (string), base_url (string, no trailing slash),
--   proof_key (string), verify_pk (32-byte Ed25519 public key),
--   lv (loader version string)
-- Env: { request(options)->response, json_encode, json_decode,
--        os_time()->int, random_bytes(n)->string,
--        file { read(path), write(path, data), exists(path), mkdir(path) } }
-- All Env.file functions optional; every call is pcall-guarded.

return function(Crypto, Env)
	local enc = Crypto.encoding
	local sha2 = Crypto.sha2
	local hmac = Crypto.hmac
	local ed25519 = Crypto.ed25519

	local function file_call(name, path, data)
		if not Env.file or type(Env.file[name]) ~= "function" then
			return nil
		end
		if data ~= nil then
			local ok, res = pcall(Env.file[name], path, data)
			if ok then
				return res
			end
			return nil
		end
		local ok, res = pcall(Env.file[name], path)
		if ok then
			return res
		end
		return nil
	end

	local function canonical_json(value)
		local t = type(value)
		if value == nil then
			return "null"
		elseif t == "boolean" then
			if value then
				return "true"
			end
			return "false"
		elseif t == "number" then
			if math.floor(value) ~= value or value < -9007199254740992 or value > 9007199254740992 then
				return nil
			end
			return string.format("%d", value)
		elseif t == "string" then
			local out = { '"' }
			for i = 1, #value do
				local b = value:byte(i)
				if b == 34 then
					out[#out + 1] = '\\"'
				elseif b == 92 then
					out[#out + 1] = "\\\\"
				elseif b < 32 then
					out[#out + 1] = string.format("\\u%04x", b)
				else
					out[#out + 1] = value:sub(i, i)
				end
			end
			out[#out + 1] = '"'
			return table.concat(out)
		elseif t == "table" then
			local keys = {}
			for k in pairs(value) do
				if type(k) ~= "string" then
					return nil
				end
				keys[#keys + 1] = k
			end
			table.sort(keys)
			local parts = {}
			for _, k in ipairs(keys) do
				local v = canonical_json(value[k])
				if v == nil then
					return nil
				end
				parts[#parts + 1] = canonical_json(k) .. ":" .. v
			end
			return "{" .. table.concat(parts, ",") .. "}"
		end
		return nil
	end

	local DENIAL_CODES = {
		KEY_VALID = true,
		KEY_INVALID = true,
		KEY_EXPIRED = true,
		KEY_BLACKLISTED = true,
		HWID_MISMATCH = true,
		SCRIPT_NOT_ALLOWED = true,
		RATE_LIMITED = true,
		UPDATE_REQUIRED = true,
		BAD_REQUEST = true,
		SERVER_ERROR = true,
	}

	local SDK = {}

	SDK.new = function(config)
		local self = {
			script_id = config.script_id,
			base_url = config.base_url,
			proof_key = config.proof_key,
			verify_pk = config.verify_pk,
			lv = config.lv,
			time_offset = 0,
			nodes = nil,
		}

		local function pick_node()
			if self.nodes and #self.nodes > 0 then
				return self.nodes[math.random(1, #self.nodes)]
			end
			return self.base_url
		end

		local function common_headers(method, path, body)
			local ts = Env.os_time() + self.time_offset
			local nonce = enc.b64url_encode(Env.random_bytes(16))
			local body_hash = enc.hex_encode(sha2.sha256(body or ""))
			local proof_input = method .. "|" .. path .. "|" .. tostring(ts) .. "|" .. nonce .. "|" .. body_hash
			local proof = enc.hex_encode(hmac.hmac_sha256(self.proof_key, proof_input))
			return {
				["x-ts"] = tostring(ts),
				["x-nonce"] = nonce,
				["x-lv"] = self.lv,
				["x-proof"] = proof,
			}
		end

		local function request(method, url, path, body, extra_headers)
			local headers = common_headers(method, path, body)
			if extra_headers then
				for k, v in pairs(extra_headers) do
					headers[k] = v
				end
			end
			local opts = {
				Method = method,
				Url = url,
				Headers = headers,
			}
			if body then
				opts.Body = body
				opts.Headers["Content-Type"] = "application/json"
			end
			return Env.request(opts)
		end

		function self.sync()
			local res = request("GET", self.base_url .. "/sync", "/sync", nil)
			if not res or res.StatusCode ~= 200 or type(res.Body) ~= "string" then
				return nil, "network"
			end
			local ok, data = pcall(Env.json_decode, res.Body)
			if not ok or type(data) ~= "table" or type(data.st) ~= "number" or type(data.nodes) ~= "table" then
				return nil, "protocol"
			end
			self.time_offset = data.st - Env.os_time()
			self.nodes = data.nodes
			return data
		end

		function self.status()
			local base = pick_node()
			local res = request("GET", base .. "/status", "/status", nil)
			if not res or res.StatusCode ~= 200 then
				return nil, "network"
			end
			local ok, data = pcall(Env.json_decode, res.Body)
			if not ok or type(data) ~= "table" then
				return nil, "protocol"
			end
			return data
		end

		function self.check_key(key)
			if not self.nodes then
				local ok = self.sync()
				if not ok then
					return { ok = false, code = "SERVER_ERROR", message = "Network error." }
				end
			end
			local node = pick_node()
			local body = Env.json_encode({
				key = key,
				script_id = self.script_id,
				lv = self.lv,
			})
			local res = request("POST", node .. "/check_key", "/check_key", body)
			if not res or res.StatusCode ~= 200 or type(res.Body) ~= "string" then
				return { ok = false, code = "SERVER_ERROR", message = "Network error." }
			end
			local ok, envelope = pcall(Env.json_decode, res.Body)
			if not ok or type(envelope) ~= "table" or type(envelope.code) ~= "string" then
				return { ok = false, code = "SERVER_ERROR", message = "Network error." }
			end
			if not DENIAL_CODES[envelope.code] then
				return { ok = false, code = "KEY_INVALID", message = "The provided key could not be used." }
			end
			if envelope.code ~= "KEY_VALID" then
				return { ok = false, code = envelope.code, message = envelope.message or "" }
			end
			local headers = res.Headers or {}
			local sig = headers["x-sig"]
			local sts = headers["x-ts"]
			if not sig or not sts then
				return { ok = false, code = "SERVER_ERROR", message = "Network error." }
			end
			local sig_bytes = enc.b64url_decode(sig)
			if not sig_bytes or #sig_bytes ~= 64 then
				return { ok = false, code = "SERVER_ERROR", message = "Network error." }
			end
			local data_canon = canonical_json(envelope.data or {})
			if not data_canon then
				return { ok = false, code = "SERVER_ERROR", message = "Network error." }
			end
			local signed = envelope.code .. "|" .. (envelope.message or "") .. "|" .. data_canon .. "|" .. sts
			if not ed25519.verify(self.verify_pk, signed, sig_bytes) then
				return { ok = false, code = "SERVER_ERROR", message = "Network error." }
			end
			return {
				ok = true,
				code = envelope.code,
				message = envelope.message or "",
				data = envelope.data,
			}
		end

		function self.load_key_cache(path)
			local data = file_call("read", path)
			if type(data) ~= "string" or #data == 0 then
				return nil
			end
			return (data:gsub("%s", ""))
		end

		function self.save_key_cache(path, key)
			local dir = path:match("^(.*)/[^/]+$")
			if dir and dir ~= "" then
				file_call("mkdir", dir)
			end
			file_call("write", path, key)
		end

		return self
	end

	return SDK
end
