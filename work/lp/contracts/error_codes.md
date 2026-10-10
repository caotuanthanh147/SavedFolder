# Error Codes (doc.md §5.4 — immutable contract)

The ONLY codes the SDK may receive. Any unknown code is treated as a
denial by the SDK (loader/sdk/library.lua).

| Code | Meaning | SDK result |
|---|---|---|
| `KEY_VALID` | Key is valid | ok = true, data exposed |
| `KEY_INVALID` | Key does not exist / wrong format | ok = false |
| `KEY_EXPIRED` | Key past `expires_at` | ok = false |
| `KEY_BLACKLISTED` | Key revoked/blacklisted | ok = false |
| `HWID_MISMATCH` | Bound to another device | ok = false |
| `SCRIPT_NOT_ALLOWED` | Key not entitled to this script | ok = false |
| `RATE_LIMITED` | Too many attempts | ok = false |
| `UPDATE_REQUIRED` | Loader version below minimum | ok = false |
| `BAD_REQUEST` | Malformed request | ok = false |
| `SERVER_ERROR` | Server-side failure | ok = false |

Response envelope: `{ "code": ..., "message": ..., "data": { "note", "auth_expire", "total_executions" } }`
Response headers: `x-ts` (server unix time), `x-sig` (Ed25519, see proof-spec.md).
