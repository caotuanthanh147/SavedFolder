import { describe, expect, test } from "bun:test";
import { packageInit, isBuildId } from "../src/initpack";

const enc = (s: string) => new TextEncoder().encode(s);

const INIT_A = `-- init fixture A
_REC.initRuns = _REC.initRuns + 1
return function(p)
  _REC.entryCalls = _REC.entryCalls + 1
  _REC.payload = p
  return true
end
`;

const INIT_B = INIT_A + "-- a second line changes the content\n";

describe("packageInit", () => {
  test("build id is content-addressed and 12 hex chars", async () => {
    const a = await packageInit(enc(INIT_A), 1760000000);
    expect(isBuildId(a.build)).toBe(true);
    expect(a.build.startsWith("b")).toBe(true);
    expect(a.build.length).toBe(13);
    expect(a.fileName).toBe("init_" + a.build + ".lua");
    expect(a.size).toBe(INIT_A.length);
    expect(a.sha256Hex).toHaveLength(64);
    expect(a.createdAt).toBe(1760000000);
  });

  test("same content -> same build id (deterministic)", async () => {
    const a1 = await packageInit(enc(INIT_A), 1760000000);
    const a2 = await packageInit(enc(INIT_A), 1760009999);
    expect(a2.build).toBe(a1.build);
    expect(a2.fnv).toBe(a1.fnv);
    expect(a2.djb).toBe(a1.djb);
    expect(a2.createdAt).not.toBe(a1.createdAt); // packaging time differs
  });

  test("different content -> different build id (cache-busting)", async () => {
    const a = await packageInit(enc(INIT_A), 1760000000);
    const b = await packageInit(enc(INIT_B), 1760000000);
    expect(b.build).not.toBe(a.build);
    expect(b.fnv).not.toBe(a.fnv);
    expect(b.djb).not.toBe(a.djb);
  });

  test("sha256 matches an independent digest", async () => {
    const a = await packageInit(enc(INIT_A), 0);
    const digest = await crypto.subtle.digest("SHA-256", enc(INIT_A) as unknown as ArrayBuffer);
    const hex = Buffer.from(digest).toString("hex");
    expect(a.sha256Hex).toBe(hex);
    expect(a.build).toBe("b" + hex.slice(0, 12));
  });
});

describe("isBuildId", () => {
  test("accepts only b + 12 lowercase hex", () => {
    expect(isBuildId("b0123456789ab")).toBe(true);
    expect(isBuildId("0123456789ab")).toBe(false); // missing b prefix
    expect(isBuildId("b0123456789ABC")).toBe(false); // uppercase
    expect(isBuildId("b0123456789a")).toBe(false); // too short
    expect(isBuildId("b/../../etc")).toBe(false); // path traversal
    expect(isBuildId("b0123456789ab.lua")).toBe(false); // suffix
  });
});
