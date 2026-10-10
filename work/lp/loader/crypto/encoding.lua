-- encoding.lua — base64url (RFC 4648 §5, no padding) and lowercase hex.
-- Pure string operations; no deps.

return function()
        local B64URL = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"
        local B64STD = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

        local function b64encode_with(alphabet, data)
                local out = {}
                local len = #data
                local i = 1
                while i + 2 <= len do
                        local a, b, c = data:byte(i, i + 2)
                        local n = a * 65536 + b * 256 + c
                        out[#out + 1] = alphabet:sub(math.floor(n / 262144) % 64 + 1, math.floor(n / 262144) % 64 + 1)
                        out[#out + 1] = alphabet:sub(math.floor(n / 4096) % 64 + 1, math.floor(n / 4096) % 64 + 1)
                        out[#out + 1] = alphabet:sub(math.floor(n / 64) % 64 + 1, math.floor(n / 64) % 64 + 1)
                        out[#out + 1] = alphabet:sub(n % 64 + 1, n % 64 + 1)
                        i = i + 3
                end
                local rem = len - i + 1
                if rem == 1 then
                        local a = data:byte(i)
                        out[#out + 1] = alphabet:sub(math.floor(a / 4) + 1, math.floor(a / 4) + 1)
                        out[#out + 1] = alphabet:sub((a % 4) * 16 + 1, (a % 4) * 16 + 1)
                elseif rem == 2 then
                        local a, b = data:byte(i, i + 1)
                        local n = a * 16 + math.floor(b / 16)
                        out[#out + 1] = alphabet:sub(math.floor(n / 64) + 1, math.floor(n / 64) + 1)
                        out[#out + 1] = alphabet:sub(n % 64 + 1, n % 64 + 1)
                        out[#out + 1] = alphabet:sub((b % 16) * 4 + 1, (b % 16) * 4 + 1)
                end
                return table.concat(out)
        end

        local function decode_with(alphabet, text)
                local rev = {}
                for i = 1, 64 do
                        rev[alphabet:byte(i)] = i - 1
                end
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

        local function b64url_encode(data)
                return b64encode_with(B64URL, data)
        end

        local function b64url_decode(text)
                if #text % 4 == 1 then
                        return nil
                end
                return decode_with(B64URL, text)
        end

        local function hex_encode(data)
                return (data:gsub(".", function(c)
                        return string.format("%02x", c:byte())
                end))
        end

        local function hex_decode(text)
                if #text % 2 ~= 0 or text:match("[^%x]") then
                        return nil
                end
                return (text:gsub("(%x%x)", function(h)
                        return string.char(tonumber(h, 16))
                end))
        end

        return {
                b64url_encode = b64url_encode,
                b64url_decode = b64url_decode,
                hex_encode = hex_encode,
                hex_decode = hex_decode,
        }
end
