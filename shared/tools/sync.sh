#!/bin/sh
# sync.sh "<commit message>" [repo-dir] — the ONE command for every protocol step.
#
# Why this exists (the two most expensive time-sinks in the logs):
#   1. The manual 4-command dance (status edit -> add -> commit -> pull --rebase
#      -> push) repeated after EVERY step. ~45s each, and it breaks under
#      parallel load: 2026-10-02 the claim round hit pull-on-dirty-tree + a
#      mid-flight push rejection from the other glm (6 commands + recovery).
#   2. Silent push failures: 2026-10-01 BOTH delivery pushes (SCP + snack)
#      reported success in the worklog but never landed on origin — the user
#      waited a day for files that weren't there. Root cause: nobody verified
#      the remote actually moved.
#
# What it does, in order (never force-pushes):
#   1. git add -A + commit "<message>"   (skipped when the tree is clean)
#   2. git pull --rebase --autostash     (absorbs the other glm's parallel
#      pushes; on a CONFLICT it aborts the rebase, restores your commit and
#      exits 1 loudly — resolve by hand, re-run)
#   3. git push                          (up to 3 attempts if the remote moved
#      again between pull and push)
#   4. VERIFY: git ls-remote origin HEAD == local HEAD; exit 1 if the remote
#      did NOT move to your commit (catches silent auth/network failures)
#   5. prints the newest commits so you see what the other glm pushed meanwhile
#
# Usage:
#   sh shared/tools/sync.sh "T9: claim + notes"              # SavedFolder (default)
#   sh shared/tools/sync.sh "deliver: MATI.lua" "$PUBLIC_DIR" # any other repo
set -u
MSG="${1:?usage: sync.sh \"<commit message>\" [repo-dir]}"
DIR="${2:-${SF_DIR:-${HOME:-/home/z}/SavedFolder}}"
cd "$DIR" || { echo "[sync] no repo at $DIR"; exit 1; }

# 1) commit local work
if [ -n "$(git status --porcelain)" ]; then
    git add -A
    git -c user.name="${GIT_NAME:-$(git config user.name || echo glm)}" \
        -c user.email="${GIT_EMAIL:-$(git config user.email || echo glm@savedfolder.local)}" \
        commit -q -m "$MSG" || { echo "[sync] commit failed"; exit 1; }
else
    echo "[sync] tree clean — nothing to commit"
fi

# 2) absorb parallel pushes
if ! git pull --rebase --autostash --quiet 2>/dev/null; then
    git rebase --abort 2>/dev/null
    echo "[sync] REBASE CONFLICT — your commit is restored locally, resolve by hand:"
    git status --short | head -5
    exit 1
fi

# 3) push (retry the pull+push pair if the remote moved again mid-flight)
i=0
until git push --quiet 2>/dev/null; do
    i=$((i + 1))
    [ "$i" -ge 3 ] && { echo "[sync] PUSH FAILED (3 attempts) — check token/auth"; exit 1; }
    git pull --rebase --autostash --quiet 2>/dev/null || { git rebase --abort 2>/dev/null; echo "[sync] REBASE CONFLICT on retry"; exit 1; }
done

# 4) VERIFY the remote actually moved to our commit (the silent-failure killer)
LOCAL=$(git rev-parse HEAD)
REMOTE=$(git ls-remote origin HEAD 2>/dev/null | cut -f1)
if [ "$LOCAL" != "$REMOTE" ]; then
    echo "[sync] VERIFY FAILED: local ${LOCAL%% *} != remote ${REMOTE:-<no answer>}"
    echo "[sync] the push did NOT land — do not trust it; investigate before moving on"
    exit 1
fi

echo "[sync] OK  $(git log --oneline -1)"
echo "[sync] newest history (watch for the other glm's work):"
git log --format="    %h %s" -4 | head -4
