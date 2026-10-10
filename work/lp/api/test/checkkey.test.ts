import { beforeAll, describe, expect, test } from "bun:test";
import { buildEnv, makeSignedInput, envelopeOf, hwidHashFor, SCRIPT_ID, TestEnv } from "./helpers";
import { buildRoutes, dispatch } from "../src/router";
import { b64urlDecode, canonicalJson } from "../src/contracts";
import { utf8 } from "../src/crypto";

let env: TestEnv;

beforeAll(async () => {
  env = await buildEnv();
});

async function post(body: Record<string, unknown> | null, opts: Parameters<typeof makeSignedInput>[3] = {}): Promise<Response> {
  const input = await makeSignedInput("POST", "/check_key", body, opts);
  return dispatch(buildRoutes(), env.ctx, env.config, input);
}

describe("POST /check_key happy path", () => {
  test("valid key returns KEY_VALID with contract-exact data, signed headers, hwid binding, event log", async () => {
    const key = await env.createKey({ note: "hello" });
    const res = await post({ key: key.plaintext, script_id: SCRIPT_ID, lv: "1.0.0" }, { headers: { "Delta-User-Identifier": "device-abc" } });
    expect(res.status).toBe(200);
    const envelope = await envelopeOf(res);
    expect(envelope.code).toBe("KEY_VALID");
    expect(envelope.message).toBe("The provided key is valid.");
    expect(envelope.data).toEqual({ note: "hello", auth_expire: 0, total_executions: 1 });

    const tsHeader = res.headers.get("x-ts");
    expect(tsHeader).not.toBeNull();
    expect(/^\d+$/.test(tsHeader!)).toBe(true);
    const sigHeader = res.headers.get("x-sig");
    expect(sigHeader).not.toBeNull();
    const payload = utf8(`${envelope.code}|${envelope.message}|${canonicalJson(envelope.data)}|${tsHeader}`);
    expect(await env.verifier.verify(payload, b64urlDecode(sigHeader!))).toBe(true);

    const row = env.db.prepare("SELECT hwid_hash, total_executions, first_used_at FROM keys WHERE id = ?").get(key.id) as { hwid_hash: string; total_executions: number; first_used_at: number };
    expect(row.hwid_hash).toBe(await hwidHashFor("device-abc"));
    expect(row.total_executions).toBe(1);
    expect(row.first_used_at).toBeGreaterThan(0);

    const events = env.db.prepare("SELECT type FROM events WHERE key_id = ? ORDER BY created_at DESC").all(key.id) as { type: string }[];
    expect(events[0].type).toBe("validate_ok");

    const second = await post({ key: key.plaintext, script_id: SCRIPT_ID, lv: "1.0.0" }, { headers: { "Delta-User-Identifier": "device-abc" } });
    const secondEnvelope = await envelopeOf(second);
    expect(secondEnvelope.data?.total_executions).toBe(2);
  });

  test("missing executor headers still succeed without touching hwid", async () => {
    const key = await env.createKey();
    const res = await post({ key: key.plaintext, script_id: SCRIPT_ID, lv: "1.0.0" }, { ip: "203.0.113.99" });
    const envelope = await envelopeOf(res);
    expect(envelope.code).toBe("KEY_VALID");
    const row = env.db.prepare("SELECT hwid_hash FROM keys WHERE id = ?").get(key.id) as { hwid_hash: string | null };
    expect(row.hwid_hash).toBeNull();
  });
});

describe("gate failures", () => {
  test("missing proof header is BAD_REQUEST", async () => {
    const key = await env.createKey();
    const input = await makeSignedInput("POST", "/check_key", { key: key.plaintext, script_id: SCRIPT_ID, lv: "1.0.0" }, { ip: "198.51.100.7" });
    delete input.headers["x-proof"];
    const res = await dispatch(buildRoutes(), env.ctx, env.config, input);
    expect((await envelopeOf(res)).code).toBe("BAD_REQUEST");
  });

  test("tampered proof is BAD_REQUEST", async () => {
    const key = await env.createKey();
    const input = await makeSignedInput("POST", "/check_key", { key: key.plaintext, script_id: SCRIPT_ID, lv: "1.0.0" }, { ip: "198.51.100.8" });
    input.headers["x-proof"] = input.headers["x-proof"].slice(0, -2) + "aa";
    const res = await dispatch(buildRoutes(), env.ctx, env.config, input);
    expect((await envelopeOf(res)).code).toBe("BAD_REQUEST");
  });

  test("proof is path-bound: a proof computed for another path fails", async () => {
    const key = await env.createKey();
    const input = await makeSignedInput("POST", "/other-path", { key: key.plaintext, script_id: SCRIPT_ID, lv: "1.0.0" }, { ip: "198.51.100.9" });
    input.path = "/check_key";
    const res = await dispatch(buildRoutes(), env.ctx, env.config, input);
    expect((await envelopeOf(res)).code).toBe("BAD_REQUEST");
  });

  test("stale and future timestamps are rejected", async () => {
    const key = await env.createKey();
    const stale = await post({ key: key.plaintext, script_id: SCRIPT_ID, lv: "1.0.0" }, { ts: Date.now() / 1000 - 120, ip: "198.51.100.10" });
    expect((await envelopeOf(stale)).code).toBe("BAD_REQUEST");
    const future = await post({ key: key.plaintext, script_id: SCRIPT_ID, lv: "1.0.0" }, { ts: Date.now() / 1000 + 120, ip: "198.51.100.11" });
    expect((await envelopeOf(future)).code).toBe("BAD_REQUEST");
  });

  test("nonce reuse is rejected (replay)", async () => {
    const key = await env.createKey();
    const fixedNonceInput = await makeSignedInput("POST", "/check_key", { key: key.plaintext, script_id: SCRIPT_ID, lv: "1.0.0" }, { ip: "198.51.100.12" });
    const first = await dispatch(buildRoutes(), env.ctx, env.config, fixedNonceInput);
    expect((await envelopeOf(first)).code).toBe("KEY_VALID");
    const replay = await dispatch(buildRoutes(), env.ctx, env.config, { ...fixedNonceInput, bodyBytes: fixedNonceInput.bodyBytes });
    expect((await envelopeOf(replay)).code).toBe("BAD_REQUEST");
  });

  test("nonce must be 16 bytes", async () => {
    const key = await env.createKey();
    const short = await post({ key: key.plaintext, script_id: SCRIPT_ID, lv: "1.0.0" }, { nonce: "AAAA", ip: "198.51.100.13" });
    expect((await envelopeOf(short)).code).toBe("BAD_REQUEST");
  });
});

