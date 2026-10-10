-- harness.lua — executor-environment simulator for M13 loader stubs.
-- Usage: lua5.4 harness.lua <scenario> <stub1.lua> <stub2.lua|-> <init.lua> <tmpdir>
--
-- Simulates the UNC-standard executor surface (request, readfile, writefile,
-- isfile, isfolder, makefolder, bit32, loadstring) over a real temp directory
-- so the stub's on-disk cache behavior is exercised against actual files.
-- Exit code 0 = all scenario assertions passed; 1 = failures (printed).

local scenario = assert(arg[1], "scenario required")
local stub1path = assert(arg[2], "stub1 path required")
local stub2path = assert(arg[3], "stub2 path or '-'")
local initpath = assert(arg[4], "init path required")
local tmpdir = assert(arg[5], "tmpdir required")

local function readfile_real(path)
  local f = assert(io.open(path, "rb"))
  local d = f:read("a")
  f:close()
  return d
end

local INIT_BYTES = readfile_real(initpath)

-- Recorder shared with the mock init fixture via _G.
local REC = { requests = 0, initRuns = 0, entryCalls = 0, payload = nil, printed = {}, lastUrl = nil }
_G._REC = REC

-- Request behavior flags per scenario.
local REQ = { fail = false, bodyOverride = nil }

