# Canonical JSON (x-sig input clarification)

doc.md §5.4 requires `x-sig` over `code | message | canonical(data) | x-ts`
but does not define `canonical()`. M3 defines it as follows (flagged as a
Contract Issue for M1 confirmation; the definition is chosen so a Roblox
client can reproduce it byte-for-byte after HttpService:JSONDecode):

- UTF-8, no whitespace: `{"k":"v","n":1}`
- Object keys sorted by byte value (ascending).
- Strings: `"` `\` and control bytes (< 0x20) escaped as `\"`, `\\`,
  `\u00xx`. No other escapes.
- Numbers: integers in decimal, no exponent, no leading `+`/zeros.
  Non-integers are not representable (envelope data fields are
  integers, strings, booleans, or null only).
- Booleans: `true` / `false`.
- JSON `null` values are OMITTED (key dropped). Roblox's
  HttpService:JSONDecode erases null-valued keys, so the server MUST
  canonicalize the same way — i.e. sign the envelope data with
  null-valued keys removed. See proof-spec.md clarification C3.