describe("key outcomes", () => {
  test("unknown key is KEY_INVALID", async () => {
    const res = await post({ key: "YURI-AAAAA-BBBBB-CCCCC-DDDDD-EEEEE2", script_id: SCRIPT_ID, lv: "1.0.0" }, { ip: "198.51.100.20" });
    const envelope = await envelopeOf(res);
    expect(envelope.code).toBe("KEY_INVALID");
  });

  test("corrupted checksum is KEY_INVALID before any DB lookup", async () => {
    const key = await env.createKey();
    const corrupted = key.plaintext.slice(0, -1) + (key.plaintext.endsWith("A") ? "B" : "A");
    const res = await post({ key: corrupted, script_id: SCRIPT_ID, lv: "1.0.0" }, { ip: "198.51.100.21" });
    expect((await envelopeOf(res)).code).toBe("KEY_INVALID");
  });

  test("expired key is KEY_EXPIRED", async () => {
    const key = await env.createKey({ days: 1 });
    env.db.prepare("UPDATE keys SET expires_at = ? WHERE id = ?").run(Math.floor(Date.now() / 1000) - 10, key.id);
    const res = await post({ key: key.plaintext, script_id: SCRIPT_ID, lv: "1.0.0" }, { ip: "198.51.100.22" });
    expect((await envelopeOf(res)).code).toBe("KEY_EXPIRED");
  });

  test("revoked key is KEY_INVALID and blacklisted status is KEY_BLACKLISTED", async () => {
    const revoked = await env.createKey();
    env.db.prepare("UPDATE keys SET status = 'revoked' WHERE id = ?").run(revoked.id);
    const resRevoked = await post({ key: revoked.plaintext, script_id: SCRIPT_ID, lv: "1.0.0" }, { ip: "198.51.100.23" });
    expect((await envelopeOf(resRevoked)).code).toBe("KEY_INVALID");

    const blacklisted = await env.createKey();
    env.db.prepare("UPDATE keys SET status = 'blacklisted' WHERE id = ?").run(blacklisted.id);
    const resBlacklisted = await post({ key: blacklisted.plaintext, script_id: SCRIPT_ID, lv: "1.0.0" }, { ip: "198.51.100.24" });
    expect((await envelopeOf(resBlacklisted)).code).toBe("KEY_BLACKLISTED");
  });

  test("script not entitled is SCRIPT_NOT_ALLOWED", async () => {
    const key = await env.createKey();
    const res = await post({ key: key.plaintext, script_id: "4" .repeat(32), lv: "1.0.0" }, { ip: "198.51.100.25" });
    expect((await envelopeOf(res)).code).toBe("SCRIPT_NOT_ALLOWED");
  });

  test("outdated loader is UPDATE_REQUIRED", async () => {
    const key = await env.createKey();
    const res = await post({ key: key.plaintext, script_id: SCRIPT_ID, lv: "0.9.0" }, { ip: "198.51.100.26", headers: { "x-lv": "0.9.0" } });
    expect((await envelopeOf(res)).code).toBe("UPDATE_REQUIRED");
  });
});

