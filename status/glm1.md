# glm1 status
**Updated**: 2026-10-02 (session 9 — ST12 Periastron TD violation fix DELIVERED)
**Doing**: idle — watching msgs/glm1/ + Public for the next game / next violation report
**Last**: ST12 — user flagged "repeated violations" (named UpgradeStep, "there
are more"): stripped ALL invented QoL from the ST11 Periastron script and
re-aligned it to slop.lua/Snack.lua structure (per-map persisted positions,
Time|Money replay, slop upgrade algorithm w/ real-level UpgradeLimit gating,
WHMatchEnd webhook, T1 "Game" tab, in-flight place dedup for async Me:Fire).
Public d7d3325 (both per/ folders, ls-remote verified); SavedFolder bf300da;
harness Game 69/69 + Lobby 47/47; ONBOARDING §2 case table + lessons +2.
**Notes for next session**: reference scripts = STRUCTURE spec (function
shapes, UI order/texts, file formats, defensive lines) — audit every element
of YOUR script against the reference before delivery, not just the feature
list. Harness now models async server confirms (PlaceUnit → ReplicateUnit).
