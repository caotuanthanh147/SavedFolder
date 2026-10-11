-- entry.lua — assembled-init entry glue (M3 session 3).
-- doc §8 steps 6-10 inside the D-M13-6 stub→init contract; M7 §11 checks
-- mounted per README-M7-CHECKS.md; M6 runtime invoked per RUNTIME-M6 v1.1
-- (containerless: container + constKey arrive per session).
--
-- Factory: return function(P) -> stub entry function
--   P.load   — chunk loader (loadstring or load), computed in the
--              executor env by the assembled wrapper
--   P.src    — module sources (strings):
--                bit, sha2, hmac, encoding, chacha20, poly1305, aead,
--                hkdf, field25519, x25519, ed25519        (M3 crypto)
--                env_executor                             (M3 sdk)
--                checks                                   (M7 env_checks)
--                handshake                                (M3 init client)
--                runtime                                  (M6 emitted chunk,
--                                                         containerless mode)
--   P.config — { script_id (hex32), base_url (fallback), proof_key,
--                verify_pk (32-byte raw string), lv,
--                key_path (optional; default "lp/<script_id>.key") }
--
-- The returned entry takes the stub payload { api, script_id, build, t,
-- s, r } (D-M13-6; no globals set by the stub) and returns the guest
-- script's main return values, or nil + a short internal code on any
-- failure. Every failure is silent and generic — no explanatory text
-- reaches the user (doc §8 rules; §11 for tamper).

return function(P)
        local load = P.load
        local src = P.src
        local cfg = P.config

        -- factory-chunk convention (all M3/M7 modules are `return function(deps)
        -- ... end`): load gives a chunk; the chunk call yields the factory; the
        -- factory call with deps yields the module. The M6 runtime is the one
        -- exception — a plain chunk that returns the entry fn directly.
        local function mod(source)
                return (load(source))()
        end

        -- module instantiation (dependency order mirrors tests/run.lua)
        local B = mod(src.bit)()
        local sha2 = mod(src.sha2)(B)
        local hmac = mod(src.hmac)(B, sha2)
        local encoding = mod(src.encoding)()
        local chacha20 = mod(src.chacha20)(B)
        local poly1305 = mod(src.poly1305)(B)
        local aead = mod(src.aead)(B, chacha20, poly1305)
        local hkdf = mod(src.hkdf)(hmac)
        local field = mod(src.field25519)(B)
        local x25519 = mod(src.x25519)(B, field)
        local ed25519 = mod(src.ed25519)(B, field, sha2)
        local Crypto = {
                sha2 = sha2, hmac = hmac, encoding = encoding,
                chacha20 = chacha20, poly1305 = poly1305, aead = aead,
                hkdf = hkdf, x25519 = x25519, ed25519 = ed25519,
        }

        local env_factory = mod(src.env_executor)
        local checks_factory = mod(src.checks)
        local handshake_factory = mod(src.handshake)
        local runtime_chunk = load(src.runtime) -- M6: chunk -> entry fn (loaded once)

        local script_id = cfg.script_id
        local key_path = cfg.key_path or ("lp/" .. script_id .. ".key")

        -- executor context (feature-detected; absent outside Roblox hosts)
        local ctx_place, ctx_game, ctx_user = nil, nil, nil
        pcall(function() ctx_place = game.PlaceId end)
        pcall(function() ctx_game = game.GameId end)
        pcall(function()
                ctx_user = game.Players.LocalPlayer.UserId
        end)

        -- the stub -> init entry (D-M13-6)
        return function(payload)
                -- 1. Env (§8 step 6): executor capabilities, feature-detected
                --    (resolved at CALL time so the stub's env is in place)
                local Env = env_factory()
                if not Env or type(Env.request) ~= "function" then
                        return nil, "env"
                end
                -- 2. §11 checks mount (M7): Checks.new WRAPS Env.request, so the
                --    sdk + handshake calls below are instrumented automatically
                local Checks = checks_factory(Crypto, Env)
                local checks = Checks.new({
                        script_id = script_id,
                        base_url = payload.api or cfg.base_url,
                        proof_key = cfg.proof_key,
                        lv = cfg.lv,
                })
                -- 3. baseline before the first request (sync teaches the
                --    executor's header-injection set on its first completed call)
                checks:capture()
                -- 4. handshake (§8 steps 7-8)
                local Handshake = handshake_factory(Crypto, Env)
                local hs = Handshake.new({
                        script_id = payload.script_id or script_id,
                        base_url = payload.api or cfg.base_url,
                        proof_key = cfg.proof_key,
                        verify_pk = cfg.verify_pk,
                        lv = cfg.lv,
                        build = payload.build,
                })
                if not hs.sync() then
                        return nil, "network"
                end
                -- key channel: the SDK key cache file (doc §8 step 3; the file
                -- stores only the key). nil for keyless scripts — the server
                -- decides (M1: keyless scripts skip the key checks).
                local key = nil
                if Env.file and type(Env.file.read) == "function" then
                        local ok, data = pcall(Env.file.read, key_path)
                        if ok and type(data) == "string" then
                                key = (data:gsub("%s", ""))
                                if #key == 0 then
                                        key = nil
                                end
                        end
                end
                local session = hs.init(key, ctx_place, ctx_game, ctx_user)
                if not session then
                        return nil, "auth"
                end
                -- 5. §11 verdict before the payload fetch (§11: signals, never
                --    client-side verdicts — report + silent no-load)
                local failures = checks:run()
                if #failures > 0 then
                        checks:report(session.session_token, failures[1])
                        return nil, "tamper"
                end
                -- per-fetch value (§5.6): the stub's r (32B hex) — integrity-
                -- linked derivation input. Feeds the CCP-M6 payload-key salt and
                -- the M6 entry s (validity-gated decoy).
                local fetch_value = nil
                if type(payload.r) == "string" and #payload.r == 64 then
                        fetch_value = encoding.hex_decode(payload.r)
                end
                -- 6. payload fetch (§8 step 9): decrypt + bundle_sig verify
                local pl = hs.payload(session, nil, fetch_value)
                if not pl then
                        return nil, "payload"
                end
                -- 7. hand the bytecode to the embedded VM runtime (§8 step 10;
                --    containerless M6: b = container, c = per-session constKey)
                if not pl.const_key then
                        return nil, "payload"
                end
                local rt_entry = runtime_chunk()
                if type(rt_entry) ~= "function" then
                        return nil, "runtime"
                end
                return rt_entry({
                        b = pl.bundle,
                        c = pl.const_key,
                        s = fetch_value,
                        env = _G,
                })
        end
end
