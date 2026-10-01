#!/bin/sh
# repack.sh <orig.zip> <script.lua> <inner-path> [--commit "<message>"] [--repo <public-clone>] [--name <zip-name>] — deliver a built script: repack the game zip with the script injected at <inner-path>, verify every ORIGINAL member (except the injected path itself) is byte-identical (content MD5), then optionally copy the zip to the Public repo root and commit+push (the clone's remote must already carry auth — never pass a token here). Uses python3 zipfile (unzip CLI glob-matches [brackets] in member names — unsafe).
set -u
ZIP="${1:?usage: repack.sh <orig.zip> <script.lua> <inner-path> [--commit msg] [--repo dir] [--name zipname]}"
SCRIPT="${2:?missing script.lua}"
INNER="${3:?missing inner path (e.g. 'GameFolder/Game.lua' or 'tdref/usethisfileSnack.lua')}"
shift 3 || true
MSG=""
REPO="/home/z/Public"
NAME=""
while [ $# -gt 0 ]; do
    case "$1" in
        --commit) MSG="${2:?--commit needs a message}"; shift 2 ;;
        --repo) REPO="${2:?--repo needs a dir}"; shift 2 ;;
        --name) NAME="${2:?--name needs a zip name}"; shift 2 ;;
        *) echo "unknown arg: $1"; exit 1 ;;
    esac
done
[ -f "$ZIP" ] || { echo "missing zip: $ZIP"; exit 1; }
[ -f "$SCRIPT" ] || { echo "missing script: $SCRIPT"; exit 1; }
[ -z "$NAME" ] && NAME="$(basename "$ZIP")"

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
OUTZIP="$WORK/$NAME"

python3 - "$ZIP" "$SCRIPT" "$INNER" "$OUTZIP" << 'PYEOF' || exit 1
import sys, zipfile, hashlib, os, time
zip_path, script_path, inner, out = sys.argv[1:5]

def md5(b):
    return hashlib.md5(b).hexdigest()

with zipfile.ZipFile(zip_path) as z:
    infos = [i for i in z.infolist() if not i.filename.endswith('/')]
    before = {i.filename: md5(z.read(i.filename)) for i in infos}
    replaced = inner in before
    with open(script_path, 'rb') as f:
        script_data = f.read()
    with zipfile.ZipFile(out, 'w', zipfile.ZIP_DEFLATED) as zout:
        for info in infos:
            if info.filename == inner:
                continue
            zout.writestr(info, z.read(info.filename))
        zi = zipfile.ZipInfo(inner, date_time=time.localtime()[:6])
        zi.compress_type = zipfile.ZIP_DEFLATED
        zout.writestr(zi, script_data)

with zipfile.ZipFile(out) as z:
    after = {i.filename: md5(z.read(i.filename)) for i in z.infolist() if not i.filename.endswith('/')}

orig_names = [n for n in before if n != inner]
changed = [n for n in orig_names if after.get(n) != before[n]]
missing = [n for n in orig_names if n not in after]
print(f"members: {len(before)} -> {len(after)}  ({'replacing' if replaced else 'adding'} {inner})")
if changed or missing:
    for n in changed:
        print(f"CHANGED original member: {n}")
    for n in missing:
        print(f"MISSING original member: {n}")
    print("FATAL: originals not byte-identical — NOT delivering")
    sys.exit(1)
print("originals byte-identical: OK")
if after.get(inner) != md5(script_data):
    print("FATAL: injected member md5 mismatch")
    sys.exit(1)
print(f"injected member md5 OK: {md5(script_data)}")
PYEOF

if [ -n "$MSG" ]; then
    echo "== commit to Public ($REPO as $NAME)"
    git -C "$REPO" pull --rebase --autostash --quiet 2>&1 | tail -1
    cp "$OUTZIP" "$REPO/$NAME"
    git -C "$REPO" add "$NAME"
    git -C "$REPO" -c user.name="${GIT_NAME:-glm}" -c user.email="${GIT_EMAIL:-glm@savedfolder.local}" commit -q -m "$MSG"
    git -C "$REPO" push 2>&1 | tail -2
else
    echo "== dry-run (no --commit): copy saved"
    cp "$OUTZIP" "/tmp/repacked-$NAME"
    echo "/tmp/repacked-$NAME"
fi
