#!/bin/sh
# selftest.sh — one-command smoke test for the shared/tools kit (glm2, T7 dogfood).
# Runs each tool's cheap happy-path on tiny fixtures in a temp dir; exit 0 = all green.
# Use after ANY tool edit (e.g. the env-var path refactor) to catch breakage in ~5s
# instead of rediscovering it mid-game. Requires: lua5.4 on PATH (bootstrap.sh) + python3.
# Covers: lua toolchain, harness_lib smoke, validate.sh, lua_lint.py (scoped range),
# deobf_search.py (both arg orders), newgame.sh (space-path extraction), repack.sh
# (MD5 verify dry-run), watch_public.sh --once (local git fixture).
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
# auto-source the bootstrap env if lua isn't on PATH yet (fresh shell UX)
command -v lua5.4 >/dev/null 2>&1 || { [ -f "${HOME:-/home/z}/.lua54-env.sh" ] && . "${HOME:-/home/z}/.lua54-env.sh"; }
WORK=$(mktemp -d /tmp/st-selftest.XXXXXX)
trap 'rm -rf "$WORK"' EXIT
P=0; F=0
ok()  { P=$((P+1)); echo "  PASS  $1"; }
bad() { F=$((F+1)); echo "  FAIL  $1"; }
sec() { echo "== $1"; }

# ---------- 1) lua toolchain ----------
sec "lua 5.4 toolchain"
if lua5.4 -v >/dev/null 2>&1; then ok "lua5.4 on PATH"; else bad "lua5.4 missing (run bootstrap.sh, . ~/.lua54-env.sh)"; fi

# ---------- 2) harness_lib smoke ----------
sec "harness_lib.lua smoke"
if out=$(lua5.4 "$HERE/harness_lib.lua" 2>&1) && echo "$out" | grep -q "0 fail"; then
    ok "$(echo "$out" | tail -1)"
else bad "harness_lib smoke: $(echo "$out" | tail -1)"
fi

# ---------- 3) validate.sh on Template.lua (self-comparison = syntax+style) ----------
sec "validate.sh (Template.lua self-comparison)"
out=$(sh "$HERE/validate.sh" "$HERE/../../work/lua/Template.lua" 2>&1)
echo "$out" | grep -q "syntax OK" && ok "validate.sh runs, syntax OK" || bad "validate.sh: $(echo "$out" | tail -2 | tr '\n' ' ')"

# ---------- 4) lua_lint.py empty-range (0 errors expected outside game section) ----------
sec "lua_lint.py scoped range"
out=$(python3 "$HERE/lua_lint.py" --from 999999 "$HERE/../../work/lua/Template.lua" 2>&1)
echo "$out" | grep -qE "0 error" && ok "lua_lint.py scoped-range clean" || bad "lua_lint.py: $(echo "$out" | tail -1)"

# ---------- 5) deobf_search.py arg-order tolerance ----------
sec "deobf_search.py arg orders"
printf 'local r = game.ReplicatedStorage.Remotes.Buy\nr:FireServer("apple", 3)\n' > "$WORK/dump.lua"
python3 "$HERE/deobf_search.py" "$WORK/dump.lua" remote >/dev/null 2>&1 && ok "FILE-first order" || bad "FILE-first order"
python3 "$HERE/deobf_search.py" remote "$WORK/dump.lua" >/dev/null 2>&1 && ok "CMD-first order" || bad "CMD-first order"

# ---------- 6) newgame.sh on a spacey-path fixture zip ----------
sec "newgame.sh (space + emoji zip)"
python3 - "$WORK/fix.zip" << 'EOF'
import sys, zipfile
with zipfile.ZipFile(sys.argv[1], 'w') as z:
    z.writestr("Game X/Game X[Deob].lua", "local a = 1\n")
    z.writestr("Game X/game_dump.txt", "d\n")
EOF
out=$(sh "$HERE/newgame.sh" "$WORK/fix.zip" "$WORK/extracted" 2>&1)
echo "$out" | grep -q "Game X\[Deob\].lua" && ok "deobf inventoried" || bad "deobf not found: $(echo "$out" | grep deobf)"
echo "$out" | grep -q "dir: $WORK/extracted/Game X$" && ok "space-path dirs intact" || bad "space-path dir split: $(echo "$out" | grep 'dir:' | tr '\n' '|')"

# ---------- 7) repack.sh dry-run (MD5 verification path) ----------
sec "repack.sh dry-run"
printf 'print("selftest payload")\n' > "$WORK/script.lua"
out=$(sh "$HERE/repack.sh" "$WORK/fix.zip" "$WORK/script.lua" "Game X/Injected.lua" 2>&1)
echo "$out" | grep -q "originals byte-identical: OK" && ok "originals byte-identical" || bad "repack verify: $(echo "$out" | tail -2 | tr '\n' ' ')"

# ---------- 8) watch_public.sh --once on a local git fixture ----------
sec "watch_public.sh --once (local git repo)"
mkdir "$WORK/pub" && cd "$WORK/pub" && git init -q . && cp "$WORK/fix.zip" . && \
    git -c user.name=st -c user.email=st@st add . && git -c user.name=st -c user.email=st@st commit -qm st
: > "/tmp/selftest.public.state"
out=$(timeout 15 sh "$HERE/watch_public.sh" --once selftest "$WORK/pub" 2>&1)
echo "$out" | grep -q "single cycle done" && ok "single cycle exits cleanly" || bad "watch --once: $(echo "$out" | tail -2 | tr '\n' ' ')"

echo
echo "selftest: $P pass / $F fail"
[ "$F" = 0 ] || exit 1
