#!/usr/bin/env python3
r"""deobf_search.py — fast exploration of huge deobfuscated dumps (2-12MB .lua / .txt).

The recurring workflow this replaces (manual grep archaeology every session):
  find a remote -> trace its wrapper to the WIRE level -> read payload shape ->
  find attributes/tags -> locate the enclosing function for context.

Usage:  python3 deobf_search.py FILE COMMAND [ARGS]
Commands:
  find PAT [-C N]     regex search (ignorecase), N context lines (default 2)
  fn LINE [-C N]      extract the Lua block enclosing LINE (function/if/do
                      nesting via depth scan) + its ancestor chain
  remote [NAME]       no NAME: remote usage map (FireServer/InvokeServer/Fire/
                      Invoke/OnClientEvent/OnServerEvent call sites, receiver
                      + first-string-arg heuristics, counts, first lines).
                      With NAME: every line mentioning NAME (ignorecase).
  strings PAT         search string LITERALS only (code stripped)
  tags                CollectionService tag census (GetTagged/AddTag/HasTag/...)
  attrs               GetAttribute/SetAttribute/...Signal name census

Line numbers match the original file exactly (masking is length-preserving).
Examples:
  python3 deobf_search.py game_deobf.lua remote PlaceTower
  python3 deobf_search.py game_deobf.lua fn 4508 -C 1
  python3 deobf_search.py game_deobf.lua find "GetTagged\(" -C 3
  python3 deobf_search.py game_dump.txt tags
"""
import re, sys
from collections import defaultdict

MASK_RE = re.compile(
    r"""(?P<lc>--\[\[(?s:.*?)\]\])"""
    r"""|(?P<bc>--\[=*\[(?s:.*?)\]=*\])"""
    r"""|(?P<ln>--[^\n]*)"""
    r"""|(?P<ls>\[(=*)\[(?s:.*?)\]\2\])"""
    r"""|(?P<dq>"(?:\\.|[^"\\\n])*")"""
    r"""|(?P<sq>'(?:\\.|[^'\\\n])*')"""
)

def mask(text):
    """Blank out comments + string literals with spaces; preserve length/newlines."""
    def repl(m):
        s = m.group(0)
        return "".join(c if c == "\n" else " " for c in s)
    return MASK_RE.sub(repl, text)

OPEN_RE  = re.compile(r"\b(function|if|do|repeat)\b")
CLOSE_RE = re.compile(r"\b(end|until)\b")
# note: 'for'/'while' are NOT openers — their 'do' opens for them; 'if' pairs with
# its 'then' via one 'end'; 'elseif' does not match \bif\b (word boundary).

def load(path):
    with open(path, encoding="utf-8", errors="replace") as f:
        raw = f.read()
    lines = raw.split("\n")
    masked = mask(raw).split("\n")
    return lines, masked

def blocks(masked):
    """Yield (start, end, depth_after_start) for every complete block; also
    return the still-open stack [(start,...)]."""
    stack, done, depth = [], [], 0
    for i, ln in enumerate(masked, 1):
        o = len(OPEN_RE.findall(ln)); c = len(CLOSE_RE.findall(ln))
        before = depth
        depth += o - c
        # any level crossed upward starting at this line -> that line opens a block
        for lvl in range(before + 1, depth + 1):
            stack.append((i, lvl))
        while stack and depth < stack[-1][1]:
            s, lvl = stack.pop()
            done.append((s, i, lvl))
    return done, stack

def cmd_fn(lines, masked, target, ctx):
    done, open_stk = blocks(masked)
    open_as_done = [(s, 10**9, l) for s, l in open_stk]
    inside = sorted([b for b in done + open_as_done if b[0] <= target <= b[1]],
                    key=lambda b: b[0])
    if not inside:
        print(f"line {target}: no enclosing block found"); return
    print(f"== block chain containing line {target} (innermost last) ==")
    for s, e, lvl in inside[-6:]:
        etag = "EOF(open)" if e == 10**9 else f"L{e}"
        print(f"  L{s}-{etag} (depth {lvl}): {lines[s-1].strip()[:100]}")
    s, e, _ = inside[-1]
    lo, hi = max(1, s - ctx), min(len(lines), e + ctx)
    print(f"== innermost block L{s}-L{e} (with context L{lo}-L{hi}) ==")
    for i in range(lo, hi + 1):
        mark = ">>" if i == target else ("  " if s <= i <= e else "~~")
        print(f"{mark}{i:6d}| {lines[i-1]}")

def cmd_find(lines, masked, pat, ctx, only_strings=False):
    rx = re.compile(pat, re.I)
    hits = 0
    for i in range(len(lines)):
        hay = lines[i] if not only_strings else string_lit(lines[i])
        if rx.search(hay):
            hits += 1
            lo, hi = max(0, i - ctx), min(len(lines), i + ctx + 1)
            for j in range(lo, hi):
                mark = ">>" if j == i else "  "
                print(f"{mark}{j+1:6d}| {lines[j]}")
            if hits >= 400:
                print("... (capped at 400 hits)"); break
    print(f"-- {hits} hit(s) for /{pat}/")

