#!/bin/sh
# bootstrap.sh [NAME] [TOKEN] — one-shot GLM session setup (glm1+glm2 unified).
# Idempotent; safe to re-run any time.
#   NAME   optional session name: also creates status/logs skeleton + shows
#          unread msgs and task owners. Needed only for brand-new instances.
#   TOKEN  optional push token; falls back to $TOKEN env, then the live token
#          in the local sandbox worklog (display-redacted only — grep it).
#          NEVER echoed, NEVER written inside any repo; lands only in
#          .git/config remote URLs of the two clones.
# What it does:
#   1. Clone-or-pull both repos:  ~/SavedFolder  +  ~/Public  (persistent —
#      /tmp is wiped between sessions; GitHub is the only durable state).
#   2. Lua 5.4 toolchain: portable tarball from THIS repo first (works even
#      after a full sandbox reset), then upload/luadist debs as fallback.
#      Installs to ~/.lua54/bin (+ ~/bin symlink) — no root, no compiling.
#   3. Wire the token into both remotes (silent, verified via ls-remote).
#   4. Print project state (task owners, statuses, unread msgs) + next steps.
# After it:  . ~/.lua54-env.sh     (PATH for this shell)

set -u
NAME="${1:-}"
TOK="${2:-${TOKEN:-}}"
SANDBOX="${HOME:-/home/z}"
SF="${SF_DIR:-$SANDBOX/SavedFolder}"
PUB="${PUBLIC_DIR:-$SANDBOX/Public}"
LUA_DIR="$SANDBOX/.lua54"
ENV_FILE="$SANDBOX/.lua54-env.sh"
WORKLOG="$SANDBOX/my-project/worklog.md"
TOOLS="$SF/shared/tools"

say() { printf '\n== %s\n' "$*"; }

# ---------- 1) repos ----------
say "repos"
for pair in "SF:$SF" "PUB:$PUB"; do
    var="${pair%%:*}"; dir="${pair#*:}"
    if [ -d "$dir/.git" ]; then
        git -C "$dir" pull --rebase --autostash --quiet >/dev/null 2>&1
        echo "$(basename "$dir"): $(git -C "$dir" log --oneline -1)"
    else
        repo="$( [ "$var" = SF ] && echo SavedFolder || echo Public )"
        timeout 240 git clone -q "https://github.com/caotuanthanh147/$repo.git" "$dir" || exit 1
        echo "cloned $repo -> $dir"
    fi
done
# make sure we run the tools from the real clone
[ -f "$TOOLS/lua54.tar.gz" ] || { echo "[ERR] $TOOLS/lua54.tar.gz missing"; exit 1; }

# ---------- 2) Lua 5.4 toolchain ----------
say "lua 5.4 toolchain"
if ! ("$LUA_DIR/bin/lua5.4" -v >/dev/null 2>&1) ; then
    rm -rf "$LUA_DIR"; mkdir -p "$LUA_DIR"
    tar -xzf "$TOOLS/lua54.tar.gz" -C "$LUA_DIR" \
      && echo "installed portable lua5.4+luac5.4 from repo tarball" \
      || {
        # fallback: extract from the sandbox debs if present (older path)
        DEB="$SANDBOX/my-project/upload/luadist"
        [ -d "$DEB" ] || DEB="$SANDBOX/my-project"
        mkdir -p "$SANDBOX/.luaroot"
        for f in "$DEB"/lua5.4_*.deb "$DEB"/liblua5.4-dev_*.deb; do
            [ -e "$f" ] && dpkg -x "$f" "$SANDBOX/.luaroot" 2>/dev/null
        done
        for b in lua5.4 luac5.4; do
            src="$(command -v find >/dev/null && find "$SANDBOX/.luaroot" -name "$b" -type f 2>/dev/null | head -1)"
            [ -n "$src" ] && cp "$src" "$LUA_DIR/bin/$b" 2>/dev/null
        done
      }
fi
mkdir -p "$SANDBOX/bin"
for b in lua5.4 luac5.4; do
    [ -x "$LUA_DIR/bin/$b" ] && ln -sf "$LUA_DIR/bin/$b" "$SANDBOX/bin/$b"
done
printf 'export PATH="%s/bin:$PATH"\n' "$LUA_DIR" > "$ENV_FILE"
. "$ENV_FILE" 2>/dev/null
lua5.4 -v 2>&1 | head -1 || { echo "[ERR] lua5.4 MISSING"; exit 1; }
luac5.4 -v 2>&1 | head -1
echo "(persist PATH per shell with: . $ENV_FILE)"

# ---------- 3) push token ----------
say "push token"
if [ -z "$TOK" ] && [ -f "$WORKLOG" ]; then
    TOK=$(grep -oE 'ghp_[A-Za-z0-9]{20,}' "$WORKLOG" | head -1)
fi
if [ -n "$TOK" ]; then
    for d in "$SF" "$PUB"; do
        u=$(git -C "$d" remote get-url origin 2>/dev/null)
        case "$u" in *caotuanthanh147*) ;; *) continue ;; esac
        git -C "$d" remote set-url origin "https://$TOK@github.com/caotuanthanh147/$(basename "$d").git"
    done
    git -C "$SF" ls-remote origin HEAD >/dev/null 2>&1 \
      && echo "token wired into both remotes (verified)" \
      || echo "[warn] token present but ls-remote failed — ask the user for a fresh one"
else
    echo "[warn] no token (arg 2, \$TOKEN, or worklog) — clones fine, pushes will fail"
fi

# ---------- 4) state + next steps ----------
if [ -n "$NAME" ]; then
    say "session files for $NAME"
    [ -f "$SF/status/$NAME.md" ] || { mkdir -p "$SF/status" "$SF/logs" "$SF/msgs/$NAME"; : > "$SF/status/$NAME.md"; : > "$SF/logs/$NAME.md"; echo "created empty status/$NAME.md + logs/$NAME.md (fill + commit)"; }
    say "unread messages for $NAME"
    ls "$SF/msgs/$NAME/"*.md 2>/dev/null || echo "(none)"
fi
say "task owners"
grep "^| T" "$SF/TASKS.md" 2>/dev/null | cut -c1-130
say "session statuses"
for s in "$SF/status/"*.md; do
    [ -e "$s" ] || continue
    echo "-- $(basename "$s"): $(head -6 "$s" | tr '\n' ' ' | tr -s ' ' | cut -c1-110)"
done
say "next"
echo "1. read $SF/shared/ONBOARDING.md (cold start) — then PROMPT.md, TASKS.md, the guide"
echo "2. answer msgs/, claim tasks in TASKS.md, keep status/ updated"
echo "3. background watchers: nohup sh $TOOLS/poll.sh ${NAME:-glmN} >/tmp/${NAME:-glmN}-poll.out 2>&1 &"
echo "   (game-zip watch)       nohup sh $TOOLS/watch_public.sh ${NAME:-glmN} >/tmp/${NAME:-glmN}-public.out 2>&1 &"
