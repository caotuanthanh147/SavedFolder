-- bench_dispatch.lua — M6 research: dispatch-strategy cost measurement in
-- pure Lua 5.4 (doc §10.2.5 research question: closure-per-opcode vs
-- if-chain vs binary-search tree vs table dispatch; goto is FORBIDDEN by
-- doc.md so computed-goto shapes are not attempted).
--
-- Design: for each ISA size N, the SAME synthetic program (400 instructions,
-- every opcode id in [0,N-2] is a distinct handler doing cheap uniform work
-- drawn from 15 semantics by id%15; id N-1 = HALT) is executed by:
--   1. if/elseif chain       (generated, N-branch, goto-free)
--   2. balanced binary tree  (generated, log2(N) comparison depth)
--   3. closure-per-opcode    (N-entry handler table, nil = HALT)
--   4. string-packed fetch   (generated if-chain, instructions unpacked
--                              from a byte string instead of a table)
-- Identical work per opcode id across strategies (same semantics, same
-- operands), so differences measure the DISPATCH+FETCH mechanism only.
--
-- Usage: lua5.4 bench_dispatch.lua [rounds] [runs]

local N_ROUNDS = tonumber(arg and arg[1]) or 7
local N_RUNS = tonumber(arg and arg[2]) or 40
local LENGTH = 400

local function lcg_seed(s)
        local state = s
        return function()
                state = (1103515245 * state + 12345) % 2147483648
                return state
        end
end

-- 15 straight-line-ish semantics (ops 7/8/14 read the operand for control
-- flow). Bodies are used BOTH for code generation (strings) and as the
-- closure bodies (compiled from the same strings via load), so the work is
-- byte-identical across strategies by construction.
local SEM_SRC = {
        [0] = "regs[1]=regs[4]+regs[5] pc=pc+1",
        [1] = "regs[1]=regs[4]-regs[5] pc=pc+1",
        [2] = "regs[1]=regs[4]*regs[5] pc=pc+1",
        [3] = "regs[1]=regs[b+1] pc=pc+1",
        [4] = "regs[1]=b pc=pc+1",
        [5] = "regs[1]=regs[2][regs[3]] pc=pc+1",
        [6] = "regs[2][regs[3]]=regs[4] pc=pc+1",
        [7] = "local d=(b%3)+1 if pc+d>#prog then d=1 end pc=pc+d",
        [8] = "if regs[4]==regs[5] then pc=pc+1 else pc=pc+2 end",
        [9] = "regs[1]=not regs[4] pc=pc+1",
        [10] = "regs[1]=#regs[2] pc=pc+1",
        [11] = "regs[1]=regs[8]..regs[9] pc=pc+1",
        [12] = "regs[1]=regs[6](regs[4]) pc=pc+1",
        [13] = "regs[1]=regs[2].x pc=pc+1",
        [14] = "if not regs[4] then pc=pc+2 else pc=pc+1 end",
}
-- string-fetch variants: same semantics, pc advances in 3-byte units,
-- jumps bounded by the string length instead of #prog.
local SEM_SRC_STR = {
        [0] = "regs[1]=regs[4]+regs[5] pc=pc+3",
        [1] = "regs[1]=regs[4]-regs[5] pc=pc+3",
        [2] = "regs[1]=regs[4]*regs[5] pc=pc+3",
        [3] = "regs[1]=regs[(o2%4)+1] pc=pc+3",
        [4] = "regs[1]=o2 pc=pc+3",
        [5] = "regs[1]=regs[2][regs[3]] pc=pc+3",
        [6] = "regs[2][regs[3]]=regs[4] pc=pc+3",
        [7] = "local di=(o2%3)+1 if pc+di*3>#prog-2 then di=1 end pc=pc+di*3",
        [8] = "if regs[4]==regs[5] then pc=pc+3 else pc=pc+6 end",
        [9] = "regs[1]=not regs[4] pc=pc+3",
        [10] = "regs[1]=#regs[2] pc=pc+3",
        [11] = "regs[1]=regs[8]..regs[9] pc=pc+3",
        [12] = "regs[1]=regs[6](regs[4]) pc=pc+3",
        [13] = "regs[1]=regs[2].x pc=pc+3",
        [14] = "if not regs[4] then pc=pc+6 else pc=pc+3 end",
}

local function build_program(n_opcodes, length, seed)
        local rnd = lcg_seed(seed)
        local prog = {}
        for i = 1, length do
                local op = rnd() % (n_opcodes - 1) -- never HALT mid-program
                -- avoid control-flow semantics near the end so jumps stay in bounds
                if i > length - 4 then
                        while op % 15 >= 7 do
                                op = (op + 1) % (n_opcodes - 1)
                        end
                end
                prog[i] = op * 65536 + (rnd() % 4) * 256 + (rnd() % 4)
        end
        prog[length + 1] = (n_opcodes - 1) * 65536 -- HALT = highest id
        return prog
end