LIT_RE = re.compile(r'"((?:\\.|[^"\\\n])*)"|\'((?:\\.|[^\'\\\n])*)\'')
def string_lit(line):
    return " ".join(m.group(1) or m.group(2) or "" for m in LIT_RE.finditer(line))

CALL_PATTERNS = [
    ("FireServer",  re.compile(r"([\w\.\:\[\]\"']+)[\.:]FireServer\s*\(")),
    ("InvokeServer",re.compile(r"([\w\.\:\[\]\"']+)[\.:]InvokeServer\s*\(")),
    ("Fire",        re.compile(r"([\w\.\:\[\]\"']+):Fire\s*\(")),
    ("Invoke",      re.compile(r"([\w\.\:\[\]\"']+):Invoke\s*\(")),
    ("OnClientEvent", re.compile(r"([\w\.\:\[\]\"'\"]+)[\.:]OnClientEvent")),
    ("OnServerEvent", re.compile(r"([\w\.\:\[\]\"'\"]+)[\.:]OnServerEvent")),
]

def cmd_remote(lines, masked, name, ctx):
    if name:
        cmd_find(lines, masked, re.escape(name), ctx); return
    print("== remote usage map (receiver heuristic -> hits, first lines) ==")
    stats = defaultdict(lambda: [0, []])
    # use RAW lines for first-string-arg capture
    for kind, rx in CALL_PATTERNS:
        for i, ln in enumerate(lines, 1):
            m = rx.search(ln)
            if not m: continue
            recv = m.group(1)
            arg = ""
            rest = ln[m.end():m.end()+80]
            am = re.match(r'\s*"([^"]+)"', rest) or re.match(r"\s*'([^']+)'", rest)
            if am: arg = am.group(1)
            key = kind + ": " + recv + (('("' + arg + '")') if arg else "")
            st = stats[key]; st[0] += 1
            if len(st[1]) < 5: st[1].append(i)
    for key, (n, ls) in sorted(stats.items(), key=lambda kv: -kv[1][0]):
        print(f"  {n:4d}x  L{','.join(map(str, ls))}{'...' if n>5 else ''}  {key}")
    defs = defaultdict(lambda: [0, []])
    for i, ln in enumerate(lines, 1):
        if "RemoteEvent" in ln or "RemoteFunction" in ln:
            d = defs[("RemoteEvent" if "RemoteEvent" in ln else "RemoteFunction")]
            d[0] += 1
            if len(d[1]) < 6: d[1].append(i)
    for k, (n, ls) in defs.items():
        print(f"  literal '{k}': {n}x at L{','.join(map(str, ls))}{'...' if n>6 else ''}")

def cmd_tags(lines, masked):
    rx = re.compile(r"(GetTagged|GetInstanceAddedSignal|AddTag|RemoveTag|HasTag)\s*\(\s*[\"']([^\"']+)[\"']")
    stats = defaultdict(lambda: [0, []])
    for i, ln in enumerate(lines, 1):
        for m in rx.finditer(ln):
            st = stats[m.group(1) + '("' + m.group(2) + '")']
            st[0] += 1
            if len(st[1]) < 4: st[1].append(i)
    print("== CollectionService tags ==")
    for k, (n, ls) in sorted(stats.items(), key=lambda kv: -kv[1][0]):
        print(f"  {n:4d}x  L{','.join(map(str, ls))}{'...' if n>4 else ''}  {k}")
    if not stats: print("  (none found)")

def cmd_attrs(lines, masked):
    rx = re.compile(r"(GetAttribute|SetAttribute|GetAttributeChangedSignal)\s*\(\s*[\"']([^\"']+)[\"']")
    stats = defaultdict(lambda: [0, []])
    for i, ln in enumerate(lines, 1):
        for m in rx.finditer(ln):
            st = stats[m.group(2)]; st[0] += 1
            if len(st[1]) < 4: st[1].append(i)
    print("== attribute census (name -> accesses, first lines) ==")
    for k, (n, ls) in sorted(stats.items(), key=lambda kv: -kv[1][0]):
        print(f"  {n:4d}x  L{','.join(map(str, ls))}{'...' if n>4 else ''}  {k}")
    if not stats: print("  (none found)")

def main():
    if len(sys.argv) < 3:
        print(__doc__); sys.exit(2)
    path, cmd = sys.argv[1], sys.argv[2]
    args = sys.argv[3:]
    ctx = 2
    if "-C" in args:
        i = args.index("-C"); ctx = int(args[i+1]); del args[i:i+2]
    lines, masked = load(path)
    if   cmd == "find":    cmd_find(lines, masked, args[0], ctx)
    elif cmd == "strings": cmd_find(lines, masked, args[0], ctx, only_strings=True)
    elif cmd == "fn":      cmd_fn(lines, masked, int(args[0]), ctx)
    elif cmd == "remote":  cmd_remote(lines, masked, args[0] if args else None, ctx)
    elif cmd == "tags":    cmd_tags(lines, masked)
    elif cmd == "attrs":   cmd_attrs(lines, masked)
    else: print(f"unknown command: {cmd}"); sys.exit(2)

if __name__ == "__main__":
    main()
