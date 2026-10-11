local inRoblox = (game ~= nil)

local function banner(t)
  print(string.rep("=", 46))
  print("  " .. t)
  print(string.rep("=", 46))
end

banner("LP1 PROTECTION DEMO - guest program running")

local function fib(n)
  if n < 2 then
    return n
  end
  return fib(n - 1) + fib(n - 2)
end

local function gcd(a, b)
  if b == 0 then
    return a
  end
  return gcd(b, a % b)
end

local sieve = {}
for i = 1, 60 do
  sieve[i] = true
end
sieve[1] = false
for i = 2, 60 do
  if sieve[i] then
    local j = i * i
    while j <= 60 do
      sieve[j] = false
      j = j + i
    end
  end
end
local primes = {}
for i = 1, 60 do
  if sieve[i] then
    primes[#primes + 1] = i
  end
end

print(string.format("fib(22)=%d gcd(1071,462)=%d", fib(22), gcd(1071, 462)))
print("primes<=" .. 60 .. ": " .. table.concat(primes, ","))

local parts = { "LP", "1", "VM", "obfuscation" }
print("upper=" .. string.upper(table.concat(parts, "-")))
local b1 = string.byte("Lua", 1)
local b2 = string.byte("Lua", 2)
local b3 = string.byte("Lua", 3)
print("bytes=" .. b1 .. "," .. b2 .. "," .. b3)
print("chars=" .. string.char(76, 80, 86, 77))
print("rev=" .. string.reverse("protected"))
print(string.format("fmt=%5.2f|%+d|%s|%q", math.pi * 10, 42, "ok", 'a"b'))
print("find=" .. tostring(string.find("protected-payload", "pay", 1, true)))

local function counter(start, step)
  local n = start
  return function()
    n = n + step
    return n
  end
end
local c1 = counter(0, 3)
local c2 = counter(100, -7)
local seq = {}
for i = 1, 5 do
  seq[i] = c1() .. "/" .. c2()
end
print("counters=" .. table.concat(seq, " "))

local function makePair()
  local n = 0
  local function inc()
    n = n + 1
    return n
  end
  local function peek()
    return n
  end
  return inc, peek
end
local inc, peek = makePair()
inc()
inc()
inc()
print("shared-upvalue peek=" .. peek())

local Vec = {}
Vec.__index = Vec
Vec.__add = function(a, b)
  return Vec.new(a.x + b.x, a.y + b.y)
end
Vec.__tostring = function(v)
  return "(" .. v.x .. "," .. v.y .. ")"
end
function Vec.new(x, y)
  return setmetatable({ x = x, y = y }, Vec)
end
function Vec:len()
  return math.sqrt(self.x * self.x + self.y * self.y)
end
local v = Vec.new(3, 4) + Vec.new(1, 1)
local vs = tostring(v)
local vl = string.format("%.3f", v:len())
print("vec=" .. vs .. " len=" .. vl)

local function tally(...)
  local n = select("#", ...)
  local sum = 0
  for i = 1, n do
    sum = sum + select(i, ...)
  end
  return n, sum
end
local tn, tsum = tally(10, 20, 30, 40)
print(string.format("tally n=%d sum=%d", tn, tsum))

local ok, err = pcall(function()
  error("demo-error", 0)
end)
local pok, pres = pcall(function()
  return "recovered"
end)
local okstr = tostring(ok)
local errstr = tostring(err)
print("pcall ok=" .. okstr .. " err=" .. errstr)
local pokstr = tostring(pok)
print("pcall2 ok=" .. pokstr .. " ret=" .. pres)

local list = { 5, 3, 9, 1, 7 }
table.sort(list)
print("sorted=" .. table.concat(list, ","))
local m1 = math.max(3, 7)
local m2 = math.min(3, 7)
local m3 = math.floor(3.7)
local m4 = math.abs(-5)
print("math=" .. m1 .. "," .. m2 .. "," .. m3 .. "," .. m4)

if inRoblox then
  banner("ROBLOX ENVIRONMENT DETECTED")
  local okp, players = pcall(function()
    return game:GetService("Players")
  end)
  if okp and players then
    local oklp, lp = pcall(function()
      return players.LocalPlayer
    end)
    if oklp and lp then
      local pn = tostring(lp.Name)
      local dn = tostring(lp.DisplayName)
      print("player=" .. pn .. " display=" .. dn)
    else
      print("player=unavailable")
    end
  end
  local okw, ws = pcall(function()
    return game:GetService("Workspace")
  end)
  if okw and ws then
    local count = 0
    for _, ch in ipairs(ws:GetChildren()) do
      if ch then
        count = count + 1
      end
    end
    print("workspace children=" .. count)
  end
  print("placeId=" .. tostring(game.PlaceId))
  local okn = pcall(function()
    game:GetService("StarterGui"):SetCore("SendNotification", {
      Title = "LP1 VM",
      Text = "Obfuscated script is running",
      Duration = 6,
    })
  end)
  print("notification=" .. tostring(okn))
  for i = 1, 3 do
    if task and task.wait then
      task.wait(1)
    end
    print("tick " .. i .. "/3 - still running")
  end
else
  banner("CONSOLE ENVIRONMENT (plain Lua 5.4)")
  print("player=N/A (not in a Roblox host)")
  for i = 1, 3 do
    print("tick " .. i .. "/3 - still running")
  end
end

banner("DEMO OK - every section completed")
