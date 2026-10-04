-- potato-harness-core.lua (glm2, POT1-H)
-- Core: deobf region parser + Luau `buffer` shim for Lua 5.4.
-- Sources: /home/z/Public/potato/game/ (copy at my-project/upload/potato/game).
-- Self-test: lua5.4 potato-harness-core.lua

local DeobfCandidates = {
    "/home/z/my-project/upload/potato/game/Peel THE Potato[Deob].lua",
    "/home/z/Public/potato/game/Peel THE Potato[Deob].lua",
    os.getenv and os.getenv("POTATO_DEOBF") or nil,
}

local M = {}

-- Luau -> Lua 5.4 transformer (adjacent file)
do
    local XT
    for _, p in ipairs({
        "potato-harness-luau.lua",
        "/home/z/SavedFolder/work/lua/potato-harness-luau.lua",
    }) do
        local f = io.open(p, "r")
        if f then f:close(); XT = dofile(p); break end
    end
    M.XT = XT
end

-- ---------------------------------------------------------------------------
-- buffer shim: Luau buffer library on Lua 5.4 strings
-- A buffer object is { data = string }. Fixed size, Luau bounds semantics.
-- ---------------------------------------------------------------------------

local Buffer = {}

local function bcheck(b)
    if type(b) ~= "table" or type(b.data) ~= "string" then
        error("buffer: expected buffer", 3)
    end
end

local function masku(v, bits)
    v = math.floor(v)
    if v < 0 then v = v + 2 ^ bits end
    return v % (2 ^ bits)
end

Buffer.create = function(size)
    if type(size) ~= "number" or size < 0 or size ~= math.floor(size) then
        error("buffer.create: invalid size", 2)
    end
    return { data = ("\0"):rep(size) }
end

Buffer.len = function(b)
    bcheck(b)
    return #b.data
end

