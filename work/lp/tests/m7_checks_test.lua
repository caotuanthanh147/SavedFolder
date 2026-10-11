-- m7_checks_test.lua — M7 s2 §11 checks module test suite (lua5.4).
-- Usage: lua5.4 tests/m7_checks_test.lua   (from the repo root)
-- Covers D-M7-13..18: identity-over-time, header teach/inject/modify,
-- timing inflation, env consistency, digest, report wire + silence.

local ROOT = "."
if arg and arg[0] and arg[0]:match("tests") then
        local f = io.open("loader/checks/env_checks.lua", "r")
        if f then
                f:close()
        else
                ROOT = ".."
        end
end
package.path = ROOT .. "/?.lua;" .. ROOT .. "/tests/?.lua;" .. package.path

local function load_module(path)
        local f = assert(loadfile(ROOT .. "/" .. path))
        return f()
end

local B = load_module("loader/crypto/bit.lua")()
local sha2 = load_module("loader/crypto/sha2.lua")(B)
local hmac = load_module("loader/crypto/hmac.lua")(B, sha2)
local encoding = load_module("loader/crypto/encoding.lua")()
local Crypto = { sha2 = sha2, hmac = hmac, encoding = encoding }
local checks_chunk = load_module("loader/checks/env_checks.lua")


-- Silence net: the module must never print (§11). The runner may print
-- (through real_print, never through the counting stub).
local prints = 0
local real_print = print
_G.print = function(...)
        prints = prints + 1
end

local passed, failed = 0, 0
local function check(name, got, want)
        if got == want then
                passed = passed + 1
                real_print("pass: " .. name)
        else
                failed = failed + 1
                real_print("FAIL: " .. name .. "\n  got:  " .. tostring(got) .. "\n  want: " .. tostring(want))
        end
end

