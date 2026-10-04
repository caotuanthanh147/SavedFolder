-- potato-harness-luau.lua (glm2, POT1-H)
-- Token-level Luau -> Lua 5.4 source transform.
-- Corpus-verified surface: if-expressions (single-line, no elseif, no end),
-- `continue` statements. No compound assign / backticks / types / goto exist.
-- if-expr -> (function() if c then return a else return b end end)()
-- continue -> goto L<n> with ::L<n>:: inserted before the loop's end/until.

local M = {}

local KEYWORDS = {
    ["and"]=true,["break"]=true,["do"]=true,["else"]=true,["elseif"]=true,
    ["end"]=true,["false"]=true,["for"]=true,["function"]=true,["if"]=true,
    ["in"]=true,["local"]=true,["nil"]=true,["not"]=true,["or"]=true,
    ["repeat"]=true,["return"]=true,["then"]=true,["true"]=true,
    ["until"]=true,["while"]=true,["goto"]=true,
}

local OPS_EXPR_CONT = {
    ["="]=true, [","]=true, ["("]=true, ["{"]=true, ["["]=true,
    ["return"]=true, ["not"]=true, ["and"]=true, ["or"]=true,
    ["+"]=true, ["-"]=true, ["*"]=true, ["/"]=true, ["%"]=true, ["^"]=true,
    [".."]=true, ["=="]=true, ["~="]=true, ["<"]=true, [">"]=true,
    ["<="]=true, [">="]=true, ["#"]=true, ["..."]=true,
}

local function isname(c) return c:match("[A-Za-z_]") ~= nil end
local function isdigit(c) return c:match("[0-9]") ~= nil end

