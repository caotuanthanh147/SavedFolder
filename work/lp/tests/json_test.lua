-- json_test.lua — minimal JSON codec for the test environment.
-- Encode: tables (string keys), strings, integers, booleans, nil.
-- Decode: full JSON subset sufficient for envelopes and payloads.
-- TEST-ONLY: executors use HttpService (see env_executor.lua).

local json = {}
local NULL = {}
json.NULL = NULL

local function encode_value(v)
	local t = type(v)
	if v == nil then
		return "null", true
	elseif t == "boolean" then
		return tostring(v), true
	elseif t == "number" then
		if math.floor(v) ~= v then
			return nil, false
		end
		return string.format("%d", v), true
	elseif t == "string" then
		local out = { '"' }
		for i = 1, #v do
			local b = v:byte(i)
			if b == 34 then
				out[#out + 1] = '\\"'
			elseif b == 92 then
				out[#out + 1] = "\\\\"
			elseif b == 10 then
				out[#out + 1] = "\\n"
			elseif b == 13 then
				out[#out + 1] = "\\r"
			elseif b == 9 then
				out[#out + 1] = "\\t"
			elseif b < 32 then
				out[#out + 1] = string.format("\\u%04x", b)
			else
				out[#out + 1] = v:sub(i, i)
			end
		end
		out[#out + 1] = '"'
		return table.concat(out), true
	elseif t == "table" then
		local is_array = #v > 0
		local parts = {}
		if is_array then
			for i = 1, #v do
				local enc, ok = encode_value(v[i])
				if not ok then
					return nil, false
				end
				parts[#parts + 1] = enc
			end
			return "[" .. table.concat(parts, ",") .. "]", true
		end
		for k, val in pairs(v) do
			if type(k) ~= "string" then
				return nil, false
			end
			local ke, kok = encode_value(k)
			local ve, vok = encode_value(val)
			if not kok or not vok then
				return nil, false
			end
			parts[#parts + 1] = ke .. ":" .. ve
		end
		table.sort(parts)
		return "{" .. table.concat(parts, ",") .. "}", true
	end
	return nil, false
end

function json.encode(v)
	local out, ok = encode_value(v)
	if not ok then
		return nil
	end
	return out
end

function json.decode(s)
	local pos = { i = 1 }
	local function skip()
		while pos.i <= #s do
			local c = s:sub(pos.i, pos.i)
			if c == " " or c == "\t" or c == "\n" or c == "\r" then
				pos.i = pos.i + 1
			else
				break
			end
		end
	end

	local parse

	local function parse_string()
		if s:sub(pos.i, pos.i) ~= '"' then
			return nil
		end
		pos.i = pos.i + 1
		local out = {}
		while pos.i <= #s do
			local c = s:sub(pos.i, pos.i)
			if c == '"' then
				pos.i = pos.i + 1
				return table.concat(out)
			elseif c == "\\" then
				local n = s:sub(pos.i + 1, pos.i + 1)
				pos.i = pos.i + 2
				if n == "n" then
					out[#out + 1] = "\n"
				elseif n == "r" then
					out[#out + 1] = "\r"
				elseif n == "t" then
					out[#out + 1] = "\t"
				elseif n == "u" then
					local hex = s:sub(pos.i + 1, pos.i + 4)
					if #hex ~= 4 then
						return nil
					end
					out[#out + 1] = string.char(tonumber(hex, 16) or 0)
					pos.i = pos.i + 4
				else
					out[#out + 1] = n
				end
			else
				out[#out + 1] = c
				pos.i = pos.i + 1
			end
		end
		return nil
	end

	parse = function()
		skip()
		local c = s:sub(pos.i, pos.i)
		if c == "{" then
			pos.i = pos.i + 1
			local obj = {}
			skip()
			if s:sub(pos.i, pos.i) == "}" then
				pos.i = pos.i + 1
				return obj
			end
			while true do
				skip()
				local k = parse_string()
				if not k then
					return nil
				end
				skip()
				if s:sub(pos.i, pos.i) ~= ":" then
					return nil
				end
				pos.i = pos.i + 1
				local v = parse()
				if v == nil then
					return nil
				end
				if v ~= NULL then
					obj[k] = v
				end
				skip()
				local d = s:sub(pos.i, pos.i)
				if d == "," then
					pos.i = pos.i + 1
				elseif d == "}" then
					pos.i = pos.i + 1
					return obj
				else
					return nil
				end
			end
		elseif c == "[" then
			pos.i = pos.i + 1
			local arr = {}
			skip()
			if s:sub(pos.i, pos.i) == "]" then
				pos.i = pos.i + 1
				return arr
			end
			while true do
				local v = parse()
				if v == nil then
					return nil
				end
				arr[#arr + 1] = v
				skip()
				local d = s:sub(pos.i, pos.i)
				if d == "," then
					pos.i = pos.i + 1
				elseif d == "]" then
					pos.i = pos.i + 1
					return arr
				else
					return nil
				end
			end
		elseif c == '"' then
			return parse_string()
		elseif s:sub(pos.i, pos.i + 3) == "true" then
			pos.i = pos.i + 4
			return true
		elseif s:sub(pos.i, pos.i + 4) == "false" then
			pos.i = pos.i + 5
			return false
		elseif s:sub(pos.i, pos.i + 3) == "null" then
			pos.i = pos.i + 4
			return NULL
		else
			local num = s:match("^-?%d+", pos.i)
			if not num then
				return nil
			end
			pos.i = pos.i + #num
			return tonumber(num)
		end
	end

	skip()
	local result = parse()
	if result == nil or result == NULL then
		return nil
	end
	return result
end

return json
