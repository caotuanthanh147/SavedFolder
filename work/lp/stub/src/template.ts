/**
 * The Lua stub template (doc.md §5.6). Rendered per fetch by the generator:
 * every stub embeds fresh per-fetch values (fetch time, stub id, per-stub
 * random) plus the expected size + dual 32-bit hashes of the init build it
 * targets, so a saved or corrupted copy fails validation.
 *
 * Lua compatibility: plain Lua 5.1 syntax (runs on Luau executors and on
 * plain Lua 5.x for testing). Structured control flow only. Feature-checked
 * executor APIs: request + loadstring are required; readfile/writefile/
 * isfile/isfolder/makefolder and bit32 are optional (cache degrades,
 * loading still works).
 */

export interface TemplateValues {
  api: string;
  staticBase: string;
  scriptId: string;
  build: string;
  fetchT: number;
  stubId: string;
  stubR: string;
  expectLen: number;
  expectFnv: number;
  expectDjb: number;
  cacheDir: string;
}

/** Escape a string into a safe single-line Lua string literal. */
export function escapeLuaString(s: string): string {
  let out = '"';
  for (let i = 0; i < s.length; i++) {
    const c = s.charCodeAt(i);
    if (c === 92) out += "\\\\";
    else if (c === 34) out += '\\"';
    else if (c === 10) out += "\\n";
    else if (c === 13) out += "\\r";
    else if (c < 32 || c > 126) out += "\\" + String(c).padStart(3, "0");
    else out += String.fromCharCode(c);
  }
  return out + '"';
}

function luaInt(n: number, name: string): string {
  if (!Number.isInteger(n) || n < 0 || n > Number.MAX_SAFE_INTEGER) {
    throw new Error(`template value ${name} must be a safe non-negative integer, got ${n}`);
  }
  return String(n);
}

export function renderStub(v: TemplateValues): string {
  return `-- generated per fetch; unique; do not save — always run from the loader link
local API = ${escapeLuaString(v.api)}
local STATIC = ${escapeLuaString(v.staticBase)}
local SCRIPT_ID = ${escapeLuaString(v.scriptId)}
local BUILD = ${escapeLuaString(v.build)}
local FETCH_T = ${luaInt(v.fetchT, "fetchT")}
local STUB_ID = ${escapeLuaString(v.stubId)}
local STUB_R = ${escapeLuaString(v.stubR)}
local EXPECT_LEN = ${luaInt(v.expectLen, "expectLen")}
local EXPECT_FNV = ${luaInt(v.expectFnv, "expectFnv")}
local EXPECT_DJB = ${luaInt(v.expectDjb, "expectDjb")}
local CACHE_DIR = ${escapeLuaString(v.cacheDir)}

local function fail()
  print("loader failed; run the loader link again")
end

local function mul32(a, b)
  local al = a % 65536
  local ah = (a - al) / 65536
  local bl = b % 65536
  local bh = (b - bl) / 65536
  return (al * bl + ((al * bh + ah * bl) % 65536) * 65536) % 4294967296
end

local bxor = bit32 and bit32.bxor or nil

local function hash_djb(data)
  local h = 5381
  for i = 1, #data do
    h = (mul32(h, 33) + string.byte(data, i)) % 4294967296
  end
  return h
end

local function hash_fnv(data)
  local h = 2166136261
  for i = 1, #data do
    h = mul32(bxor(h, string.byte(data, i)), 16777619)
  end
  return h
end

local function valid(data)
  if #data ~= EXPECT_LEN then return false end
  if hash_djb(data) ~= EXPECT_DJB then return false end
  if bxor and hash_fnv(data) ~= EXPECT_FNV then return false end
  return true
end

local function run(data)
  local chunk = loadstring(data, "=lp-init")
  if not chunk then return fail() end
  local ok, entry = pcall(chunk)
  if not ok or type(entry) ~= "function" then return fail() end
  local ok2 = pcall(entry, {
    api = API,
    script_id = SCRIPT_ID,
    build = BUILD,
    t = FETCH_T,
    s = STUB_ID,
    r = STUB_R,
  })
  if not ok2 then fail() end
end

if type(request) ~= "function" or type(loadstring) ~= "function" then
  return fail()
end

local cache_file = CACHE_DIR .. "/init_" .. BUILD .. ".lua"

if type(readfile) == "function" then
  local exists = false
  if type(isfile) == "function" then
    exists = isfile(cache_file)
  else
    exists = pcall(readfile, cache_file)
  end
  if exists then
    local ok, data = pcall(readfile, cache_file)
    if ok and type(data) == "string" and valid(data) then
      return run(data)
    end
  end
end

local ok, resp = pcall(request, {
  Url = STATIC .. "/static/init_" .. BUILD .. ".lua",
  Method = "GET",
})
if not ok
  or type(resp) ~= "table"
  or resp.Success ~= true
  or resp.StatusCode ~= 200
  or type(resp.Body) ~= "string"
  or not valid(resp.Body)
then
  return fail()
end

local data = resp.Body

if type(writefile) == "function" then
  if type(isfolder) ~= "function" or not isfolder(CACHE_DIR) then
    if type(makefolder) == "function" then pcall(makefolder, CACHE_DIR) end
  end
  pcall(writefile, cache_file, data)
end

run(data)
`;
}
