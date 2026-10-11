-- env_checks.lua — M7 §11 environment/integrity checks (doc.md §11, D-M7-5).
-- Factory chunk in M3 loader style: return function(Crypto, Env) ... end.
-- Crypto needs: sha2 (sha256), hmac (hmac_sha256), encoding (b64url_encode,
-- hex_encode). Env shape = loader/sdk/library.lua's Env, plus an OPTIONAL
-- Env.clock (sub-second monotonic clock; defaults to os.clock when present).
--
-- API (D-M7-12..17):
--   local Checks = chunk()(Crypto, Env)
--   local c = Checks.new({ script_id, base_url, proof_key, lv })
--     → wraps Env.request with the §1.2.9 header watch (teach-then-diff);
--       every module built on the SAME Env table afterwards is covered.
--   c:capture()  → baseline (identity double-capture, env snapshot, timing
--                  median of 9). Idempotent.
--   c:run()      → failures array, e.g. { {check="identity.changed",
--                  detail="loadstring"}, ... }; empty = clean. Header
--                  failures accumulated since the last run() are merged;
--                  everything is read-once. Never raises, never prints.
--   c:digest()   → sha256 hex over the sorted baseline identity lines
--                  (deterministic per environment; for decoy-path variation
--                  and tamper detail — NOT a key-derivation input, D-M7-11).
--   c:report(session_token, failure) → POST /auth/<script_id>/heartbeat
--                  with the D-M7-6 tamper field; response read only for
--                  transport success; never raises. False when no
--                  session_token (the server wire requires one).
--
-- §11 contract: signals, never verdicts. Silent failure is the CALLER's
-- policy (report failures[1], then load nothing, no explanatory message —
-- see loader/checks/README-M7-CHECKS.md). This module itself never prints,
-- notifies, or raises on a check outcome.

