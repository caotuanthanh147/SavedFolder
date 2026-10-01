#!/bin/sh
# newgame.sh <game.zip> [dest-dir] — start a new game task: extract the user's uploaded zip, inventory the deobf/dump/Template files, verify the expected structure, and print the Rule-18 pipeline checklist with concrete paths.
set -u
ZIP="${1:?usage: newgame.sh <game.zip> [dest-dir]}"
DEST="${2:-/home/z/my-project/upload/$(basename "$ZIP" .zip | tr -d '[]()')}"

echo "== extracting $(basename "$ZIP")"
mkdir -p "$DEST"
unzip -q -o "$ZIP" -d "$DEST" || exit 1
echo "-> $DEST"

echo "== inventory"
deobf=$(find "$DEST" -type f -iname "*deob*" -name "*.lua" | head -5)
dump=$(find "$DEST" -type f -name "game_dump.txt" | head -5)
tmpl=$(find "$DEST" -type f -name "Template.lua" | head -5)
[ -n "$deobf" ] && echo "deobf:      $deobf" || echo "deobf:      NONE FOUND — ask the user / check the zip"
[ -n "$dump" ] && echo "dump:       $dump" || echo "dump:       NONE FOUND"
[ -n "$tmpl" ] && echo "template:   $tmpl (Rule 14: re-sync work/lua/Template.lua from this if newer)" || echo "template:   (none in zip — keep current work/lua/Template.lua)"
echo "lua files:  $(find "$DEST" -type f -name "*.lua" | wc -l)  txt dumps: $(find "$DEST" -type f -name "*.txt" | wc -l)"

echo "== structure notes"
find "$DEST" -type d | head -8 | while IFS= read -r d; do echo "  dir: $d"; done

cat << 'EOF'

== pipeline checklist (GLM_SCRIPTING_RULES.md Rule 18 order)
 1. Re-read work/lua/GLM_SCRIPTING_RULES.md (all sections) + work/lua/Template.lua in full.
 2. If the zip carried a Template.lua: diff against work/lua/Template.lua, re-sync if newer.
 3. Study the deobf(s) + dump(s): verify EVERY remote (name, ClassName, signature at the
    client call site — wrapper vs wire, EasyEvents-style wrappers included, §20.6/§24).
 4. Build work/lua/<Game>.lua: template verbatim head/tail, game section in the marked
    region, SaveManager folder "Yuri/<Game>". Zero comments. Clean-code rules (see
    work/lua/clean-code-violations-scpinc.md: spec-table features, ONE pcall owner,
    init-not-step, provenance constants).
 5. Mock harness: copy shared/tools/harness_lib.lua as the prelude, append game mocks
    + checks. grep your Instance mock for FindFirstChildOfClass FIRST.
 6. sh shared/tools/validate.sh work/lua/<Game>.lua
 7. sh shared/tools/repack.sh <orig-zip> work/lua/<Game>.lua "<inner path>" --commit "<game>: add <Game>.lua automation (...)"
 8. Update work/lua/TASK_SOURCE.md table + TASKS.md + shared/lessons.md; message the
    user's delivery in the worklog.
EOF