-- Extract embedded constants from a rendered stub (proves pass-through of
-- the stub's OWN per-fetch values to the init entry payload). The value
-- pattern stops at end-of-line without consuming it so consecutive
-- "local X = value" lines all match.
local function extract(src)
  local out = {}
  for name, value in src:gmatch("\nlocal ([A-Z_]+) = ([^\n]*)") do
    out[name] = value
  end
  return out
end

local function unquote(literal)
  return literal:match('^"(.*)"$')
end

local S1 = extract(readfile_real(stub1path))
local S2 = stub2path ~= "-" and extract(readfile_real(stub2path)) or nil

-- bit32 shim (Luau builtin; lua5.4 native ops).
local bit32_shim = { bxor = function(a, b) return (a ~ b) % 0x100000000 end }

local function loadstring_shim(src, name)
  return load(src, name or "=(load)", "t", _G)
end

local function q(path)
  return "'" .. path .. "'"
end

local function wpath(p)
  return tmpdir .. "/" .. p
end

-- FS mocks backed by the real filesystem (workspace = tmpdir).
local function mock_readfile(p)
  local f = io.open(wpath(p), "rb")
  if not f then error("readfile: " .. p, 0) end
  local d = f:read("a")
  f:close()
  return d
end

local function mock_writefile(p, d)
  local f = io.open(wpath(p), "wb")
  if not f then error("writefile: " .. p, 0) end
  f:write(d)
  f:close()
end

local function mock_isfile(p)
  local f = io.open(wpath(p), "rb")
  if not f then return false end
  f:close()
  return true
end

local function mock_isfolder(p)
  return os.execute("test -d " .. q(wpath(p)))
end

local function mock_makefolder(p)
  os.execute("mkdir -p " .. q(wpath(p)))
end

local function mock_request(opts)
  REC.requests = REC.requests + 1
  REC.lastUrl = opts.Url
  if REQ.fail then
    return { Success = false, StatusCode = 0, Body = "" }
  end
  return { Success = true, StatusCode = 200, Body = REQ.bodyOverride or INIT_BYTES }
end

local function mock_print(...)
  local parts = {}
  for i = 1, select("#", ...) do parts[i] = tostring(select(i, ...)) end
  REC.printed[#REC.printed + 1] = table.concat(parts, " ")
end

-- Per-run env options (mutated between stub runs by scenarios).
local OPTS = {}

local function makeEnv()
  local o = {}
  if not OPTS.no_request then o.request = mock_request end
  if not OPTS.no_loadstring then o.loadstring = loadstring_shim end
  if not OPTS.no_bit32 then o.bit32 = bit32_shim end
  if not OPTS.no_fs then
    o.readfile = mock_readfile
    o.writefile = OPTS.write_fail and function() error("EACCES", 0) end or mock_writefile
    o.isfile = mock_isfile
    o.isfolder = mock_isfolder
    o.makefolder = mock_makefolder
  end
  o.print = mock_print
  return setmetatable(o, { __index = _G })
end

local function runStub(path)
  local src = readfile_real(path)
  local chunk = assert(load(src, "=stub", "t", makeEnv()))
  chunk()
end

-- Workspace file helpers for scenario tampering.
local function cacheFile()
  local build = unquote(assert(S1.BUILD, "BUILD not embedded"))
  return "lp/init_" .. build .. ".lua"
end

local function writeWorkspace(rel, data)
  mock_makefolder(rel:match("^(.*)/[^/]+$") or ".")
  mock_writefile(rel, data)
end

local function readWorkspace(rel)
  return mock_readfile(rel)
end

-- Assertion collection.
local failures = {}
local function check(cond, msg)
  if cond then
    print("  ok  " .. msg)
  else
    failures[#failures + 1] = msg
    print("  FAIL " .. msg)
  end
end

local function failedPrinted()
  for _, p in ipairs(REC.printed) do
    if p:find("loader failed", 1, true) then return true end
  end
  return false
end

local function checkPayloadAgainst(stubConsts, label)
  local p = REC.payload
  check(p ~= nil, label .. ": init entry received payload")
  if not p then return end
  check(p.api == unquote(stubConsts.API), label .. ": payload.api = " .. tostring(p.api))
  check(p.script_id == unquote(stubConsts.SCRIPT_ID), label .. ": payload.script_id = " .. tostring(p.script_id))
  check(p.build == unquote(stubConsts.BUILD), label .. ": payload.build = " .. tostring(p.build))
  check(p.t == tonumber(stubConsts.FETCH_T), label .. ": payload.t = " .. tostring(p.t))
  check(p.s == unquote(stubConsts.STUB_ID), label .. ": payload.s = " .. tostring(p.s))
  check(p.r == unquote(stubConsts.STUB_R), label .. ": payload.r = " .. tostring(p.r))
end

-- ---- scenarios ----

if scenario == "fresh" then
  runStub(stub1path)
  check(REC.requests == 1, "fresh: exactly one init download")
  check(REC.initRuns == 1 and REC.entryCalls == 1, "fresh: init ran once")
  check(not failedPrinted(), "fresh: no failure message")
  checkPayloadAgainst(S1, "fresh")
  check(mock_isfile(cacheFile()), "fresh: init cached to " .. cacheFile())
  check(readWorkspace(cacheFile()) == INIT_BYTES, "fresh: cached bytes identical to served bytes")
  check(REC.lastUrl ~= nil and REC.lastUrl:find("/static/init_", 1, true), "fresh: download URL targets /static/init_")

elseif scenario == "cache-hit" then
  runStub(stub1path)
  check(REC.requests == 1, "cache-hit: first run downloads once")
  runStub(stub2path)
  check(REC.requests == 1, "cache-hit: second run served from cache (no second download)")
  check(REC.initRuns == 2 and REC.entryCalls == 2, "cache-hit: init ran both times")
  check(not failedPrinted(), "cache-hit: no failure message")
  checkPayloadAgainst(S2, "cache-hit(second stub)")

elseif scenario == "corrupt-cache" then
  runStub(stub1path)
  check(REC.requests == 1, "corrupt-cache: first run downloads")
  local cached = readWorkspace(cacheFile())
  local pos = 37
  local orig = cached:sub(pos, pos)
  local flipped = orig == "a" and "b" or "a"
  writeWorkspace(cacheFile(), cached:sub(1, pos - 1) .. flipped .. cached:sub(pos + 1))
  runStub(stub2path)
  check(REC.requests == 2, "corrupt-cache: tampered cache detected, re-downloaded")
  check(REC.initRuns == 2, "corrupt-cache: init ran from repaired source")
  check(not failedPrinted(), "corrupt-cache: no failure message")
  check(readWorkspace(cacheFile()) == INIT_BYTES, "corrupt-cache: cache repaired with valid bytes")
  checkPayloadAgainst(S2, "corrupt-cache(second stub)")

elseif scenario == "truncated-cache" then
  runStub(stub1path)
  local cached = readWorkspace(cacheFile())
  writeWorkspace(cacheFile(), cached:sub(1, math.floor(#cached * 0.4)))
  runStub(stub2path)
  check(REC.requests == 2, "truncated-cache: size mismatch detected, re-downloaded")
  check(REC.initRuns == 2, "truncated-cache: init ran after repair")
  check(readWorkspace(cacheFile()) == INIT_BYTES, "truncated-cache: cache repaired")
  check(not failedPrinted(), "truncated-cache: no failure message")

elseif scenario == "no-bit32" then
  OPTS.no_bit32 = true
  runStub(stub1path)
  check(REC.requests == 1 and REC.initRuns == 1, "no-bit32: valid init accepted via DJB2+size")
  check(not failedPrinted(), "no-bit32: no failure message")
  checkPayloadAgainst(S1, "no-bit32")
  local cached = readWorkspace(cacheFile())
  local pos = 41
  local flipped = cached:sub(pos, pos) == "a" and "b" or "a"
  writeWorkspace(cacheFile(), cached:sub(1, pos - 1) .. flipped .. cached:sub(pos + 1))
  runStub(stub2path)
  check(REC.requests == 2, "no-bit32: same-size tamper still detected by DJB2")
  check(REC.initRuns == 2, "no-bit32: init ran after repair")

elseif scenario == "write-fail" then
  OPTS.write_fail = true
  runStub(stub1path)
  check(REC.requests == 1 and REC.initRuns == 1, "write-fail: init downloaded and ran without cache")
  check(not failedPrinted(), "write-fail: no failure message (cache write is best-effort)")
  check(not mock_isfile(cacheFile()), "write-fail: no cache file left behind")

elseif scenario == "download-fail" then
  REQ.fail = true
  runStub(stub1path)
  check(REC.requests == 1, "download-fail: request attempted")
  check(REC.initRuns == 0 and REC.entryCalls == 0, "download-fail: init NOT loaded")
  check(failedPrinted(), "download-fail: generic failure message shown")
  check(not mock_isfile(cacheFile()), "download-fail: nothing cached")

elseif scenario == "bad-body" then
  REQ.bodyOverride = "x" .. INIT_BYTES:sub(2) -- same length, first byte tampered
  runStub(stub1path)
  check(REC.requests == 1, "bad-body: request attempted")
  check(REC.initRuns == 0, "bad-body: tampered body rejected before loadstring")
  check(failedPrinted(), "bad-body: generic failure message shown")
  check(not mock_isfile(cacheFile()), "bad-body: nothing cached")

elseif scenario == "no-request" then
  OPTS.no_request = true
  runStub(stub1path)
  check(REC.initRuns == 0, "no-request: init NOT loaded")
  check(failedPrinted(), "no-request: generic failure message shown")
  check(REC.requests == 0, "no-request: no request made")

elseif scenario == "no-loadstring" then
  OPTS.no_loadstring = true
  runStub(stub1path)
  check(REC.initRuns == 0, "no-loadstring: init NOT loaded")
  check(failedPrinted(), "no-loadstring: generic failure message shown")

else
  print("unknown scenario: " .. tostring(scenario))
  os.exit(2)
end

print(string.format("scenario %s: %d failure(s)", scenario, #failures))
if #failures > 0 then os.exit(1) end
os.exit(0)
