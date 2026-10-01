#!/usr/bin/env python3
"""lua_lint.py — mechanical rule-violation scanner for project .lua scripts.

Usage:  python3 lua_lint.py [--from N] [--to M] FILE [FILE...]
       --from/--to  : restrict ERROR-level Luau checks to lines N..M (the game
                      section you wrote). Outside the range they downgrade to
                      warnings, because the canonical Template.lua legitimately
                      uses executor-env Luau (typeof, bare unpack) and the mock
                      harness shims those. YOUR game section must be Lua 5.4 clean.

Checks:
  E1  syntax     : luac5.4 -p (auto-found on PATH or ~/.lua54/bin)
  E2  comments   : any '--' outside a string literal (deliverables = zero comments)
  E3  goto/continue (banned)
  E4  Luau-only in range: bare unpack(, table.clone/freeze, string.split/trim,
                   math.round, bit32, typeof(   (Lua 5.4 harness can't run these)
  W5  print(     : debug leftover warning (use notify/Fluent)
  W6  Luau-only outside range (see E4) — template region, usually fine

Exit code = ERROR count>0 ? 1 : 0.
"""
import os, re, subprocess, sys

LUAC = None
for c in ("luac5.4", os.path.expanduser("~/.lua54/bin/luac5.4")):
    if os.access(c, os.X_OK) or os.system(f"command -v {c} >/dev/null 2>&1") == 0:
        LUAC = c
        break

STR_OR_COMMENT = re.compile(
    r"""(--\[\[.*?\]\]|--[^\n]*|"(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'|\[\[.*?\]\])""", re.S)

def strip_strings_comments(line):
    def repl(m):
        s = m.group(0)
        if s.startswith("--"):
            return " " * len(s)
        return '"' + " " * max(0, len(s) - 2) + '"'
    return STR_OR_COMMENT.sub(repl, line)

HARD = [
    ("E2", re.compile(r"--"),                        "comment (-- banned in deliverables)"),
    ("E3", re.compile(r"\bgoto\b|\bcontinue\b"),     "goto/continue statement"),
]
LUAU_ONLY = [
    ("E4", re.compile(r"(?<![\w.])unpack\s*\("),     "bare unpack() — Luau/5.1 only (5.4: table.unpack)"),
    ("E4", re.compile(r"\btable\.clone\b|\btable\.freeze\b"), "Luau-only table.clone/freeze"),
    ("E4", re.compile(r"\bstring\.split\b|\bstring\.trim\b"), "Luau-only string.split/trim"),
    ("E4", re.compile(r"\bmath\.round\b"),           "math.round — Luau-only (5.4: math.floor(x+0.5))"),
    ("E4", re.compile(r"\bbit32\b"),                 "bit32 — Luau-only"),
    ("E4", re.compile(r"\btypeof\s*\("),             "typeof() — Luau-only (5.4: type)"),
]
WARN_ONLY = [
    ("W5", re.compile(r"\bprint\s*\("),              "print() debug leftover? (use notify/Fluent)"),
]

def lint(path, lo, hi):
    errors = warnings = 0
    if LUAC:
        r = subprocess.run([LUAC, "-p", path], capture_output=True, text=True)
        if r.returncode != 0:
            first = (r.stderr or r.stdout).strip().splitlines()
            print(f"{path}:E1: luac syntax: {first[0] if first else 'parse error'}")
            errors += 1
    try:
        with open(path, encoding="utf-8", errors="replace") as f:
            lines = f.read().split("\n")
    except OSError as e:
        print(f"{path}: E0 cannot read: {e}"); return 1, 0
    for i, raw in enumerate(lines, 1):
        code = strip_strings_comments(raw)
        for cid, rx, msg in HARD:
            if rx.search(code):
                print(f"{path}:{i}:{cid}: {msg}  |  {raw.strip()[:90]}"); errors += 1
        for cid, rx, msg in LUAU_ONLY:
            if rx.search(code):
                in_range = (lo is None or i >= lo) and (hi is None or i <= hi)
                if in_range:
                    print(f"{path}:{i}:{cid}: {msg}  |  {raw.strip()[:90]}"); errors += 1
                else:
                    print(f"{path}:{i}:W6: (template region) {msg}  |  {raw.strip()[:90]}"); warnings += 1
        for cid, rx, msg in WARN_ONLY:
            if rx.search(code):
                print(f"{path}:{i}:{cid}: {msg}  |  {raw.strip()[:90]}"); warnings += 1
    return errors, warnings

def main():
    args = sys.argv[1:]
    lo = hi = None
    files = []
    while args:
        a = args.pop(0)
        if a == "--from":   lo = int(args.pop(0))
        elif a == "--to":   hi = int(args.pop(0))
        else:               files.append(a)
    if not files:
        print(__doc__); sys.exit(2)
    te = tw = 0
    for p in files:
        e, w = lint(p, lo, hi); te += e; tw += w
    rng = "" if lo is None and hi is None else f" (strict range {lo or 0}..{hi or 'end'})"
    print(f"-- {len(files)} file(s){rng}: {te} error(s), {tw} warning(s)"
          + ("  [PASS]" if te == 0 else "  [FAIL]"))
    sys.exit(1 if te else 0)

if __name__ == "__main__":
    main()
