#!/bin/sh
# poll.sh <name> [repo-dir] — background loop for AI sessions: every 30s, git pull --rebase (skipped while a commit is in flight) and report new msgs/<name>/*.md files to /tmp/<name>.msgs.log (one basename+timestamp per line; the log doubles as the seen-list).
NAME="$1"
DIR="${2:-/home/z/SavedFolder}"
LOG="/tmp/${NAME}.msgs.log"
cd "$DIR" || exit 1
: > "$LOG"
while true; do
    if [ ! -e .git/index.lock ]; then
        git pull --rebase --quiet >/dev/null 2>&1
    fi
    for f in msgs/"$NAME"/*.md; do
        [ -e "$f" ] || continue
        base=$(basename "$f")
        if ! grep -qx "$base" "$LOG" 2>/dev/null; then
            echo "$base $(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$LOG"
            echo "NEW MSG for $NAME: $base"
        fi
    done
    sleep 30
done
