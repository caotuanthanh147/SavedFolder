-- env_executor.lua — builds an Env table for Roblox executor hosts
-- (UNC standard, potassium docs §Miscellaneous/Crypt). Every capability
-- is feature-detected; missing capabilities degrade to nil and the SDK
-- treats them as unavailable (doc §8: generic failure, no crash).
-- No secrets are hardcoded; the caller supplies config.

return function()
	local env = {}

	local function resolve(names)
		for _, n in ipairs(names) do
			local v = _G[n]
			if type(v) == "function" then
				return v
			end
			local holder = _G
			for part in string.gmatch(n, "[^.]+") do
				if type(holder) ~= "table" then
					holder = nil
					break
				end
				holder = holder[part]
			end
			if type(holder) == "function" then
				return holder
			end
		end
		return nil
	end

	local request_fn = resolve({ "request", "http_request", "syn.request" })
	if not request_fn and type(_G.syn) == "table" and type(_G.syn.request) == "function" then
		request_fn = _G.syn.request
	end
	env.request = request_fn

	local http_service_ok, HttpService = pcall(function()
		return game:GetService("HttpService")
	end)
	if http_service_ok and HttpService then
		env.json_encode = function(v)
			return HttpService:JSONEncode(v)
		end
		env.json_decode = function(s)
			return HttpService:JSONDecode(s)
		end
	end
	if not env.json_encode then
		return nil, "json"
	end

	env.os_time = os.time

	local crypt_table = _G.crypt
	if type(crypt_table) == "table" and type(crypt_table.random) == "function" then
		env.random_bytes = function(n)
			return crypt_table.random(n)
		end
	elseif type(crypt_table) == "table" and type(crypt_table.generatebytes) == "function" then
		local b64std = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
		local rev = {}
		for i = 1, 64 do
			rev[b64std:byte(i)] = i - 1
		end
		env.random_bytes = function(n)
			local text = crypt_table.generatebytes(n)
			local out = {}
			local acc, bits = 0, 0
			for i = 1, #text do
				local v = rev[text:byte(i)]
				if not v then
					return nil
				end
				acc = acc * 64 + v
				bits = bits + 6
				if bits >= 8 then
					bits = bits - 8
					out[#out + 1] = string.char(math.floor(acc / 2 ^ bits) % 256)
					acc = acc % 2 ^ bits
				end
			end
			return table.concat(out)
		end
	elseif type(_G.syn) == "table" and type(_G.syn.crypt) == "table" and type(_G.syn.crypt.random) == "function" then
		env.random_bytes = function(n)
			return _G.syn.crypt.random(n)
		end
	else
		env.random_bytes = function(n)
			local out = {}
			for i = 1, n do
				out[i] = string.char(math.random(0, 255))
			end
			return table.concat(out)
		end
	end

	env.file = {}
	if type(readfile) == "function" then
		env.file.read = readfile
	end
	if type(writefile) == "function" then
		env.file.write = writefile
	end
	if type(isfile) == "function" then
		env.file.exists = isfile
	end
	if type(makefolder) == "function" then
		env.file.mkdir = makefolder
	end

	return env
end