return function(Crypto, Env)
	local sha2 = Crypto.sha2
	local hmac = Crypto.hmac
	local enc = Crypto.encoding

	local TIMING_BASELINE_SAMPLES = 9
	local TIMING_RUN_SAMPLES = 5
	local TIMING_RATIO = 20
	local WORK_UNIT = string.rep("m7", 32)

	-- Pinned critical surfaces (D-M7-13a). UNC extras are feature-detected:
	-- absent-at-baseline + absent-at-run = consistent (not a signal).
	local CRITICAL_GLOBALS = {
		"request", "http_request", "loadstring", "getfenv",
		"setfenv", "getgenv", "rawget", "rawequal",
		"hookfunction", "getconnections", "newcclosure",
	}

	local function fold(k)
		return (tostring(k):gsub("%s", ""):lower())
	end

	local function identity_token(v)
		local t = type(v)
		if t == "function" then
			return t .. "|" .. tostring(v)
		end
		return t
	end

	local function safe_global(name)
		local ok, v = pcall(function()
			return _G[name]
		end)
		if ok then
			return identity_token(v)
		end
		return "error"
	end

	local function executor_identity()
		local ok, res = pcall(function()
			if type(identify_executor) == "function" then
				return identify_executor()
			end
			if type(_G.syn) == "table" then
				return "syn"
			end
			return "unknown"
		end)
		if ok and type(res) == "string" and #res > 0 then
			return res
		end
		return "unknown"
	end

	local function version_string()
		local ok, res = pcall(function()
			if type(version) == "function" then
				return version()
			end
		end)
		if ok and type(res) == "string" and #res > 0 then
			return res
		end
		if type(_G.VERSION) == "string" then
			return _G.VERSION
		end
		return ""
	end

	-- One full snapshot: function identities + environment fields.
	local function snapshot()
		local fns = {}
		for _, name in ipairs(CRITICAL_GLOBALS) do
			fns[name] = safe_global(name)
		end
		local ok, hook = pcall(function()
			if type(debug) == "table" and type(debug.sethook) == "function" then
				return debug.sethook
			end
			return nil
		end)
		fns["debug.sethook"] = ok and identity_token(hook) or "error"
		local envf = {}
		envf["executor"] = executor_identity()
		envf["version"] = version_string()
		local oks, sv = pcall(function()
			return rawget(_G, "syn")
		end)
		envf["syn"] = oks and identity_token(sv) or "error"
		return { fns = fns, env = envf }
	end

	local function resolve_clock()
		if type(Env) == "table" and type(Env.clock) == "function" then
			return Env.clock
		end
		if type(os) == "table" and type(os.clock) == "function" then
			return os.clock
		end
		return nil
	end

	local function work_once()
		return sha2.sha256(WORK_UNIT)
	end

	local function timing_median(clock, samples)
		local times = {}
		for _ = 1, samples do
			local t0 = clock()
			work_once()
			local t1 = clock()
			times[#times + 1] = t1 - t0
		end
		table.sort(times)
		local n = #times
		if n == 0 then
			return 0
		end
		if n % 2 == 1 then
			return times[(n + 1) / 2]
		end
		return (times[n / 2] + times[n / 2 + 1]) / 2
	end

	local Checks = {}

	Checks.new = function(config)
		local self = {
			script_id = config.script_id,
			base_url = config.base_url,
			proof_key = config.proof_key,
			lv = config.lv,
		}

		local state = {
			captured = false,
			fns = nil,
			envf = nil,
			anomalies = {},
			timing_base = nil,
			clock = nil,
			taught = nil,
			header_failures = {},
			header_seen = {},
		}
		local original_request = Env.request

		local function note_header(check, key)
			local dedup = check .. ":" .. key
			if not state.header_seen[dedup] then
				state.header_seen[dedup] = true
				state.header_failures[#state.header_failures + 1] = {
					check = check,
					detail = key,
				}
			end
		end

		-- §1.2.9 header watch (D-M7-13b/D-M7-14): snapshot the SDK-set
		-- headers table before the call; after a COMPLETED call diff it.
		-- First successful call teaches the executor's normal injection
		-- set; later unknown additions = headers.injected; removed or
		-- value-changed SDK-set entries = headers.modified. Keys are
		-- case-folded (executors legitimately recase header names).
		local function inspect_headers(headers, before, res)
			if type(headers) ~= "table" or type(before) ~= "table" then
				return
			end
			if type(res) ~= "table" or type(res.StatusCode) ~= "number" then
				return
			end
			local after = {}
			for k, v in pairs(headers) do
				after[fold(k)] = v
			end
			local added = {}
			for k in pairs(after) do
				if before[k] == nil then
					added[#added + 1] = k
				end
			end
			if state.taught == nil then
				state.taught = {}
				for _, k in ipairs(added) do
					state.taught[k] = true
				end
			else
				for _, k in ipairs(added) do
					if not state.taught[k] then
						note_header("headers.injected", k)
					end
				end
			end
			for k, v in pairs(before) do
				local av = after[k]
				if av == nil or av ~= v then
					note_header("headers.modified", k)
				end
			end
		end

		if type(original_request) == "function" then
			Env.request = function(opts)
				local headers = nil
				if type(opts) == "table" then
					headers = opts.Headers
				end
				local before = nil
				if type(headers) == "table" then
					before = {}
					for k, v in pairs(headers) do
						before[fold(k)] = v
					end
				end
				local res = original_request(opts)
				pcall(inspect_headers, headers, before, res)
				return res
			end
		end

		function self:capture()
			if state.captured then
				return true
			end
			local a = snapshot()
			local b = snapshot()
			state.fns = a.fns
			state.envf = a.env
			-- Active-swapping catch: two immediate captures that disagree
			-- already prove instrumentation (recorded, surfaced by run()).
			for name, tok in pairs(a.fns) do
				if b.fns[name] ~= tok then
					state.anomalies[#state.anomalies + 1] = {
						check = "identity.changed",
						detail = name,
					}
				end
			end
			for name, v in pairs(a.env) do
				if b.env[name] ~= v then
					state.anomalies[#state.anomalies + 1] = {
						check = "env.changed",
						detail = name,
					}
				end
			end
			state.clock = resolve_clock()
			if state.clock then
				local ok, med = pcall(timing_median, state.clock, TIMING_BASELINE_SAMPLES)
				if ok and type(med) == "number" and med > 0 then
					state.timing_base = med
				end
			end
			state.captured = true
			return true
		end

		function self:run()
			local failures = {}
			for _, f in ipairs(state.anomalies) do
				failures[#failures + 1] = f
			end
			state.anomalies = {}
			for _, f in ipairs(state.header_failures) do
				failures[#failures + 1] = f
			end
			state.header_failures = {}
			state.header_seen = {}
			if not state.captured then
				return failures
			end
			local now = snapshot()
			for name, tok in pairs(state.fns) do
				if now.fns[name] ~= tok then
					failures[#failures + 1] = {
						check = "identity.changed",
						detail = name,
					}
				end
			end
			for name, v in pairs(state.envf) do
				if now.env[name] ~= v then
					failures[#failures + 1] = {
						check = "env.changed",
						detail = name,
					}
				end
			end
			if state.clock and state.timing_base and state.timing_base > 0 then
				local ok, med = pcall(timing_median, state.clock, TIMING_RUN_SAMPLES)
				if ok and type(med) == "number" and med > 0 then
					if med >= state.timing_base * TIMING_RATIO then
						failures[#failures + 1] = {
							check = "timing.inflated",
							detail = string.format("%.1fx", med / state.timing_base),
						}
					end
				end
			end
			return failures
		end

		function self:digest()
			if not state.captured then
				return ""
			end
			local lines = {}
			for name, tok in pairs(state.fns) do
				lines[#lines + 1] = name .. "=" .. tok
			end
			for name, v in pairs(state.envf) do
				lines[#lines + 1] = name .. "=" .. v
			end
			table.sort(lines)
			return enc.hex_encode(sha2.sha256(table.concat(lines, "\n")))
		end

		-- D-M7-6/D-M7-15: minimal heartbeat client. Proof headers use the
		-- same formula as loader/sdk/library.lua's common_headers. The
		-- response envelope is read ONLY for transport success — §11: no
		-- signal that the report was acted on.
		function self:report(session_token, failure)
			if type(session_token) ~= "string" or #session_token == 0 then
				return false
			end
			if type(failure) ~= "table" or type(failure.check) ~= "string" then
				return false
			end
			if type(original_request) ~= "function" then
				return false
			end
			local ok, delivered = pcall(function()
				local path = "/auth/" .. self.script_id .. "/heartbeat"
				local body = Env.json_encode({
					v = 1,
					session_token = session_token,
					tamper = {
						check = failure.check,
						detail = failure.detail or "",
					},
				})
				local ts = Env.os_time()
				local nonce = enc.b64url_encode(Env.random_bytes(16))
				local body_hash = enc.hex_encode(sha2.sha256(body))
				local proof_input = "POST" .. "|" .. path .. "|" .. tostring(ts) .. "|" .. nonce .. "|" .. body_hash
				local proof = enc.hex_encode(hmac.hmac_sha256(self.proof_key, proof_input))
				local res = original_request({
					Method = "POST",
					Url = self.base_url .. path,
					Headers = {
						["x-ts"] = tostring(ts),
						["x-nonce"] = nonce,
						["x-lv"] = self.lv,
						["x-proof"] = proof,
						["Content-Type"] = "application/json",
					},
					Body = body,
				})
				return type(res) == "table" and res.StatusCode == 200
			end)
			if ok and delivered == true then
				return true
			end
			return false
		end

		return self
	end

	return Checks
end
