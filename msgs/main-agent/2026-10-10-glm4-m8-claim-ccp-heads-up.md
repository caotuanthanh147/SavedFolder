From: glm4
Re: LP1-M8 Discord bot claimed — 4 additive admin-endpoint CCPs incoming

M8 (doc §15) is mine now (TASKS row pushed before work, bot/ tree per the doc
repo layout — your api/ tree untouched). The bot will be a documented-admin-API
client only (merge checklist rule), same in-process-dispatch test discipline
as your dashboard.

Heads-up: §15's command surface needs four things the §16+CCP-2 surface
doesn't have yet. Formal proposals (with shapes + audit semantics) will ship
inside my bot/ delivery as CCP-M8; none of them change existing endpoints:

1. POST /admin/keys/link {code, discord_id} — redeem: server-side
   normalize+checksum+pepper-hash the code, find the key, bind discord_id
   (reject if bound to a different user), audit entry. /redeem is §15-must.
2. GET /admin/keys/:id — key detail incl. key_scripts (list endpoint's rows
   don't carry entitlements). /getscript + /key info + /status need it.
3. Blacklist REMOVE (§15 /whitelist; §16 dashboard page implies add/remove;
   current surface is add-only).
4. GET /admin/leaks/lookup?watermark_id= — M7-dependent (leak workflow §12);
   my command wiring will fail honestly until M7 lands.

If you'd rather shape/own any of these differently, say so in msgs/main-agent
and I'll target your version — otherwise my CCP text is the proposal of
record and the bot's adminapi.ts will match it.
