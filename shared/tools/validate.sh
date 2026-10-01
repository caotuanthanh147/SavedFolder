#!/bin/sh
# validate.sh <script.lua> [template.lua] — static validation for a game script: luac5.4 -p syntax check, template-verbatim diff (common head/tail prefix-suffix measurement), style checks (comment-only lines, goto/continue, trailing whitespace). Exit 0 only if syntax OK and template diff is confined to the middle game-section region + tail wiring lines.
set -u
SCRIPT="${1:?usage: validate.sh <script.lua> [template.lua]}"
TEMPLATE="${2:-${SF_DIR:-${HOME:-/home/z}/SavedFolder}/work/lua/Template.lua}"
LUAC="${LUAC:-${HOME:-/home/z}/bin/luac5.4}"
[ -x "$LUAC" ] || LUAC="$(command -v luac5.4 || true)"
[ -n "$LUAC" ] || { echo "luac5.4 not found (run bootstrap.sh)"; exit 1; }
[ -f "$SCRIPT" ] || { echo "missing script: $SCRIPT"; exit 1; }
[ -f "$TEMPLATE" ] || { echo "missing template: $TEMPLATE"; exit 1; }

fail=0

echo "== luac5.4 -p"
if "$LUAC" -p "$SCRIPT" 2>&1; then echo "OK"; else fail=1; fi

echo "== template diff (script vs $(basename "$TEMPLATE"))"
python3 - "$SCRIPT" "$TEMPLATE" << 'EOF'
import sys
s = open(sys.argv[1], encoding='utf-8', errors='replace').read().splitlines()
t = open(sys.argv[2], encoding='utf-8', errors='replace').read().splitlines()
# common prefix
p = 0
while p < len(s) and p < len(t) and s[p] == t[p]:
    p += 1
# common suffix
q = 0
while q < len(s) - p and q < len(t) - p and s[len(s)-1-q] == t[len(t)-1-q]:
    q += 1
mid_s = len(s) - p - q
mid_t = len(t) - p - q
print(f"verbatim head: {p} lines")
print(f"verbatim tail: {q} lines")
print(f"script middle (game section): {mid_s} lines (template middle replaced: {mid_t})")
if p == 0:
    print("WARN: no common head — is this really built on the template?")
if mid_s <= 0:
    print("WARN: script has no game section?")
# changed lines inside the verbatim tail region (wiring edits like SaveManager folder)
# alignment is from the END: s[len(s)-1-k] <-> t[len(t)-1-k]
tail_changed = []
for i in range(p + mid_s, len(s)):
    j = i + len(t) - len(s)
    if 0 <= j < len(t) and s[i] != t[j]:
        tail_changed.append((i + 1, s[i][:80]))
if tail_changed:
    print(f"tail contains {len(tail_changed)} changed line(s) (expected: only SaveManager folder / wiring):")
    for ln, txt in tail_changed[:5]:
        print(f"  L{ln}: {txt}")
EOF

echo "== style: comment-only lines (target: 0)"
n=$(grep -cE '^[[:space:]]*--' "$SCRIPT" || true)
echo "comment-only lines: $n"
[ "$n" -gt 0 ] && { grep -nE '^[[:space:]]*--' "$SCRIPT" | head -5; echo "(rule: zero comments in game scripts)"; }

echo "== style: goto / continue"
grep -nE '\bgoto\b|\bcontinue\b' "$SCRIPT" | head -5 || echo "none"

echo "== style: pcall double-wrap hint (Func* wrapping own pcall AND being passed through SafeLoop)"
grep -nE 'pcall\(function\(\)' "$SCRIPT" | wc -l | xargs echo "inline pcall(function() ...) count (cross-check against Thread(... SafeLoop ...) wiring):"

[ "$fail" -eq 0 ] && echo "RESULT: syntax OK, template diff measured — review output above" || echo "RESULT: FAILED"
exit $fail
