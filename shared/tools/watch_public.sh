#!/bin/sh
# watch_public.sh [NAME] — automate T3: watch github.com/caotuanthanh147/Public
# for new/removed game zips + new commits. Every 30s:
#   git pull --rebase (skipped while a commit is in flight), then diff the
#   ROOT-LEVEL *.zip list against the last state.
# Reports to stdout AND /tmp/<name>.public.log (one event per line, doubles as history).
# Usage:  sh watch_public.sh [--once] glm2 &   (from anywhere; default clone
#         /home/z/Public). --once: run ONE cycle then exit (testing/spot-check).
# Event format:
#   <utc-time> ZIP+     <name>  (new game zip — run the standard pipeline!)
#   <utc-time> ZIP-     <name>  (game closed by user)
#   <utc-time> COMMIT   <sha7> <subject>   (any other change)

ONCE=0
[ "${1:-}" = "--once" ] && { ONCE=1; shift; }
NAME="${1:-watcher}"
PUBLIC_DIR="${2:-/home/z/Public}"
STATE="/tmp/${NAME}.public.state"
LOG="/tmp/${NAME}.public.log"

cd "$PUBLIC_DIR" || { echo "no clone at $PUBLIC_DIR (run bootstrap.sh first)"; exit 1; }

# init state quietly on first run
[ -f "$STATE" ] || git ls-files -- '*.zip' > "$STATE"
LAST_HEAD=$(git rev-parse --short HEAD 2>/dev/null)

report() { echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) $1 $2" | tee -a "$LOG"; }

echo "watch_public: watching $PUBLIC_DIR for zip changes (as $NAME)"

while true; do
    if [ ! -e .git/index.lock ]; then
        git pull --rebase --quiet >/dev/null 2>&1
    fi
    git ls-files -- '*.zip' > "$STATE.new"
    # root-level zips only (delivery convention)
    awk -F/ 'NF==1' "$STATE.new" > "$STATE.roots"
    awk -F/ 'NF==1' "$STATE"     > "$STATE.roots.old"
    while IFS= read -r z; do
        grep -qxF "$z" "$STATE.roots.old" || report "ZIP+" "$z"
    done < "$STATE.roots"
    while IFS= read -r z; do
        grep -qxF "$z" "$STATE.roots" || report "ZIP-" "$z"
    done < "$STATE.roots.old"
    mv "$STATE.new" "$STATE"
    HEAD_NOW=$(git rev-parse --short HEAD 2>/dev/null)
    if [ -n "$LAST_HEAD" ] && [ "$HEAD_NOW" != "$LAST_HEAD" ]; then
        git log --oneline "$LAST_HEAD..$HEAD_NOW" 2>/dev/null | while read -r sha rest; do
            report "COMMIT" "$sha $rest"
        done
    fi
    LAST_HEAD="$HEAD_NOW"
    [ "$ONCE" = 1 ] && { echo "watch_public: single cycle done (--once)"; exit 0; }
    sleep 30
done
