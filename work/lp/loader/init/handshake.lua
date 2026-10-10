-- handshake.lua — init/payload client (doc.md §5.5, §8 steps 7-10).
-- new(config): script_id, base_url, proof_key, verify_pk (32B), lv,
--   build (build id string)
-- Env: same shape as loader/sdk/library.lua.
-- Derivations per doc.md §5.7 with the clarifications recorded in
-- contracts/proof-spec.md (server nonce travels in the x-nonce
-- response header; payload AEAD nonce is 12 zero bytes because each
-- key encrypts exactly one message; watermark id must be delivered to
-- the client by the server — this module reads it from the init
-- response when present, else the caller passes it to payload()).

return function(Crypto, Env)
	local enc = Crypto.encoding
	local sha2 = Crypto.sha2
	local hmac = Crypto.hmac
	local hkdf = Crypto.hkdf
	local aead = Crypto.aead
	local x25519 = Crypto.x25519
	local ed25519 = Crypto.ed25519

	local ZERO_NONCE = string.rep("\0", 12)

	local function common_headers(proof_key, lv, method, path, body)
		local ts = Env.os_time()
		local nonce = enc.b64url_encode(Env.random_bytes(16))
		local body_hash = enc.hex_encode(sha2.sha256(body or ""))
		local proof_input = method .. "|" .. path .. "|" .. tostring(ts) .. "|" .. nonce .. "|" .. body_hash
		local proof = enc.hex_encode(hmac.hmac_sha256(proof_key, proof_input))
		return {
			["x-ts"] = tostring(ts),
			["x-nonce"] = nonce,
			["x-lv"] = lv,
			["x-proof"] = proof,
		}
	end

	local Handshake = {}

	Handshake.new = function(config)
		local self = {
			script_id = config.script_id,
			base_url = config.base_url,
			proof_key = config.proof_key,
			verify_pk = config.verify_pk,
			lv = config.lv,
			build = config.build,
			time_offset = 0,
		}

		local function path_prefix()
			return "/auth/" .. self.script_id
		end

		local function request(method, path, body, expects)
			local headers = common_headers(self.proof_key, self.lv, method, path, body)
			local opts = {
				Method = method,
				Url = self.base_url .. path,
				Headers = headers,
			}
			if body then
				opts.Body = body
				opts.Headers["Content-Type"] = "application/json"
			end
			local res = Env.request(opts)
			if not res or res.StatusCode ~= 200 or type(res.Body) ~= "string" then
				return nil, "network"
			end
			return res
		end

		function self.sync()
			local res = request("GET", "/sync", nil)
			if not res then
				return nil
			end
			local ok, data = pcall(Env.json_decode, res.Body)
			if not ok or type(data) ~= "table" or type(data.st) ~= "number" then
				return nil
			end
			self.time_offset = data.st - Env.os_time()
			return data
		end

		-- Step 7-8: ephemeral X25519, POST init, derive session key.
		-- Returns the decrypted session table (doc §5.5 fields) with the
		-- raw session key attached for payload().
		function self.init(key, place_id, game_id, user_id)
			if self.time_offset == 0 then
				self.sync()
			end
			local sk = Env.random_bytes(32)
			local pk = x25519.public_key(sk)
			local client_nonce = Env.random_bytes(16)
			local hello = enc.b64url_encode(pk .. client_nonce)
			local path = path_prefix() .. "/init"
			local body = Env.json_encode({
				v = 1,
				key = key,
				build = self.build,
				place_id = place_id,
				game_id = game_id,
				user_id = user_id,
				hello = hello,
			})
			local res = request("POST", path, body)
			if not res then
				return nil, "network"
			end
			local blob = enc.b64url_decode(res.Body)
			if not blob or #blob < 48 then
				return nil, "protocol"
			end
			local server_pk = blob:sub(1, 32)
			local ct = blob:sub(33)
			local headers = res.Headers or {}
			local server_nonce_b64 = headers["x-nonce"]
			if not server_nonce_b64 then
				return nil, "protocol"
			end
			local server_nonce = enc.b64url_decode(server_nonce_b64)
			if not server_nonce or #server_nonce ~= 16 then
				return nil, "protocol"
			end
			local shared = x25519.shared(sk, server_pk)
			local session_key = hkdf.hkdf_sha256(shared, client_nonce .. server_nonce, "session-key", 32)
			local plain = aead.open(session_key, ZERO_NONCE, "", ct)
			if not plain then
				return nil, "protocol"
			end
			local ok, session = pcall(Env.json_decode, plain)
			if not ok or type(session) ~= "table" or type(session.session_token) ~= "string" or type(session.payload_ref) ~= "string" then
				return nil, "protocol"
			end
			session.session_key = session_key
			return session
		end

		-- Step 9-10: fetch payload, derive payload key, decrypt, verify sig.
		function self.payload(session, watermark_id)
			local path = path_prefix() .. "/payload"
			local body = Env.json_encode({
				v = 1,
				session_token = session.session_token,
				payload_ref = session.payload_ref,
			})
			local res = request("POST", path, body)
			if not res then
				return nil, "network"
			end
			local blob = enc.b64url_decode(res.Body)
			if not blob or #blob < 16 then
				return nil, "protocol"
			end
			local wm = watermark_id or session.watermark_id
			if type(wm) ~= "string" then
				return nil, "watermark"
			end
			local salt_input = self.build .. wm
			local payload_key = hkdf.hkdf_sha256(session.session_key, salt_input, "payload-key", 32)
			local plain = aead.open(payload_key, ZERO_NONCE, "", blob)
			if not plain then
				return nil, "protocol"
			end
			local ok, payload = pcall(Env.json_decode, plain)
			if not ok or type(payload) ~= "table" or type(payload.build_hash) ~= "string" or type(payload.bundle) ~= "string" or type(payload.bundle_sig) ~= "string" then
				return nil, "protocol"
			end
			local sig = enc.b64url_decode(payload.bundle_sig)
			if not sig or #sig ~= 64 then
				return nil, "protocol"
			end
			local bundle = enc.b64url_decode(payload.bundle)
			if not bundle then
				return nil, "protocol"
			end
			local signed = enc.hex_decode(payload.build_hash)
			if not signed then
				return nil, "protocol"
			end
			if not ed25519.verify(self.verify_pk, signed .. bundle, sig) then
				return nil, "signature"
			end
			return {
				build_hash = payload.build_hash,
				bundle = bundle,
				bundle_sig = sig,
			}
		end

		return self
	end

	return Handshake
end
