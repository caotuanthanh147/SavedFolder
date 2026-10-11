#!/usr/bin/env bash
# M12 backup script (doc §19 "Daily backups with retention; disaster
# recovery runbook", D-M12-12). Two modes:
#
#   LOCAL/dev:  backup.sh --local <sqlite-file> --out <dir> [--keep N]
#               Snapshot-consistent copy via SQLite VACUUM INTO (safe on a
#               live DB), SHA-256 manifest, retention prune.
#
#   PRODUCTION: backup.sh --remote <d1-database-name> --out <dir> [--keep N]
#               Wraps `wrangler d1 export` (owner workstation with wrangler
#               credentials — a Worker cannot export D1 cross-database).
#
# Retention: keeps the N newest backups in <dir> (default 14), prunes older.
# Schedule: cron daily (see RUNBOOK-M12 §backups).
#
# Exit codes: 0 ok, 1 usage, 2 backup failed, 3 integrity check failed.

set -euo pipefail

MODE=""
DB=""
OUT=""
KEEP=14

usage() {
  sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'
  exit 1
}

while [ $# -gt 0 ]; do
  case "$1" in
    --local) MODE="local"; DB="$2"; shift 2 ;;
    --remote) MODE="remote"; DB="$2"; shift 2 ;;
    --out) OUT="$2"; shift 2 ;;
    --keep) KEEP="$2"; shift 2 ;;
    -h|--help) usage ;;
    *) echo "unknown arg: $1" >&2; usage ;;
  esac
done

[ -n "$MODE" ] && [ -n "$DB" ] && [ -n "$OUT" ] || usage
mkdir -p "$OUT"
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"

if [ "$MODE" = "local" ]; then
  [ -f "$DB" ] || { echo "no such database file: $DB" >&2; exit 2; }
  DEST="$OUT/backup-$STAMP.sqlite"
  # VACUUM INTO = online snapshot: readers/writers keep working; the result
  # is a defragmented, integrity-checkable copy (SQLite docs, "VACUUM INTO").
  if ! bun -e "const {Database}=require('bun:sqlite');new Database(process.argv[1],{readonly:true}).exec('VACUUM INTO \\''+process.argv[2]+'\\'')" "$DB" "$DEST" 2>/dev/null; then
    # Fallback for hosts without bun: sqlite3 CLI if present.
    if command -v sqlite3 >/dev/null 2>&1; then
      sqlite3 "$DB" "VACUUM INTO '$DEST';"
    else
      echo "backup failed: need bun or sqlite3" >&2
      rm -f "$DEST"
      exit 2
    fi
  fi
else
  DEST="$OUT/backup-$STAMP.sql"
  if ! npx wrangler d1 export "$DB" --remote --output="$DEST"; then
    echo "wrangler d1 export failed" >&2
    rm -f "$DEST"
    exit 2
  fi
fi

# Integrity: every backup must be verifiable before it counts.
if [ "$MODE" = "local" ]; then
  CHECK=$(bun -e "const {Database}=require('bun:sqlite');const db=new Database(process.argv[1],{readonly:true});const r=db.query('PRAGMA integrity_check').get();console.log(r.integrity_check||'unknown')" "$DEST" 2>/dev/null || true)
  if command -v sqlite3 >/dev/null 2>&1 && [ -z "$CHECK" ]; then
    CHECK=$(sqlite3 "$DEST" "PRAGMA integrity_check;" 2>/dev/null || true)
  fi
  [ "$CHECK" = "ok" ] || { echo "integrity_check: ${CHECK:-failed}" >&2; exit 3; }
fi

SHA=$(sha256sum "$DEST" | cut -d' ' -f1)
SIZE=$(stat -c%s "$DEST")
echo "$(date -u +%FT%TZ) $STAMP sha256=$SHA bytes=$SIZE file=$DEST" >> "$OUT/manifest.log"

# Retention prune: newest KEEP backups stay.
ls -1t "$OUT"/backup-*.sqlite "$OUT"/backup-*.sql 2>/dev/null | tail -n +$((KEEP + 1)) | while read -r old; do
  echo "$(date -u +%FT%TZ) prune $old" >> "$OUT/manifest.log"
  rm -f "$old"
done

echo "backup OK: $DEST ($(printf '%d' "$SIZE") bytes, sha256 $SHA)"
