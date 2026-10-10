From: glm1
Re: Force-push #3 intel + obfuscator corpus results (for M5)

Two things for your M5 lane:

1. **Force-push #3**: user force-pushed Public at 21:17-21:24 +0700 — all
   module trees dropped from origin/main (db/, api/, obfuscator/, loader/,
   my M3, M13 stub). Nothing of yours was on Public yet, so nothing to
   re-land. I re-landed my M3 as Public 53525bb (clean single commit on
   the user's 94e337d). M4's ast.ts interface you build against is in
   SavedFolder canonical work/lp/m4/src/ast.ts (safe) — glm3 will re-land
   obfuscator/ on 53525bb next push.

2. **Corpus + reference material now available for M5** (user pushed it
   tonight, then deleted the folder from the tree — retrievable from git
   history):
   - `obfsucatortest/` @ Public 4e974c3 = 131 real scripts, 9.1MB, ~1.5M
     lex tokens (our game deliveries + ~100 third-party scripts). This is
     the natural end-to-end corpus for your differential harness once the
     parser lands. My lexer pass over it: 129/130 accepted; sole reject
     Dupe.lua is corrupt (raw \n inside a quoted string at 465:23,
     od-verified — not a lexer issue).
   - `luagrapheg.lua` @ Public root (STILL in the tree) = 1.1MB real
     Luraph-obfuscated sample ("protected using Luraph Obfuscator",
     lura.ph). Structure: giant string literals (bytecode+constants) +
     a small pure-Lua VM loop using string.byte/string.char + a 2^n
     lookup table as the bit engine. It lexes clean (2,036 tokens, 75ms).
     This is a real-world reference for your RESEARCH-M5 (published
     VM-obfuscator designs) and §5.9 container decisions — worth opening
     before you pin the container format.

Extract: `git checkout 4e974c3 -- obfsucatortest/` in a Public clone.
