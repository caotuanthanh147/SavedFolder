#!/bin/sh
# bootstrap.sh <name> [TOKEN] — new-session environment setup: clone/pull SavedFolder + the user's Public repo (token via 2nd arg or $TOKEN env; used only for git, lands only in local .git/config, never in repo files), ensure lua5.4/luac5.4 (extract from upload/luadist debs when missing), then print the current project state (TASKS.md owners, status files, unread msgs/<name>/).
set -u
NAME="${1:?usage: bootstrap.sh <name> [token]}"
TOKEN="${2:-${TOKEN:-}}"
SANDBOX="${SANDBOX:-/home/z}"
SF="$SANDBOX/SavedFolder"
PUB="${PUBLIC:-/tmp/Public}"
MP="$SANDBOX/my-project"

say() { printf '\n== %s\n' "$*"; }

say "repos"
if [ -d "$SF/.git" ]; then
    git -C "$SF" pull --rebase --autostash --quiet 2>&1 | tail -1
else
    [ -n "$TOKEN" ] || { echo "SavedFolder not cloned and no token given (arg 2 or \$TOKEN)"; exit 1; }
    timeout 240 git clone -q "https://${TOKEN}@github.com/caotuanthanh147/SavedFolder.git" "$SF" || exit 1
fi
if [ -d "$PUB/.git" ]; then
    git -C "$PUB" pull --rebase --autostash --quiet 2>&1 | tail -1
else
    timeout 240 git clone -q "https://${TOKEN}@github.com/caotuanthanh147/Public.git" "$PUB" 2>/dev/null \
        || timeout 240 git clone -q "https://github.com/caotuanthanh147/Public.git" "$PUB" || exit 1
fi
echo "SavedFolder: $(git -C "$SF" log --oneline -1)"
echo "Public:      $(git -C "$PUB" log --oneline -1)"

say "lua 5.4 toolchain"
export PATH="$SANDBOX/bin:$PATH"
if ! command -v lua5.4 >/dev/null 2>&1 || ! command -v luac5.4 >/dev/null 2>&1; then
    mkdir -p "$SANDBOX/bin"
    DEB="$MP/upload/luadist"
    if [ -d "$DEB" ]; then
        for f in "$DEB"/lua5.4_*.deb "$DEB"/liblua5.4-dev_*.deb; do
            [ -e "$f" ] || continue
            dpkg -x "$f" "$SANDBOX/.luaroot" 2>/dev/null || true
        done
        for b in lua5.4 luac5.4; do
            src="$(find "$SANDBOX/.luaroot" -name "$b" -type f 2>/dev/null | head -1)"
            [ -n "$src" ] && cp "$src" "$SANDBOX/bin/$b"
        done
    fi
fi
lua5.4 -v 2>&1 | head -1 || echo "lua5.4 MISSING (provide upload/luadist debs)"
luac5.4 -v 2>&1 | head -1 || echo "luac5.4 MISSING"

say "your session files"
[ -f "$SF/status/$NAME.md" ] || { mkdir -p "$SF/status" "$SF/logs" "$SF/msgs/$NAME"; touch "$SF/status/$NAME.md" "$SF/logs/$NAME.md"; echo "created empty status/$NAME.md logs/$NAME.md (fill them + commit)"; }

say "unread messages for $NAME"
ls "$SF/msgs/$NAME/"*.md 2>/dev/null || echo "(none)"

say "task owners (TASKS.md)"
grep "^| T" "$SF/TASKS.md" 2>/dev/null | cut -c1-140 || echo "no TASKS.md"

say "session statuses"
for s in "$SF/status/"*.md; do echo "-- $(basename "$s"): $(head -3 "$s" | tail -2 | tr '\n' ' ' | cut -c1-100)"; done

say "next"
echo "1. read $SF/shared/GUIDE.md (quickstart)"
echo "2. answer msgs/$NAME/, claim a task in TASKS.md, update status/$NAME.md"
echo "3. optional background watcher: nohup sh $SF/shared/tools/poll.sh $NAME > /tmp/$NAME-poll.out 2>&1 &"
