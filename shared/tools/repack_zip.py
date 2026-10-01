#!/usr/bin/env python3
"""repack_zip.py — repack a game zip with new/replaced files, originals BYTE-IDENTICAL.

Delivery convention (Public repo): push the repacked game zip — every ORIGINAL
entry keeps its exact bytes (MD5-verified), only your added/replaced entries differ.

Usage:
  python3 repack_zip.py ORIGINAL.zip -o OUT.zip \
      [-a SRCPATH:ZIPPATH]...        # add/replace entries (SRCPATH -> zip path)
      [-d ZIPPATH]...                # delete entries (rare; user convention is keep-all)

What it does:
  1. Copies every original entry preserving order, compress_type, date_time,
     external_attr (dirs, exec bits) — content bytes untouched.
  2. Applies adds/replaces/deletes.
  3. VERIFIES the output: same entry order; every untouched original entry's
     MD5 identical; count matches expectation. Prints a per-entry report.
  4. Exits non-zero if ANY verification fails. Trust nothing, verify everything.
"""
import argparse, copy, hashlib, sys, zipfile

def md5(b): return hashlib.md5(b).hexdigest()

def main():
    ap = argparse.ArgumentParser(description="Repack zip, originals byte-identical (verified)")
    ap.add_argument("original")
    ap.add_argument("-o", "--out", required=True)
    ap.add_argument("-a", "--add", action="append", default=[], metavar="SRC:ZIPPATH")
    ap.add_argument("-d", "--delete", action="append", default=[], metavar="ZIPPATH")
    args = ap.parse_args()

    adds, dels = {}, set(args.delete)
    for spec in args.add:
        if ":" not in spec:
            sys.exit(f"bad -a spec '{spec}' (want SRC:ZIPPATH)")
        src, zp = spec.rsplit(":", 1)
        adds[zp] = src

    zin = zipfile.ZipFile(args.original, "r")
    names = zin.namelist()

    # sanity: add/delete targets must be explicit
    for zp in adds:
        if zp in dels: sys.exit(f"{zp}: both added and deleted")
    for zp in dels:
        if zp not in names: sys.exit(f"delete target not in zip: {zp}")

    zout = zipfile.ZipFile(args.out, "w")
    replaced = []
    for info in zin.infolist():
        if info.filename in dels:            continue
        if info.filename in adds:            replaced.append(info.filename); continue
        data = zin.read(info.filename)       # untouched: copy with original ZipInfo
        # NB: writestr MUTATES the ZipInfo it is given — pass a CLONE, or the
        # original archive's cached metadata (zin.filelist) gets corrupted and
        # every later zin.read() seeks to garbage offsets (BadZipFile).
        zout.writestr(copy.copy(info), data)
    for zp, src in adds.items():
        with open(src, "rb") as f: zout.writestr(zp, f.read(), compress_type=zipfile.ZIP_DEFLATED)
    zout.close()

    # ---------- verification pass ----------
    zchk = zipfile.ZipFile(args.out, "r")
    chk_names = zchk.namelist()
    # expected order: originals (minus deletions) keep their positions;
    # replaced entries stay in place; brand-new entries are appended.
    expect = [n for n in names if n not in dels] + [n for n in adds if n not in names]
    ok = True
    if chk_names != expect:
        ok = False
        print(f"[FAIL] entry order/count mismatch\n  want: {expect}\n  got : {chk_names}")
    bad = 0
    for n in names:
        if n in dels or n in adds: continue
        a, b = md5(zin.read(n)), md5(zchk.read(n))
        mark = "ok " if a == b else "FAIL"
        if a != b: ok = False; bad += 1
        print(f"[{mark}] {n}  {a[:10]}.. -> {b[:10]}..")
    for zp, src in adds.items():
        with open(src, "rb") as f: a = md5(f.read())
        b = md5(zchk.read(zp))
        mark = "ok " if a == b else "FAIL"
        if a != b: ok = False; bad += 1
        tag = "REPLACED" if zp in names else "NEW"
        print(f"[{mark}] {zp}  {tag} {a[:10]}..")
    for n in dels:
        print(f"[ok ] DELETED {n}")

    total_orig = len(names)
    print(f"-- {args.out}: {total_orig} original entries, {len(adds)} add/replace "
          f"({len(replaced)} replaced), {len(dels)} deleted; md5 mismatches: {bad}"
          + ("  [VERIFIED]" if ok else "  [FAILED]"))
    sys.exit(0 if ok else 1)

if __name__ == "__main__":
    main()
