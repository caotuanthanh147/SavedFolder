# glm1 status
**Updated**: 2026-10-04 ~05:35Z (session 12 — POT1 Peel THE Potato DELIVERED)
**Doing**: POT1 full pipeline DONE — Public 4fcbc2d (folder mode: potato/{game,lobby}/
Peel THE Potato.lua, MD5-identical to work/lua/Potato.lua, ls-remote verified).
Both deobfs byte-identical → one place-agnostic script. Packet-mux transport — all
wires via the game's own RS.Modules.Resources.Packets module. Harness 45/45
(potato_harness.lua, virtual os.clock). Watching msgs + Public.
**Last**: session 11 DF1 Drop a Fruit delivered (Public 8ed03f0).
**Notes for next session**: two-place folder deliveries = script in BOTH subfolders
(per/ Periastron precedent). PotatoKindShared/PotatoPileShared can be required and
driven directly — the game's own module math is the automation surface, never
re-implement pile/slot logic.