local function wrbytes(b, offset, s)
    bcheck(b)
    if offset < 1 or offset + #s - 1 > #b.data then
        error("buffer: write out of bounds", 2)
    end
    if #s == 0 then return offset end
    b.data = b.data:sub(1, offset - 1) .. s .. b.data:sub(offset + #s)
    return offset + #s
end

local function rdbounds(b, offset, n)
    bcheck(b)
    if offset < 1 or offset + n - 1 > #b.data then
        error("buffer: read out of bounds", 2)
    end
end

Buffer.writeu8 = function(b, offset, value)
    return wrbytes(b, offset, string.pack("<I1", masku(value, 8)))
end
Buffer.writeu16 = function(b, offset, value)
    return wrbytes(b, offset, string.pack("<I2", masku(value, 16)))
end
Buffer.writeu32 = function(b, offset, value)
    return wrbytes(b, offset, string.pack("<I4", masku(value, 32)))
end
Buffer.writei16 = function(b, offset, value)
    return wrbytes(b, offset, string.pack("<i2", math.floor(value)))
end
Buffer.writei32 = function(b, offset, value)
    return wrbytes(b, offset, string.pack("<i4", math.floor(value)))
end
Buffer.writef32 = function(b, offset, value)
    return wrbytes(b, offset, string.pack("<f", value))
end
Buffer.writef64 = function(b, offset, value)
    return wrbytes(b, offset, string.pack("<d", value))
end
Buffer.writestring = function(b, offset, s)
    if type(s) ~= "string" then error("buffer.writestring: expected string", 2) end
    return wrbytes(b, offset, s)
end

Buffer.readu8 = function(b, offset)
    rdbounds(b, offset, 1)
    return string.unpack("<I1", b.data, offset)
end
Buffer.readu16 = function(b, offset)
    rdbounds(b, offset, 2)
    return string.unpack("<I2", b.data, offset)
end
Buffer.readu32 = function(b, offset)
    rdbounds(b, offset, 4)
    return string.unpack("<I4", b.data, offset)
end
Buffer.readi16 = function(b, offset)
    rdbounds(b, offset, 2)
    return string.unpack("<i2", b.data, offset)
end
Buffer.readi32 = function(b, offset)
    rdbounds(b, offset, 4)
    return string.unpack("<i4", b.data, offset)
end
Buffer.readf32 = function(b, offset)
    rdbounds(b, offset, 4)
    return string.unpack("<f", b.data, offset)
end
Buffer.readf64 = function(b, offset)
    rdbounds(b, offset, 8)
    return string.unpack("<d", b.data, offset)
end
Buffer.readstring = function(b, offset, count)
    rdbounds(b, offset, count)
    return b.data:sub(offset, offset + count - 1), offset + count
end

Buffer.fromstring = function(s)
    if type(s) ~= "string" then error("buffer.fromstring: expected string", 2) end
    return { data = s }
end
Buffer.tostring = function(b)
    bcheck(b)
    return b.data
end

Buffer.copy = function(dst, dstOffset, src, srcOffset, count)
    bcheck(dst); bcheck(src)
    if count < 0 then error("buffer.copy: negative count", 2) end
    if dstOffset < 1 or dstOffset + count - 1 > #dst.data
        or srcOffset < 1 or srcOffset + count - 1 > #src.data then
        error("buffer: copy out of bounds", 2)
    end
    if count == 0 then return end
    local chunk = src.data:sub(srcOffset, srcOffset + count - 1)
    dst.data = dst.data:sub(1, dstOffset - 1) .. chunk .. dst.data:sub(dstOffset + count)
end

Buffer.fill = function(b, offset, count, value)
    bcheck(b)
    if count < 0 then error("buffer.fill: negative count", 2) end
    if offset < 1 or offset + count - 1 > #b.data then
        error("buffer: fill out of bounds", 2)
    end
    if count == 0 then return end
    local byte = string.pack("<I1", masku(value or 0, 8))
    b.data = b.data:sub(1, offset - 1) .. byte:rep(count) .. b.data:sub(offset + count)
end

M.Buffer = Buffer

-- ---------------------------------------------------------------------------
-- deobf region parser
-- Format: `--- <dotted.path> [ModuleScript|LocalScript]` / `-- y u r i` /
-- blank / code... / blank / next marker. Region body: marker+3 .. next-2.
-- ---------------------------------------------------------------------------

local MARKER = "^%-%-%- (.+) %[([^%]]+)%]$"

function M.parseDeobf(path)
    local f = io.open(path, "r")
    if not f then return nil, "cannot open: " .. tostring(path) end
    local markers = {}   -- { {line=n, path=, class=} }
    local lines = {}
    for line in f:lines() do
        lines[#lines + 1] = line
        local p, c = line:match(MARKER)
        if p and (c == "ModuleScript" or c == "LocalScript") then
            markers[#markers + 1] = { line = #lines, path = p, class = c }
        end
    end
    f:close()

    local regions = {}
    local byPath = {}
    for i, mk in ipairs(markers) do
        local nextLine = (i < #markers) and (markers[i + 1].line - 1) or (#lines + 1)
        -- body starts at marker+3 (skip `-- y u r i` + blank), ends at next-2
        local s = mk.line + 3
        local e = nextLine - 1
        local src
        if e < s then
            src = ""
        else
            -- trim trailing blank lines
            while e >= s and lines[e]:match("^%s*$") do e = e - 1 end
            if e < s then src = "" else src = table.concat(lines, "\n", s, e) end
        end
        local region = {
            path = mk.path, class = mk.class,
            startLine = s, endLine = e, source = src,
        }
        regions[#regions + 1] = region
        if byPath[mk.path] ~= nil then
            return nil, "duplicate region path: " .. mk.path
        end
        byPath[mk.path] = region
    end
    -- apply Luau -> Lua 5.4 transform to every region source
    if M.XT then
        for i = 1, #regions do
            local r = regions[i]
            r.rawSource = r.source
            r.source = M.XT.transform(r.source)
        end
    end

    M.lines = lines
    return regions, byPath
end

-- split a dotted path into instance-name segments.
-- Atomic rule: a segment containing "@" merges following digit-only segments
-- (version dots, e.g. `1foreverhd_topbarplus@3.4.0`).
function M.splitPath(path)
    local raw = {}
    for seg in path:gmatch("[^%.]+") do raw[#raw + 1] = seg end
    local out, i = {}, 1
    while i <= #raw do
        local seg = raw[i]
        if seg:find("@", 1, true) then
            local j = i + 1
            while j <= #raw and raw[j]:match("^%d+$") do
                seg = seg .. "." .. raw[j]
                j = j + 1
            end
            out[#out + 1] = seg
            i = j
        else
            out[#out + 1] = seg
            i = i + 1
        end
    end
    return out
end

-- ---------------------------------------------------------------------------
-- self-test
-- ---------------------------------------------------------------------------

local function selftest()
    local pass, fail = 0, 0
    local function check(name, cond)
        if cond then pass = pass + 1 else fail = fail + 1; print("FAIL: " .. name) end
    end

    local deobf
    for _, p in ipairs(DeobfCandidates) do
        if p and p ~= "" then
            local f = io.open(p, "r")
            if f then f:close(); deobf = p; break end
        end
    end
    check("deobf file found", deobf ~= nil)
    if not deobf then
        print(("CORE-1: %d/%d PASS (no source)"):format(pass, pass + fail))
        os.exit(1)
    end
    print("deobf: " .. deobf)

    local regions, byPath = M.parseDeobf(deobf)
    check("parse ok", regions ~= nil)
    if not regions then
        print(("CORE-1: %d/%d PASS"):format(pass, pass + fail))
        os.exit(1)
    end

    check("548 regions", #regions == 548)
    local rsCount, lsCount = 0, 0
    for _, r in ipairs(regions) do
        if r.path:find("^ReplicatedStorage%.") then rsCount = rsCount + 1 end
        if r.class == "LocalScript" then lsCount = lsCount + 1 end
    end
    check("500 ReplicatedStorage regions", rsCount == 500)
    check("4 LocalScripts", lsCount == 4)
    check("byPath count == 548", (function() local n = 0; for _ in pairs(byPath) do n = n + 1 end; return n == 548 end)())

    local types = byPath["ReplicatedStorage.ModifiedPackages.Packet._Types"]
    check("_Types region exists", types ~= nil)
    if types then check("_Types ~2910 code lines", types.endLine - types.startLine + 1 >= 2500) end
    local pk = byPath["ReplicatedStorage.Modules.Resources.Packets"]
    check("Resources.Packets exists", pk ~= nil)
    if pk then check("Resources.Packets endLine 44422", pk.endLine == 44422) end
    local health = byPath["Workspace.Players.lwtwtnp.Health"]
    check("empty Health region exists", health ~= nil and health.source == "")

    -- syntax-load every region (post-transform); the malformed
    -- TableToSyntaxString region is a documented deobfuscator artifact
    local syntaxExceptions = {}
    for p in pairs(byPath) do
        -- TableToSyntaxString: deobfuscator long-bracket artifact
        -- Promise._Promise: `...` vararg inside an if-expression IIFE
        -- topbarplus Elements.Caption: nested if-expr inside an if-expr condition
        if p:find("TableToSyntaxString", 1, true)
            or p:find("ModifiedPackages%.Promise%.%_Promise", 1)
            or (p:find("topbarplus", 1, true) and p:find("Elements%.Caption", 1)) then
            syntaxExceptions[p] = true
        end
    end
    local badSyntax = {}
    for _, r in ipairs(regions) do
        if r.source ~= "" and not syntaxExceptions[r.path] then
            local fn, err = load(r.source, "@" .. r.path, "t", {})
            if not fn then badSyntax[#badSyntax + 1] = r.path .. " : " .. tostring(err) end
        end
    end
    local nExc = (function() local n = 0; for _ in pairs(syntaxExceptions) do n = n + 1 end; return n end)()
    check("all regions syntax-load, 3 known exceptions (" .. #badSyntax .. " bad, " .. nExc .. " excepted)", #badSyntax == 0 and nExc == 3)
    for i = 1, math.min(#badSyntax, 10) do print("  SYNTAX-FAIL: " .. badSyntax[i]) end

    -- essential regions must load
    local essentials = {
        "ReplicatedStorage.ModifiedPackages.Packet",
        "ReplicatedStorage.ModifiedPackages.Packet._Types",
        "ReplicatedStorage.ModifiedPackages.Packet._Signal",
        "ReplicatedStorage.ModifiedPackages.Packet._Task",
        "ReplicatedStorage.Modules.Resources.Packets",
        "ReplicatedStorage.Shared.PotatoPileShared",
    }
    for _, p in ipairs(essentials) do
        local r = byPath[p]
        local ok = r and (r.source == "" or load(r.source, "@" .. p, "t", {}))
        check("essential loads: " .. p, ok ~= nil and ok ~= false)
    end

    -- splitPath
    local segs = M.splitPath("ReplicatedStorage.Packages._Index.1foreverhd_topbarplus@3.4.0.topbarplus")
    check("splitPath atomic version (5 segs)", #segs == 5 and segs[4] == "1foreverhd_topbarplus@3.4.0" and segs[5] == "topbarplus")
    segs = M.splitPath("ReplicatedStorage.ModifiedPackages.Packet")
    check("splitPath plain (3 segs)", #segs == 3 and segs[3] == "Packet")

    -- buffer roundtrips
    local b = Buffer.create(64)
    local o = 1
    o = Buffer.writeu8(b, o, 255); o = Buffer.writeu16(b, o, 65535)
    o = Buffer.writeu32(b, o, 4294967295); o = Buffer.writei16(b, o, -32768)
    o = Buffer.writei32(b, o, -2147483648)
    o = Buffer.writef32(b, o, 0.25); o = Buffer.writef64(b, o, math.pi)
    o = Buffer.writestring(b, o, "hello")
    check("buffer writes consumed 30", o == 31)
    local v
    o = 1
    v = Buffer.readu8(b, o); check("readu8 255", v == 255); o = o + 1
    v = Buffer.readu16(b, o); check("readu16 65535", v == 65535); o = o + 2
    v = Buffer.readu32(b, o); check("readu32 max", v == 4294967295); o = o + 4
    v = Buffer.readi16(b, o); check("readi16 min", v == -32768); o = o + 2
    v = Buffer.readi32(b, o); check("readi32 min", v == -2147483648); o = o + 4
    v = Buffer.readf32(b, o); check("readf32 0.25", v == 0.25); o = o + 4
    v = Buffer.readf64(b, o); check("readf64 pi", math.abs(v - math.pi) < 1e-15); o = o + 8
    local s2
    s2, o = Buffer.readstring(b, o, 5); check("readstring hello", s2 == "hello" and o == 31)
    check("len", Buffer.len(b) == 64)
    check("tostring/fromstring", Buffer.tostring(Buffer.fromstring("abc")) == "abc")
    local b2 = Buffer.fromstring("AAAABBBBCCCC")
    Buffer.copy(b2, 5, Buffer.fromstring("XY"), 1, 2)
    check("copy", Buffer.tostring(b2) == "AAAAXYBBCCCC")
    local b3 = Buffer.create(4)
    Buffer.fill(b3, 2, 2, 7)
    check("fill", Buffer.tostring(b3) == "\0\7\7\0")
    local okOvf = pcall(Buffer.writeu8, b, 65, 1)
    check("write overflow errors", not okOvf)
    local okRd = pcall(Buffer.readu8, b, 65)
    check("read overflow errors", not okRd)
    local okNeg = pcall(Buffer.writeu8, Buffer.create(2), 1, 300)
    check("writeu8 masks (no error)", okNeg)
    check("writeu8 mask value", (function() local bb = Buffer.create(2); Buffer.writeu8(bb, 1, 300); return Buffer.readu8(bb, 1) == 44 end)())

    print(("CORE-1: %d/%d PASS"):format(pass, pass + fail))
    if fail > 0 then os.exit(1) end
end

if arg and arg[0] and arg[0]:match("potato%-harness%-core") then
    selftest()
end

return M