describe("HWID binding", () => {
  test("second device gets HWID_MISMATCH and no rebind", async () => {
    const key = await env.createKey();
    const first = await post({ key: key.plaintext, script_id: SCRIPT_ID, lv: "1.0.0" }, { headers: { "Delta-User-Identifier": "device-one" }, ip: "198.51.100.30" });
    expect((await envelopeOf(first)).code).toBe("KEY_VALID");
    const second = await post({ key: key.plaintext, script_id: SCRIPT_ID, lv: "1.0.0" }, { headers: { "Delta-User-Identifier": "device-two" }, ip: "198.51.100.31" });
    expect((await envelopeOf(second)).code).toBe("HWID_MISMATCH");
    const row = env.db.prepare("SELECT hwid_hash FROM keys WHERE id = ?").get(key.id) as { hwid_hash: string };
    expect(row.hwid_hash).toBe(await hwidHashFor("device-one"));
    const events = env.db.prepare("SELECT type, detail FROM events WHERE key_id = ?").all(key.id) as { type: string; detail: string }[];
    expect(events.some((e) => e.type === "validate_fail" && e.detail === "hwid")).toBe(true);
  });

  test("blacklisted HWID is KEY_BLACKLISTED before binding", async () => {
    const key = await env.createKey();
    const hwidHash = await hwidHashFor("evil-device");
    env.db.prepare("INSERT INTO blacklist (id, kind, value_hash, reason, created_by, created_at) VALUES (?, 'hwid', ?, 'test', 'seed', ?)").run("bl-1", hwidHash, Math.floor(Date.now() / 1000));
    const res = await post({ key: key.plaintext, script_id: SCRIPT_ID, lv: "1.0.0" }, { headers: { "Delta-User-Identifier": "evil-device" }, ip: "198.51.100.32" });
    expect((await envelopeOf(res)).code).toBe("KEY_BLACKLISTED");
    const row = env.db.prepare("SELECT hwid_hash FROM keys WHERE id = ?").get(key.id) as { hwid_hash: string | null };
    expect(row.hwid_hash).toBeNull();
  });

  test("blacklisted IP is KEY_BLACKLISTED", async () => {
    const key = await env.createKey();
    const ip = "203.0.113.66";
    const ipHash = await (await import("../src/crypto")).sha256Hex(env.config.pepper + "|ip|" + ip);
    env.db.prepare("INSERT INTO blacklist (id, kind, value_hash, reason, created_by, created_at) VALUES (?, 'ip', ?, 'test', 'seed', ?)").run("bl-2", ipHash, Math.floor(Date.now() / 1000));
    const res = await post({ key: key.plaintext, script_id: SCRIPT_ID, lv: "1.0.0" }, { ip });
    expect((await envelopeOf(res)).code).toBe("KEY_BLACKLISTED");
  });
});

describe("rate limiting", () => {
  test("61st request within a minute from one IP is RATE_LIMITED", async () => {
    const key = await env.createKey();
    const ip = "203.0.113.77";
    let last: Response | null = null;
    for (let i = 0; i < 61; i++) {
      last = await post({ key: key.plaintext, script_id: SCRIPT_ID, lv: "1.0.0" }, { ip });
    }
    expect((await envelopeOf(last!)).code).toBe("RATE_LIMITED");
    expect(Number(last!.headers.get("retry-after"))).toBeGreaterThan(0);
    const other = await post({ key: key.plaintext, script_id: SCRIPT_ID, lv: "1.0.0" }, { ip: "203.0.113.78" });
    expect((await envelopeOf(other)).code).toBe("KEY_VALID");
  });

  test("five invalid keys lock the IP out", async () => {
    const ip = "203.0.113.88";
    for (let i = 0; i < 5; i++) {
      const res = await post({ key: "YURI-AAAAA-BBBBB-CCCCC-DDDDD-EEEEE2", script_id: SCRIPT_ID, lv: "1.0.0" }, { ip });
      expect((await envelopeOf(res)).code).toBe("KEY_INVALID");
    }
    const validKey = await env.createKey();
    const locked = await post({ key: validKey.plaintext, script_id: SCRIPT_ID, lv: "1.0.0" }, { ip });
    const envelope = await envelopeOf(locked);
    expect(envelope.code).toBe("RATE_LIMITED");
    const tamperEvents = env.db.prepare("SELECT type FROM events WHERE type = 'tamper'").all() as { type: string }[];
    expect(tamperEvents.length).toBeGreaterThan(0);
  });
});

describe("malformed input", () => {
  test("non-JSON body is BAD_REQUEST", async () => {
    const input = await makeSignedInput("POST", "/check_key", null, { bodyBytes: utf8("not json"), ip: "203.0.113.90" });
    const res = await dispatch(buildRoutes(), env.ctx, env.config, input);
    expect((await envelopeOf(res)).code).toBe("BAD_REQUEST");
  });

  test("missing or wrong-typed fields are BAD_REQUEST", async () => {
    const missing = await post({}, { ip: "203.0.113.91" });
    expect((await envelopeOf(missing)).code).toBe("BAD_REQUEST");
    const badScript = await post({ key: "YURI-AAAAA-BBBBB-CCCCC-DDDDD-EEEEE2", script_id: "short", lv: "1.0.0" }, { ip: "203.0.113.92" });
    expect((await envelopeOf(badScript)).code).toBe("BAD_REQUEST");
    const badKey = await post({ key: "x".repeat(200), script_id: SCRIPT_ID, lv: "1.0.0" }, { ip: "203.0.113.93" });
    expect((await envelopeOf(badKey)).code).toBe("BAD_REQUEST");
  });
});
