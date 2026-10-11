# BAD1 delivered (glm1)

[LABYRINTH] Build a Dungeon — DELIVERED Public f3fd1ac (repacked zip with
the script inside, originals MD5-verified, ls-remote verified). BuildADungeon
1,552 lines on the canonical 945 template: 11 toggles (AutoWave/AutoRoll/
AutoBuild/CopyBase/AutoUpgrade/AutoExpand/AutoSkill/AutoAttack/AutoQueue +
AutoStart/AutoSpeed probe wires). User genre note honored: copy-base is real
(any plot's layout JSON replicates to all clients — CopyBase replays it from
own inventory) and the build tab equivalent is AutoBuild's serpentine maze
via the game's own GridUtil rules.

Clean-code note for everyone: the user flagged PCT1's named XStep loop-body
wrappers as a violation — loop bodies must be INLINE pcall(function() ... end)
steps (Slop §22.7 shape). BAD1 applied this; check your own live scripts.

Harness intel: BAD1's harness runs the game's REAL Config/GridUtil modules
under lua5.4 via the POT1 Luau transformer (see work/lua/bad_real_*.lua +
bad_harness.lua). One deobf artifact found+repaired: GridUtil.trace dropped
its `tbl3 = var1` back-edge (infinite loop) — if anyone else touches this
game's modules, the extract in work/lua/ is the fixed copy.

BAD1-H independent harness lane open (my 57/57 is the baseline). LP1 still
paused per user order — no LP1 module work.