local function json_encode(v)
        local t = type(v)
        if t == "number" then
                return string.format("%d", v)
        elseif t == "string" then
                return '"' .. v:gsub('["\\]', { ['"'] = '\\"', ['\\'] = '\\\\' }) .. '"'
        elseif t == "table" then
                local parts = {}
                for k, val in pairs(v) do
                        parts[#parts + 1] = '"' .. tostring(k) .. '":' .. json_encode(val)
                end
                return "{" .. table.concat(parts, ",") .. "}"
        end
        return "null"
end

-- Mock Env. opts: { inject = fn(opts) mutates opts.Headers during the call
-- (executor/spy behavior, doc §1.2.9); respond = fn(call) -> response table;
-- clock = fn() }. Returns env + call log.
local function make_env(opts)
        opts = opts or {}
        local calls = {}
        local env = {
                json_encode = json_encode,
                os_time = function()
                        return 1700000000
                end,
                random_bytes = function(n)
                        return string.rep("\0", n)
                end,
                clock = opts.clock,
        }
        env.request = function(o)
                local log = {
                        method = o.Method,
                        url = o.Url,
                        headers = {},
                        body = o.Body,
                }
                for k, v in pairs(o.Headers) do
                        log.headers[k] = v
                end
                calls[#calls + 1] = log
                if opts.inject then
                        opts.inject(o, #calls)
                end
                if opts.respond then
                        return opts.respond(log, #calls)
                end
                return { StatusCode = 200, Body = "{}" }
        end
        return env, calls
end

local CFG = {
        script_id = "a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6",
        base_url = "https://api.example.test",
        proof_key = "unit-test-proof-key",
        lv = "test-lv",
}

-- The factory chunk binds Crypto + Env (M3 pattern): one chunk call per Env.
local function new_checks(env)
        return checks_chunk(Crypto, env).new(CFG)
end

local function find_fail(failures, checkname, detail)
        for _, f in ipairs(failures) do
                if f.check == checkname and (detail == nil or f.detail == detail) then
                        return true
                end
        end
        return false
end

------------------------------------------------------------------ clean run

do
        local env = make_env()
        local c = new_checks(env)
        check("capture returns true", c:capture(), true)
        local failures = c:run()
        check("clean run has 0 failures", #failures, 0)
        check("digest is 64 hex", #c:digest(), 64)
        check("digest hex only", c:digest():match("^[0-9a-f]+$") ~= nil, true)
end

------------------------------------------------------- digest determinism

do
        local d1, d2
        do
                local env = make_env()
                local c = new_checks(env)
                c:capture()
                d1 = c:digest()
        end
        do
                local env = make_env()
                local c = new_checks(env)
                c:capture()
                d2 = c:digest()
        end
        check("digest deterministic per env", d1 == d2, true)
        local d3
        do
                local saved = _G.loadstring
                _G.loadstring = function()
                        return nil
                end
                local env = make_env()
                local c = new_checks(env)
                c:capture()
                d3 = c:digest()
                _G.loadstring = saved
        end
        check("digest sensitive to env", d1 ~= d3, true)
end

--------------------------------------------------------- run before capture

do
        local env = make_env()
        local c = new_checks(env)
        check("run before capture: no baseline failures", #c:run(), 0)
        check("digest before capture empty", c:digest(), "")
end

-------------------------------------------------------- identity over time

do
        local env = make_env()
        local c = new_checks(env)
        c:capture()
        local saved = _G.loadstring
        _G.loadstring = function()
                return nil
        end
        local failures = c:run()
        _G.loadstring = saved
        check("identity swap detected", find_fail(failures, "identity.changed", "loadstring"), true)
        check("identity swap is the only failure", #failures, 1)
        -- Second run with the global restored: read-once semantics = clean.
        check("failures are read-once", #c:run(), 0)
end

do
        -- UNC global APPEARING after baseline (spy installed late).
        local env = make_env()
        local c = new_checks(env)
        c:capture()
        _G.hookfunction = function()
                return nil
        end
        local failures = c:run()
        _G.hookfunction = nil
        check("late UNC global install detected", find_fail(failures, "identity.changed", "hookfunction"), true)
end

do
        -- Active swapping during capture: _G __index returns a fresh closure
        -- per access → the double-catch records a baseline anomaly.
        local meta = { __index = function()
                return function()
                        return nil
                end
        end }
        local saved_meta = getmetatable(_G)
        setmetatable(_G, meta)
        local env = make_env()
        local c = new_checks(env)
        c:capture()
        setmetatable(_G, saved_meta)
        local failures = c:run()
        check("baseline double-catch fires", find_fail(failures, "identity.changed"), true)
end

---------------------------------------------------------------- env checks

do
        local env = make_env()
        local c = new_checks(env)
        c:capture()
        local saved_syn = _G.syn
        _G.syn = { request = function()
                return nil
        end }
        local failures = c:run()
        _G.syn = saved_syn
        check("syn table appearing late = env.changed", find_fail(failures, "env.changed", "syn"), true)
end

do
        local env = make_env()
        local c = new_checks(env)
        c:capture()
        _G.identify_executor = function()
                return "SpoofedExecutor"
        end
        local failures = c:run()
        _G.identify_executor = nil
        check("executor identity change = env.changed", find_fail(failures, "env.changed", "executor"), true)
end

------------------------------------------------------------------- headers

do
        -- Teach on first call: executor injects X-Executor-Id every call (fine);
        -- third call adds an unknown X-Spy-Trace (signal).
        local n = 0
        local env = make_env({
                inject = function(o, i)
                        o.Headers["X-Executor-Id"] = "unit-executor"
                        if i >= 3 then
                                o.Headers["X-Spy-Trace"] = "gotcha"
                        end
                end,
        })
        local c = new_checks(env)
        c:capture()
        for _ = 1, 3 do
                env.request({
                        Method = "GET",
                        Url = "https://api.example.test/sync",
                        Headers = { ["x-lv"] = "test-lv" },
                })
        end
        local failures = c:run()
        check("taught executor header is not a failure", find_fail(failures, "headers.injected", "x-executor-id"), false)
        check("unknown injected header detected", find_fail(failures, "headers.injected", "x-spy-trace"), true)
end

do
        -- Spy rewrites an SDK-set header value mid-call.
        local env = make_env({
                inject = function(o)
                        o.Headers["x-proof"] = "0000000000000000000000000000000000000000000000000000000000000000"
                end,
        })
        local c = new_checks(env)
        c:capture()
        for _ = 1, 2 do
                env.request({
                        Method = "GET",
                        Url = "https://api.example.test/sync",
                        Headers = { ["x-proof"] = "real-proof-value" },
                })
        end
        local failures = c:run()
        check("rewritten SDK header = headers.modified", find_fail(failures, "headers.modified", "x-proof"), true)
end

do
        -- Executor recasing a header key (legit variance, S1 #9) is NOT a signal.
        local env = make_env({
                inject = function(o)
                        local v = o.Headers["x-lv"]
                        o.Headers["x-lv"] = nil
                        o.Headers["X-LV"] = v
                end,
        })
        local c = new_checks(env)
        c:capture()
        for _ = 1, 2 do
                env.request({
                        Method = "GET",
                        Url = "https://api.example.test/sync",
                        Headers = { ["x-lv"] = "test-lv" },
                })
        end
        local failures = c:run()
        check("header recase is not a failure", #failures, 0)
end

do
        -- Injection dedup within one window + read-once across runs.
        local env = make_env({
                inject = function(o, i)
                        if i >= 2 then
                                o.Headers["X-Spy"] = "1"
                        end
                end,
        })
        local c = new_checks(env)
        c:capture()
        for _ = 1, 4 do
                env.request({
                        Method = "GET",
                        Url = "https://api.example.test/sync",
                        Headers = { ["x-lv"] = "test-lv" },
                })
        end
        local failures = c:run()
        local count = 0
        for _, f in ipairs(failures) do
                if f.check == "headers.injected" and f.detail == "x-spy" then
                        count = count + 1
                end
        end
        check("header failure deduped in window", count, 1)
        check("second run clean (read-once)", #c:run(), 0)
end

-------------------------------------------------------------------- timing

local function fake_clock(times)
        local i = 0
        return function()
                i = i + 1
                if times[i] ~= nil then
                        return times[i]
                end
                return times[#times] + math.floor((i - #times) / 2)
        end
end

-- Baseline: each sample costs 1 unit (18 clock reads: 9 samples × 2).
-- Run: each sample costs 100 units → median 100 vs 1 → 100x ≥ 20x.
do
        local base = {}
        for i = 0, 8 do
                base[#base + 1] = i * 2
                base[#base + 1] = i * 2 + 1
        end
        local runt = {}
        for i = 0, 4 do
                runt[#runt + 1] = 100 * i * 2
                runt[#runt + 1] = 100 * i * 2 + 100
        end
        -- One clock that serves baseline first, then run samples.
        local seq = {}
        for _, v in ipairs(base) do
                seq[#seq + 1] = v
        end
        for _, v in ipairs(runt) do
                seq[#seq + 1] = v
        end
        local env = make_env({ clock = fake_clock(seq) })
        local c = new_checks(env)
        c:capture()
        local failures = c:run()
        check("timing inflation detected", find_fail(failures, "timing.inflated"), true)
end

do
        -- 19x stays under the 20x threshold (D-M7-13: generous to low-end HW).
        local base = {}
        for i = 0, 8 do
                base[#base + 1] = i * 2
                base[#base + 1] = i * 2 + 1
        end
        local runt = {}
        for i = 0, 4 do
                runt[#runt + 1] = 19 * i * 2
                runt[#runt + 1] = 19 * i * 2 + 19
        end
        local seq = {}
        for _, v in ipairs(base) do
                seq[#seq + 1] = v
        end
        for _, v in ipairs(runt) do
                seq[#seq + 1] = v
        end
        local env = make_env({ clock = fake_clock(seq) })
        local c = new_checks(env)
        c:capture()
        local failures = c:run()
        check("19x under threshold passes", find_fail(failures, "timing.inflated"), false)
end

-------------------------------------------------------------------- report

do
        local env, calls = make_env()
        local c = new_checks(env)
        c:capture()
        local delivered = c:report("sess_tok_test_1234", { check = "headers.injected", detail = "x-spy-trace" })
        check("report delivered on 200", delivered, true)
        local last = calls[#calls]
        check("report path", last.url, "https://api.example.test/auth/" .. CFG.script_id .. "/heartbeat")
        check("report method", last.method, "POST")
        check("report body v", last.body:match('"v":1') ~= nil, true)
        check("report body session_token", last.body:match('"session_token":"sess_tok_test_1234"') ~= nil, true)
        check("report body tamper.check", last.body:match('"check":"headers.injected"') ~= nil, true)
        check("report body tamper.detail", last.body:match('"detail":"x%-spy%-trace"') ~= nil, true)
        -- Proof header recomputation (same formula as loader/sdk/library.lua).
        local ts = last.headers["x-ts"]
        local nonce = last.headers["x-nonce"]
        local body_hash = encoding.hex_encode(sha2.sha256(last.body))
        local proof_input = "POST" .. "|" .. "/auth/" .. CFG.script_id .. "/heartbeat" .. "|" .. ts .. "|" .. nonce .. "|" .. body_hash
        local want_proof = encoding.hex_encode(hmac.hmac_sha256(CFG.proof_key, proof_input))
        check("report x-proof valid", last.headers["x-proof"], want_proof)
        check("report x-lv", last.headers["x-lv"], CFG.lv)
end

do
        local env, calls = make_env({
                respond = function()
                        return { StatusCode = 500, Body = "boom" }
                end,
        })
        local c = new_checks(env)
        c:capture()
        local delivered = c:report("sess_tok_test_1234", { check = "timing.inflated", detail = "25.0x" })
        check("report 500 → not delivered, no raise", delivered, false)
        check("report 500 still made the call", #calls, 1)
end

do
        local env, calls = make_env()
        local c = new_checks(env)
        c:capture()
        local delivered = c:report("", { check = "x" })
        check("report without session_token is a no-op", delivered, false)
        check("report no-op fired no request", #calls, 0)
end

------------------------------------------------- degrade: no Env.request

do
        local env = make_env()
        env.request = nil
        local c = new_checks(env)
        check("no-request env: capture works", c:capture(), true)
        check("no-request env: run clean", #c:run(), 0)
        check("no-request env: report unavailable", c:report("st", { check = "x" }), false)
end

------------------------------------------------------------------- silence

_G.print = real_print
check("module never printed", prints, 0)

print(string.format("\n%d passed, %d failed", passed, failed))
if failed > 0 then
        os.exit(1)
end