local function tokenize(src)
    local toks = {}
    local i, n = 1, #src
    local pre = ""
    local function push(kind, a, b)
        toks[#toks + 1] = { kind = kind, text = src:sub(a, b), pre = pre }
        pre = ""
    end
    while i <= n do
        local c = src:sub(i, i)
        if c == "\n" then
            push("nl", i, i); i = i + 1
        elseif c == " " or c == "\t" or c == "\r" then
            pre = pre .. c; i = i + 1
        elseif c == "-" and src:sub(i + 1, i + 1) == "-" then
            local j = i + 2
            local level = -1
            if src:sub(j, j) == "[" then
                local k = j + 1
                local eq = 0
                while src:sub(k, k) == "=" do eq = eq + 1; k = k + 1 end
                if src:sub(k, k) == "[" then level = eq; j = k + 1 end
            end
            if level >= 0 then
                local close = "]" .. ("="):rep(level) .. "]"
                local e = src:find(close, j, true)
                e = (e and e + #close - 1) or n
                push("comment", i, e); i = e + 1
            else
                local e = src:find("\n", i, true) or (n + 1)
                push("comment", i, e - 1); i = e
            end
        elseif c == "[" then
            local k = i + 1
            local eq = 0
            while src:sub(k, k) == "=" do eq = eq + 1; k = k + 1 end
            if src:sub(k, k) == "[" then
                local close = "]" .. ("="):rep(eq) .. "]"
                local e = src:find(close, k + 1, true)
                e = (e and e + #close - 1) or n
                push("string", i, e); i = e + 1
            else
                push("op", i, i); i = i + 1
            end
        elseif c == "'" or c == '"' then
            local j = i + 1
            while j <= n do
                local d = src:sub(j, j)
                if d == "\\" then j = j + 2
                elseif d == c or d == "\n" then break
                else j = j + 1 end
            end
            push("string", i, math.min(j, n)); i = math.min(j, n) + 1
        elseif isdigit(c) or (c == "." and isdigit(src:sub(i + 1, i + 1))) then
            local j = i
            if src:sub(j, j + 1) == "0x" or src:sub(j, j + 1) == "0X" then
                j = j + 2
                while j <= n and (isdigit(src:sub(j, j)) or src:sub(j, j) == "_" or
                    src:sub(j, j):match("[A-Fa-f]")) do j = j + 1 end
            else
                while j <= n and (isdigit(src:sub(j, j)) or src:sub(j, j) == "_") do j = j + 1 end
                if src:sub(j, j) == "." and src:sub(j + 1, j + 1) ~= "." then
                    j = j + 1
                    while j <= n and (isdigit(src:sub(j, j)) or src:sub(j, j) == "_") do j = j + 1 end
                end
                local e1 = src:sub(j, j)
                if e1 == "e" or e1 == "E" then
                    j = j + 1
                    if src:sub(j, j) == "+" or src:sub(j, j) == "-" then j = j + 1 end
                    while j <= n and (isdigit(src:sub(j, j)) or src:sub(j, j) == "_") do j = j + 1 end
                end
            end
            push("number", i, j - 1); i = j
        elseif isname(c) then
            local j = i + 1
            while j <= n and (isname(src:sub(j, j)) or isdigit(src:sub(j, j))) do j = j + 1 end
            local w = src:sub(i, j - 1)
            push(KEYWORDS[w] and "kw" or "name", i, j - 1); i = j
        else
            local three = src:sub(i, i + 2)
            if three == "..." then
                push("op", i, i + 2); i = i + 3
            else
                local two = src:sub(i, i + 1)
                if two == ".." or two == "==" or two == "~=" or two == "<="
                    or two == ">=" or two == "::" then
                    push("op", i, i + 1); i = i + 2
                else
                    push("op", i, i); i = i + 1
                end
            end
        end
    end
    return toks
end

M.tokenize = tokenize

function M.transform(src)
    local toks = tokenize(src)
    local out = {}
    -- unified stack: blocks AND expression parens live here.
    -- kinds: paren (call/table/index), func, if, block, loop, whilehdr, forhdr
    local S = {}
    local ifStack = {}      -- {state="cond"|"then"|"else", base=#S at push}
    local loopId = 0
    local prevSig = nil     -- last significant token (comment/nl excluded)

    local function emit(s) out[#out + 1] = s end
    local function emitTok(t) emit(t.pre); emit(t.text) end

    -- close if-expr frames whose else-branch terminates before `closer`
    local function closeFrames(closer)
        while true do
            local f = ifStack[#ifStack]
            if not f or f.state ~= "else" then break end
            if closer == "nl" or closer == ";" or closer == "," or closer == ")"
                or closer == "}" or closer == "]" or closer == "end"
                or closer == "until" or closer == "else" or closer == "elseif" then
                if #S == f.base then
                    emit(" end end)()")
                    ifStack[#ifStack] = nil
                else
                    break
                end
            else
                break
            end
        end
    end

    local idx = 1
    while idx <= #toks do
        local t = toks[idx]
        local k, x = t.kind, t.text

        if k == "comment" then
            emitTok(t)
            idx = idx + 1
        elseif k == "nl" then
            closeFrames("nl")
            emitTok(t)
            prevSig = t
            idx = idx + 1
        elseif k == "string" or k == "number" then
            emitTok(t); prevSig = t; idx = idx + 1
        elseif k == "name" then
            if x == "continue" and (prevSig == nil or prevSig.kind == "nl"
                or (prevSig.kind == "kw" and (prevSig.text == "end" or prevSig.text == "then"
                    or prevSig.text == "else" or prevSig.text == "do" or prevSig.text == "repeat"
                    or prevSig.text == "until"))
                or (prevSig.kind == "op" and prevSig.text == ";")) then
                local loopIdx = nil
                for bi = #S, 1, -1 do
                    if S[bi].kind == "loop" then loopIdx = bi; break end
                end
                if loopIdx then
                    S[loopIdx].hasContinue = true
                    emit(t.pre); emit("goto L" .. S[loopIdx].id)
                    prevSig = { kind = "kw", text = "goto" }
                else
                    emitTok(t); prevSig = t
                end
            else
                emitTok(t); prevSig = t
            end
            idx = idx + 1
        elseif k == "kw" then
            if x == "if" then
                local isExpr = false
                local f = ifStack[#ifStack]
                if f and (f.state == "then" or f.state == "else") then
                    isExpr = true
                elseif prevSig == nil then
                    isExpr = false
                elseif prevSig.kind == "nl" then
                    local top = S[#S]
                    isExpr = top ~= nil and top.kind == "paren"
                elseif OPS_EXPR_CONT[prevSig.text] then
                    isExpr = true
                end
                if isExpr then
                    emit(t.pre); emit("(function() if")
                    ifStack[#ifStack + 1] = { state = "cond", base = #S }
                else
                    emitTok(t)
                    S[#S + 1] = { kind = "if" }
                end
                prevSig = t
            elseif x == "then" then
                local f = ifStack[#ifStack]
                if f and f.state == "cond" then
                    emit(t.pre); emit("then return")
                    f.state = "then"
                else
                    emitTok(t)
                end
                prevSig = t
            elseif x == "else" then
                closeFrames("else")
                local f = ifStack[#ifStack]
                if f and f.state == "then" then
                    emit(t.pre); emit("else return")
                    f.state = "else"
                else
                    emitTok(t)
                end
                prevSig = t
            elseif x == "elseif" then
                closeFrames("elseif")
                emitTok(t); prevSig = t
            elseif x == "while" then
                emitTok(t); prevSig = t
                S[#S + 1] = { kind = "whilehdr" }
            elseif x == "for" then
                emitTok(t); prevSig = t
                S[#S + 1] = { kind = "forhdr" }
            elseif x == "do" then
                local top = S[#S]
                if top and (top.kind == "whilehdr" or top.kind == "forhdr") then
                    top.kind = "loop"
                    loopId = loopId + 1
                    top.id = loopId
                    top.hasContinue = false
                    emitTok(t)
                else
                    emitTok(t)
                    S[#S + 1] = { kind = "block" }
                end
                prevSig = t
            elseif x == "repeat" then
                emitTok(t); prevSig = t
                loopId = loopId + 1
                S[#S + 1] = { kind = "loop", id = loopId, hasContinue = false }
            elseif x == "function" then
                emitTok(t); prevSig = t
                S[#S + 1] = { kind = "func" }
            elseif x == "return" then
                emitTok(t); prevSig = t
                if #S > 0 then S[#S].returnOutPos = #out end
            elseif x == "end" then
                closeFrames("end")
                local popped = table.remove(S)
                emit(t.pre)
                if popped and popped.kind == "loop" and popped.hasContinue then
                    if popped.returnOutPos and popped.returnOutPos <= #out then
                        table.insert(out, popped.returnOutPos, "do ")
                        emit(" end ")
                    end
                    emit("::L" .. popped.id .. ":: ")
                end
                emit("end")
                prevSig = t
            elseif x == "until" then
                closeFrames("until")
                local popped = table.remove(S)
                emit(t.pre)
                if popped and popped.kind == "loop" and popped.hasContinue then
                    if popped.returnOutPos and popped.returnOutPos <= #out then
                        table.insert(out, popped.returnOutPos, "do ")
                        emit(" end ")
                    end
                    emit("::L" .. popped.id .. ":: ")
                end
                emit("until")
                prevSig = t
            else
                emitTok(t); prevSig = t
            end
            idx = idx + 1
        else -- op
            if x == "(" or x == "{" or x == "[" then
                emitTok(t)
                S[#S + 1] = { kind = "paren" }
                prevSig = t
            elseif x == ")" or x == "}" or x == "]" then
                closeFrames(x)
                emitTok(t)
                table.remove(S)
                prevSig = t
            elseif x == "," or x == ";" then
                closeFrames(x)
                emitTok(t)
                prevSig = t
            else
                emitTok(t); prevSig = t
            end
            idx = idx + 1
        end
    end
    while #ifStack > 0 do
        emit(" end end)()")
        ifStack[#ifStack] = nil
    end
    return table.concat(out)
end

-- self-test when run directly
if arg and arg[0] and arg[0]:match("potato%-harness%-luau") then
    local pass, fail = 0, 0
    local function check(name, cond)
        if cond then pass = pass + 1 else fail = fail + 1; print("FAIL: " .. name) end
    end

    local s1 = "local var1 = if str14 then var2.new() else nil\nvar4 = if v8.VREnabled then str7 else str5\n"
    local t1 = M.transform(s1)
    local f1 = load(t1, "=t1", "t", { str14 = true, var2 = { new = function() return "N" end },
        v8 = { VREnabled = true }, str7 = "S", str5 = "s" })
    check("t1 loads", f1 ~= nil)
    if f1 then local ok = pcall(f1); check("t1 runs", ok) end

    local s2 = 'var4.Text = str1:format(var5, if var3 and var3 ~= "" then ("@%*"):format(var3) else "")\n'
    local t2 = M.transform(s2)
    check("t2 loads", load(t2, "=t2", "t", {
        str1 = { format = function() return "" end }, var5 = 1, var3 = "x" }) ~= nil)

    local s3 = "local n = 0\nfor i = 1, 10 do\n\tif i % 2 == 0 then\n\t\tcontinue\n\tend\n\tn = n + i\nend\nreturn n\n"
    local t3 = M.transform(s3)
    local f3 = load(t3, "=t3", "t", {})
    check("t3 loads", f3 ~= nil)
    if f3 then local ok, r = pcall(f3); check("t3 runs: sum of odds = 25", ok and r == 25) end

    local s4 = "local c = 0\nlocal i = 0\nwhile true do\n\ti = i + 1\n\tif i > 5 then break end\n\tfor j = 1, 3 do\n\t\tif j == 2 then continue end\n\t\tc = c + 1\n\tend\nend\nreturn c\n"
    local t4 = M.transform(s4)
    local f4 = load(t4, "=t4", "t", {})
    check("t4 loads", f4 ~= nil)
    if f4 then local ok, r = pcall(f4); check("t4 runs: 5x2 = 10", ok and r == 10) end

    local s5 = "local x = if a then if b then 1 else 2 else 3\nreturn x\n"
    local t5 = M.transform(s5)
    local f5 = load(t5, "=t5", "t", { a = true, b = false })
    check("t5 loads", f5 ~= nil)
    if f5 then local ok, r = pcall(f5); check("t5 nested = 2", ok and r == 2) end

    local s6 = "local t = {}\ntable.insert(t, if flag then 10 else 20)\nreturn t[1]\n"
    local t6 = M.transform(s6)
    local f6 = load(t6, "=t6", "t", { flag = true, table = table })
    check("t6 loads", f6 ~= nil)
    if f6 then local ok, r = pcall(f6); check("t6 arg-close = 10", ok and r == 10) end

    local s7 = "local r = 0\nif cond then\n\tr = 1\nelse\n\tr = 2\nend\nreturn r\n"
    local t7 = M.transform(s7)
    local f7 = load(t7, "=t7", "t", { cond = true })
    check("t7 loads", f7 ~= nil)
    if f7 then local ok, r = pcall(f7); check("t7 statement-if = 1", ok and r == 1) end

    local s8 = 'local s = [[multi\nline]] .. [==[x]==] -- comment\nreturn #s\n'
    local t8 = M.transform(s8)
    local f8 = load(t8, "=t8", "t", {})
    check("t8 loads", f8 ~= nil)
    if f8 then local ok, r = pcall(f8); check("t8 long-string len = 11", ok and r == 11) end

    -- statement-if + continue inside a function inside a table constructor
    local s9 = 'local n = 0\nlocal t = {\n\tfn = function()\n\t\tfor i = 1, 3 do\n\t\t\tif i == 2 then\n\t\t\t\tcontinue\n\t\t\tend\n\t\t\tn = n + i\n\t\tend\n\tend,\n}\nt.fn()\nreturn n\n'
    local t9 = M.transform(s9)
    local f9 = load(t9, "=t9", "t", {})
    check("t9 loads (stmt-if in table-function)", f9 ~= nil)
    if f9 then local ok, r = pcall(f9); check("t9 runs: 1+3=4", ok and r == 4) end

    -- multiline call with if-expr arg
    local s10 = 'local function f(a, b)\n\treturn a + b\nend\nreturn f(\n\tif true then 1 else 2,\n\t10\n)\n'
    local t10 = M.transform(s10)
    local f10 = load(t10, "=t10", "t", {})
    check("t10 loads (multiline call if-expr)", f10 ~= nil)
    if f10 then local ok, r = pcall(f10); check("t10 = 11", ok and r == 11) end

    -- trailing return inside a continue-loop (label must not follow a retstat)
    local s11 = 'local n = 0\nfor i = 1, 4 do\n\tif i == 1 then\n\t\tcontinue\n\tend\n\tif i == 3 then\n\t\treturn n\n\tend\n\tn = n + i\nend\nreturn n\n'
    local t11 = M.transform(s11)
    local f11 = load(t11, "=t11", "t", {})
    check("t11 loads (trailing return + continue)", f11 ~= nil)
    if f11 then local ok, r = pcall(f11); check("t11 runs: n=2 (i=1 skip, i=2 add, i=3 return)", ok and r == 2) end

    local s12 = 'local i = 0\nrepeat\n\ti = i + 1\n\tif i == 2 then\n\t\tcontinue\n\tend\n\tif i == 4 then\n\t\treturn i\n\tend\nuntil i >= 4\nreturn -1\n'
    local t12 = M.transform(s12)
    local f12 = load(t12, "=t12", "t", {})
    check("t12 loads (repeat trailing return)", f12 ~= nil)
    if f12 then local ok, r = pcall(f12); check("t12 runs: 4", ok and r == 4) end

    print(("LUAU-XFORM: %d/%d PASS"):format(pass, pass + fail))
    if fail > 0 then os.exit(1) end
end

return M
