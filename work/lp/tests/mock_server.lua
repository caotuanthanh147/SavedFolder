-- mock_server.lua — TEST-ONLY stand-in for the M1 API (doc.md §5).
-- Implements /sync, /status, /check_key, /auth/<id>/init, /auth/<id>/payload
-- using the M1 wire formats as landed (Public 617d386: init =
-- b64url(serverPub|serverNonce|ct|tag), aad = scriptId|serverPub|
-- serverNonce, nonce = serverNonce[0..12); payload = b64url(nonce|ct|
-- tag), payloadKey salt = fromHex(build_hash), info = "payload-key"|
-- fromHex(watermark_id), aad = scriptId|sessionId(16 raw)).

return function(Crypto, Env, Signer, opts)
        local enc = Crypto.encoding
        local sha2 = Crypto.sha2
        local hmac = Crypto.hmac
        local hkdf = Crypto.hkdf
        local aead = Crypto.aead
        local x25519 = Crypto.x25519
        local ed25519 = Crypto.ed25519

        local server_sk = opts.signing_sk
        local server_pk = Signer.secret_to_public(server_sk)
        local proof_key = opts.proof_key
        local valid_key = opts.valid_key
        local script_id = opts.script_id
        local build = opts.build
        local build_hash = opts.build_hash
        local bundle = opts.bundle
        local watermark_id = opts.watermark_id
        local server_time = opts.server_time

        local state = {
                proof_checked = nil,
                check_key_headers = nil,
                init_request = nil,
                payload_request = nil,
                nonce_log = {},
        }

        local function canonical_json(value)
                local t = type(value)
                if value == nil then
                        return "null"
                elseif t == "boolean" then
                        return tostring(value)
                elseif t == "number" then
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
                                keys[#keys + 1] = k
                        end
                        table.sort(keys)
                        local parts = {}
                        for _, k in ipairs(keys) do
                                parts[#parts + 1] = canonical_json(k) .. ":" .. canonical_json(value[k])
                        end
                        return "{" .. table.concat(parts, ",") .. "}"
                end
                return "null"
        end

        local function envelope(code, message, data)
                local body = Env.json_encode({ code = code, message = message, data = data })
                local sts = tostring(server_time)
                local sig = Signer.sign(server_sk, code .. "|" .. message .. "|" .. canonical_json(data) .. "|" .. sts)
                return {
                        StatusCode = 200,
                        Body = body,
                        Headers = {
                                ["x-ts"] = sts,
                                ["x-sig"] = enc.b64url_encode(sig),
                        },
                }
        end

        local function check_proof(headers, method, path, body)
                local ts = headers["x-ts"]
                local nonce = headers["x-nonce"]
                local proof = headers["x-proof"]
                if not ts or not nonce or not proof or not headers["x-lv"] then
                        return false
                end
                state.nonce_log[#state.nonce_log + 1] = nonce
                local body_hash = enc.hex_encode(sha2.sha256(body or ""))
                local expect = enc.hex_encode(hmac.hmac_sha256(proof_key, method .. "|" .. path .. "|" .. ts .. "|" .. nonce .. "|" .. body_hash))
                return expect == proof
        end

        local function json_response(tbl, extra)
                local headers = { ["x-ts"] = tostring(server_time) }
                if extra then
                        for k, v in pairs(extra) do
                                headers[k] = v
                        end
                end
                return { StatusCode = 200, Body = Env.json_encode(tbl), Headers = headers }
        end

        local function handle_init(req)
                state.init_request = req
                local body = Env.json_decode(req.Body or "")
                if not body or body.key ~= valid_key then
                        return { StatusCode = 200, Body = Env.json_encode({ code = "KEY_INVALID", message = "Invalid key.", data = {} }), Headers = { ["x-ts"] = tostring(server_time) } }
                end
                local hello = enc.b64url_decode(body.hello or "")
                if not hello or #hello ~= 48 then
                        return { StatusCode = 200, Body = Env.json_encode({ code = "BAD_REQUEST", message = "Bad hello.", data = {} }), Headers = { ["x-ts"] = tostring(server_time) } }
                end
                local client_pk = hello:sub(1, 32)
                local client_nonce = hello:sub(33)
                local server_sk_x = opts.server_x25519_sk
                local server_pk_x = x25519.public_key(server_sk_x)
                local server_nonce = opts.server_nonce
                local shared = x25519.shared(server_sk_x, client_pk)
                local session_key = hkdf.hkdf_sha256(shared, client_nonce .. server_nonce, "session-key", 32)
                state.session_key = session_key
                state.session_token = enc.b64url_encode(opts.server_nonce)
                local session = {
                        session_token = state.session_token,
                        session_expires_at = server_time + 3600,
                        tier = "paid",
                        auth_expire = 0,
                        discord_id = nil,
                        note = "mock",
                        build_hash = build_hash,
                        watermark_id = watermark_id,
                        payload_ref = "ref-1",
                }
                local plain = Env.json_encode(session)
                local aad = script_id .. server_pk_x .. server_nonce
                local sealed = aead.seal(session_key, server_nonce:sub(1, 12), aad, plain)
                return {
                        StatusCode = 200,
                        Body = enc.b64url_encode(server_pk_x .. server_nonce .. sealed),
                        Headers = {
                                ["x-ts"] = tostring(server_time),
                        },
                }
        end

        local function handle_payload(req)
                state.payload_request = req
                local body = Env.json_decode(req.Body or "")
                if not body or body.session_token ~= state.session_token then
                        return { StatusCode = 200, Body = "AAAA", Headers = { ["x-ts"] = tostring(server_time) } }
                end
                local salt = enc.hex_decode(build_hash)
                local info = "payload-key" .. enc.hex_decode(watermark_id)
                local payload_key = hkdf.hkdf_sha256(state.session_key, salt, info, 32)
                local session_id_raw = enc.b64url_decode(state.session_token)
                local sig = Signer.sign(server_sk, enc.hex_decode(build_hash) .. bundle)
                local plain = Env.json_encode({
                        build_hash = build_hash,
                        bundle = enc.b64url_encode(bundle),
                        bundle_sig = enc.b64url_encode(sig),
                })
                local nonce = opts.payload_nonce or "\1\2\3\4\5\6\7\8\9\10\11\12"
                local aad = script_id .. session_id_raw
                local sealed = aead.seal(payload_key, nonce, aad, plain)
                return {
                        StatusCode = 200,
                        Body = enc.b64url_encode(nonce .. sealed),
                        Headers = { ["x-ts"] = tostring(server_time) },
                }
        end

        local server = {}

        function server.request(opts)
                local method = opts.Method
                local url = opts.Url
                local path = url:match("^https?://[^/]+(/.*)$") or url
                local query = ""
                path, query = path:match("^([^?]*)%??(.*)$")
                local headers = {}
                for k, v in pairs(opts.Headers or {}) do
                        headers[string.lower(k)] = v
                end

                if method == "GET" and path == "/sync" then
                        state.proof_checked = check_proof(headers, "GET", "/sync", nil)
                        return json_response({ st = server_time, nodes = { opts.base or "https://mock-node" }, colo = "TST" })
                elseif method == "GET" and path == "/status" then
                        return json_response({ active = true, versions = { ["1"] = "v1" }, nodes = { "mock-node" } })
                elseif method == "POST" and path == "/check_key" then
                        state.check_key_headers = headers
                        state.proof_checked = check_proof(headers, "POST", "/check_key", opts.Body)
                        local body = Env.json_decode(opts.Body or "")
                        if not body or body.key ~= valid_key then
                                return envelope("KEY_INVALID", "The provided key is not valid.", {})
                        end
                        return envelope("KEY_VALID", "The provided key is valid.", {
                                note = "mock note",
                                auth_expire = server_time + 86400,
                                total_executions = 7,
                        })
                elseif method == "POST" and path:sub(1, 6) == "/auth/" then
                        local rest = path:sub(6)
                        if rest:sub(-5) == "/init" then
                                return handle_init(opts)
                        elseif rest:sub(-8) == "/payload" then
                                return handle_payload(opts)
                        end
                end
                return { StatusCode = 404, Body = "", Headers = {} }
        end

        server.state = state
        server.server_pk = server_pk
        return server
end