-- ============ generated if/elseif chain ============
local function make_ifchain(n, sem_src, fetch)
        local parts = {}
        for i = 0, n - 2 do
                local kw = i == 0 and "if" or "elseif"
                parts[#parts + 1] = ("%s op==%d then do %s end "):format(kw, i, sem_src[i % 15])
        end
        parts[#parts + 1] = "else do total=total+pc break end end "
        local fetch_src = fetch or "local ins=prog[pc] local op=math.floor(ins/65536) local b=ins%256 "
        local src = "return function(prog,n_iter,regs) local total=0 "
                .. "for _=1,n_iter do local pc=1\n"
                .. "while true do " .. fetch_src .. "\n"
                .. table.concat(parts)
                .. "\nend end return total end"
        return assert(load(src, "=ifchain"))(), src
end

-- ============ generated balanced binary comparison tree ============
local function make_bintree(n)
        local parts = {}
        local halt_id = n - 1
        local function emit(lo, hi)
                if lo == hi then
                        if lo == halt_id then
                                parts[#parts + 1] = "do total=total+pc break end "
                        else
                                parts[#parts + 1] = ("do %s end "):format(SEM_SRC[lo % 15])
                        end
                        return
                end
                local mid = math.floor((lo + hi) / 2)
                parts[#parts + 1] = ("if op<=%d then "):format(mid)
                emit(lo, mid)
                parts[#parts + 1] = "else "
                emit(mid + 1, hi)
                parts[#parts + 1] = "end "
        end
        parts[#parts + 1] = "local total=0 "
        parts[#parts + 1] = "for _=1,n_iter do local pc=1\nwhile true do "
        parts[#parts + 1] = "local ins=prog[pc] local op=math.floor(ins/65536) local b=ins%256\n"
        emit(0, n - 1)
        parts[#parts + 1] = "\nend end return total"
        local src = "return function(prog,n_iter,regs) " .. table.concat(parts) .. " end"
        return assert(load(src, "=bintree"))(), src
end

-- ============ closure-per-opcode table dispatch ============
local function make_closure_table(n)
        local handlers = {}
        for i = 0, n - 2 do
                local f = assert(load(("return function(regs,b,prog,pc) %s return pc end"):format(SEM_SRC[i % 15]), "=h"))
                handlers[i + 1] = f()
        end
        return function(prog, n_iter, regs)
                local total = 0
                local H = handlers
                for _ = 1, n_iter do
                        local pc = 1
                        while true do
                                local ins = prog[pc]
                                local h = H[math.floor(ins / 65536) + 1]
                                if h == nil then
                                        total = total + pc
                                        break
                                end
                                pc = h(regs, ins % 256, prog, pc)
                        end
                end
                return total
        end
end

-- ============ harness ============
local function fresh_regs()
        local t = { 1, 2, 3, 4, 5, 6, 7, "a", "b" }
        t[2] = t
        t[2].x = 7
        t[6] = function(x) return x end
        return t
end

local function bench(fn, prog, n_iter)
        local best = math.huge
        for _ = 1, N_ROUNDS do
                local regs = fresh_regs()
                local t0 = os.clock()
                fn(prog, n_iter, regs)
                local dt = os.clock() - t0
                if dt < best then best = dt end
        end
        return best
end

print(("lua: %s | rounds=%d runs=%d | program: %d instr + HALT, same stream everywhere")
        :format(_VERSION, N_ROUNDS, N_RUNS, LENGTH))

local results = {}
for _, n_opcodes in ipairs({ 16, 64, 256 }) do
        local prog = build_program(n_opcodes, LENGTH, 42 + n_opcodes)

        -- string-packed twin of the same program (3 bytes/instr: op, operand, pad)
        local sbuf = {}
        for i = 1, LENGTH do
                local ins = prog[i]
                sbuf[#sbuf + 1] = string.char(math.floor(ins / 65536), ins % 256, 0)
        end
        sbuf[#sbuf + 1] = string.char(n_opcodes - 1, 0, 0) -- HALT
        sbuf = table.concat(sbuf)

        local ifchain = make_ifchain(n_opcodes, SEM_SRC)
        local bintree = make_bintree(n_opcodes)
        local closure_tbl = make_closure_table(n_opcodes)
        local strfetch = make_ifchain(n_opcodes, SEM_SRC_STR,
                "local byte=string.byte local o1=byte(prog,pc) local o2=byte(prog,pc+1) local op=o1 ")

        local n_instr = LENGTH * N_RUNS
        local t_if = bench(ifchain, prog, N_RUNS)
        local t_bt = bench(bintree, prog, N_RUNS)
        local t_cl = bench(closure_tbl, prog, N_RUNS)
        local t_st = bench(strfetch, sbuf, N_RUNS)

        results[#results + 1] = {
                n = n_opcodes,
                ifchain = t_if / n_instr * 1e9,
                bintree = t_bt / n_instr * 1e9,
                closure = t_cl / n_instr * 1e9,
                strfetch = t_st / n_instr * 1e9,
        }
end

print(("%-6s %-12s %-12s %-12s %-12s"):format("ISA", "if/elseif", "bin-tree", "closure-tbl", "str-fetch"))
for _, r in ipairs(results) do
        print(("%-6d %-12.1f %-12.1f %-12.1f %-12.1f"):format(r.n, r.ifchain, r.bintree, r.closure, r.strfetch))
end
print("(ns per dispatched program-instruction, best-of-rounds; str-fetch = generated if-chain + string:byte unpack)")
