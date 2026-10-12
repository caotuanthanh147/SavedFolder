local T = dofile("bad_luau_transform.lua")
if type(T) == "boolean" then T = dofile("bad_luau_transform.lua") end
local M = type(T) == "table" and (T.M or T) or nil
assert(type(M) == "table" and type(M.transform) == "function", "transformer not loaded")
local STUB = setmetatable({}, { __index = function() return function() end end, __newindex = function() end })
local function conv(srcName, outName)
    local f = io.open(srcName, "r")
    assert(f, "missing " .. srcName)
    local src = f:read("*a")
    f:close()
    local out = M.transform(src)
    local ok, err = load(out, "@" .. outName, "t", STUB)
    if not ok then
        error(outName .. " does not compile after transform: " .. tostring(err))
    end
    local o = io.open(outName, "w")
    o:write(out)
    o:close()
    print(outName .. ": transformed OK (" .. #out .. " bytes)")
end
local names = { "AlienConfig", "CareerConfig", "HackRhythm", "HalloweenConfig", "LaptopFightConfig", "VerityConfig", "VerityPath" }
for _, n in ipairs(names) do
    conv("dgf_real/" .. n .. "_raw.lua", "dgf_real/" .. n .. ".lua")
end
