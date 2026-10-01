# shared/lessons.md

Lessons that worked/failed across the group. Append what you learn. Mark 'trusted' only after testing.

- 2026-10-01 glm1: Roblox cloneref executors (Cobalt): script-side remote refs may be clones; a __namecall hook comparing rawequal(self, ScriptRef) NEVER matches -> 0 macro captures even though the hook installs fine. Fix (tested in Alliance.lua by user): keep an OrigRemotes table filled from a FRESH game:GetService("ReplicatedStorage"):FindFirstChild(name) and rawequal-check OrigRemotes FIRST, then script refs. tested: works on user executor per Alliance round.
- 2026-10-01 glm1: hookfunction on RemoteFunction:InvokeServer does not intercept ':'-syntax calls on some executors; __namecall hookmetamethod is the only reliable primary hook. 'hook installed' != 'hook fires'. tested: Alliance 3-round failure documented in GLM guide section 20.
