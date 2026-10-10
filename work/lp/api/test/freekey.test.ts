import { describe, expect, test } from "bun:test";
import { buildEnv, envelopeOf, makeSignedInput, SCRIPT_ID } from "./helpers";
import { dispatch, buildRoutes } from "../src/router";
import { b64urlDecode, canonicalJson } from "../src/contracts";
import { utf8 } from "../src/crypto";

// §22 free-flow tests: the spec rows of doc.md §14 are the external oracle —
// every §14.3 verification clause and §14.5 anti-bypass clause maps to a test
// below. The happy-path key is then validated through the REAL M1 check_key
// handler (cross-module).

interface StartData {
  token: string;
  step: number;
  total_steps: number;
  url: string;
  min_seconds: number;
}

function secretFromUrl(url: string): string {
  const m = /[?&]s=([^&]+)/.exec(url);
  if (!m) throw new Error("no secret in url: " + url);
  return m[1];
}

async function runFree(env: Awaited<ReturnType<typeof buildEnv>>, method: string, path: string, body: Record<string, unknown> | null, ip = "203.0.113.10"): Promise<{ code: string; data: Record<string, unknown> | null; res: Response }> {
  const input = await makeSignedInput(method, path, body, { ip });
  const res = await dispatch(buildRoutes(), env.ctx, env.config, input);
  const env0 = await envelopeOf(res);
  return { code: env0.code, data: env0.data, res };
}

describe("free flow happy path (doc §14.1-14.4)", () => {
  test("start → step 1 (after min time) → step 2 → claim issues a KEY_VALID free key", async () => {
    const env = await buildEnv();
    const start = await runFree(env, "POST", "/free/start", { slug: "yuri" });
    expect(start.code).toBe("KEY_VALID");
    const s1 = start.data as unknown as StartData;
    expect(s1.step).toBe(1);
    expect(s1.total_steps).toBe(2);
    expect(s1.url).toContain("s=");
    expect(s1.min_seconds).toBe(1);

    // §14.3: minimum time elapsed since step start (checkpoint 1 has min_seconds=1)
    await new Promise((r) => setTimeout(r, 1100));
    const secret1 = secretFromUrl(s1.url);
    const step1 = await runFree(env, "POST", "/free/step", { token: s1.token, completion_token: secret1 });
    expect(step1.code).toBe("KEY_VALID");
    const s2 = step1.data as unknown as StartData;
    expect(s2.step).toBe(2);
    expect(s2.url).toContain("a="); // {{ATTEMPT}} substituted

    const secret2 = secretFromUrl(s2.url);
    const step2 = await runFree(env, "POST", "/free/step", { token: s2.token, completion_token: secret2 });
    expect(step2.code).toBe("KEY_VALID");
    expect((step2.data as unknown as { done: boolean }).done).toBe(true);

    const claim = await runFree(env, "POST", "/free/claim", { token: (step2.data as unknown as { token: string }).token });
    expect(claim.code).toBe("KEY_VALID");
    const key = (claim.data as unknown as { key: string; expires_at: number; tier: string });
    expect(key.tier).toBe("free");
    expect(key.expires_at).toBeGreaterThan(Math.floor(Date.now() / 1000));
    expect(key.key).toMatch(/^YURI-/);

    // cross-module: the claimed key validates through the REAL check_key handler
    const checkInput = await makeSignedInput("POST", "/check_key", { key: key.key, script_id: SCRIPT_ID, lv: "1.0.0" });
    const check = await dispatch(buildRoutes(), env.ctx, env.config, checkInput);
    const checkEnv = await envelopeOf(check);
    expect(checkEnv.code).toBe("KEY_VALID");

    // entitlement rows exist for the project script
    const keyId = await env.ctx.db.first<{ id: string }>("SELECT id FROM keys WHERE note = 'free flow'", []);
    const ks = await env.ctx.db.all<{ script_id: string }>("SELECT script_id FROM key_scripts WHERE key_id = ?", [keyId!.id]);
    expect(ks.map((k) => k.script_id)).toContain(SCRIPT_ID);

    // audit entry per D-M9-9
    const audit = await env.ctx.db.first<{ action: string }>("SELECT action FROM audit_log WHERE target = ?", [keyId!.id]);
    expect(audit?.action).toBe("create_key");
  });

  test("response envelope is x-sig signed like every other endpoint (§5.4)", async () => {
    const env = await buildEnv();
    const start = await runFree(env, "POST", "/free/start", { slug: "yuri" });
    const sig = start.res.headers.get("x-sig");
    const ts = start.res.headers.get("x-ts");
    expect(sig).not.toBeNull();
    expect(ts).not.toBeNull();
    const payload = utf8(`KEY_VALID|The provided key is valid.|${canonicalJson(start.data)}|${ts}`);
    expect(await env.verifier.verify(payload, b64urlDecode(sig!))).toBe(true);
  });
});

describe("free flow bypass attempts (doc §22)", () => {
  test("replay: an already-used step token is rejected", async () => {
    const env = await buildEnv();
    const start = await runFree(env, "POST", "/free/start", { slug: "yuri" });
    const s1 = start.data as unknown as StartData;
    await new Promise((r) => setTimeout(r, 1100));
    const secret1 = secretFromUrl(s1.url);
    const step1 = await runFree(env, "POST", "/free/step", { token: s1.token, completion_token: secret1 });
    expect(step1.code).toBe("KEY_VALID");
    // replay the OLD token (already rotated)
    const replay = await runFree(env, "POST", "/free/step", { token: s1.token, completion_token: secret1 });
    expect(replay.code).toBe("BAD_REQUEST");
    const ev = await env.ctx.db.first<{ type: string }>("SELECT type FROM events WHERE type = 'free_bypass' AND detail = 'step-unknown-token'", []);
    expect(ev).not.toBeNull();
  });

  test("skipped steps: claim before completing steps is rejected", async () => {
    const env = await buildEnv();
    const start = await runFree(env, "POST", "/free/start", { slug: "yuri" });
    const claim = await runFree(env, "POST", "/free/claim", { token: (start.data as unknown as StartData).token });
    expect(claim.code).toBe("BAD_REQUEST");
    const ev = await env.ctx.db.first<{ detail: string }>("SELECT detail FROM events WHERE detail = 'claim-uncompleted-steps'", []);
    expect(ev).not.toBeNull();
  });

  test("fast completion: step before min_seconds elapsed is rejected and logged", async () => {
    const env = await buildEnv();
    const start = await runFree(env, "POST", "/free/start", { slug: "yuri" });
    const s1 = start.data as unknown as StartData;
    expect(s1.min_seconds).toBe(1);
    const secret1 = secretFromUrl(s1.url);
    const fast = await runFree(env, "POST", "/free/step", { token: s1.token, completion_token: secret1 });
    expect(fast.code).toBe("BAD_REQUEST");
    const ev = await env.ctx.db.first<{ detail: string }>("SELECT detail FROM events WHERE detail LIKE 'step-too-fast:%'", []);
    expect(ev).not.toBeNull();
  });

  test("bad step secret (resolver-bypass user presenting garbage) is rejected", async () => {
    const env = await buildEnv();
    const start = await runFree(env, "POST", "/free/start", { slug: "yuri" });
    const s1 = start.data as unknown as StartData;
    await new Promise((r) => setTimeout(r, 1100));
    const bad = await runFree(env, "POST", "/free/step", { token: s1.token, completion_token: "AAAA" + secretFromUrl(s1.url) });
    expect(bad.code).toBe("BAD_REQUEST");
    const ev = await env.ctx.db.first<{ detail: string }>("SELECT detail FROM events WHERE detail LIKE 'step-bad-secret:%'", []);
    expect(ev).not.toBeNull();
  });

  test("cooldown: same fingerprint cannot start a second attempt inside the window", async () => {
    const env = await buildEnv();
    const first = await runFree(env, "POST", "/free/start", { slug: "yuri" });
    expect(first.code).toBe("KEY_VALID");
    const second = await runFree(env, "POST", "/free/start", { slug: "yuri" });
    expect(second.code).toBe("RATE_LIMITED");
    expect(Number(second.res.headers.get("retry-after"))).toBeGreaterThan(0);
  });

  test("multi-account: same IP with a different HWID gets a distinct fingerprint and a new attempt", async () => {
    const env = await buildEnv();
    const a = await runFree(env, "POST", "/free/start", { slug: "yuri", hwid: "HWID-AAA" });
    expect(a.code).toBe("KEY_VALID");
    const b = await runFree(env, "POST", "/free/start", { slug: "yuri", hwid: "HWID-BBB" });
    expect(b.code).toBe("KEY_VALID");
    // but the SAME hwid is still blocked by the fingerprint cooldown
    const c = await runFree(env, "POST", "/free/start", { slug: "yuri", hwid: "HWID-AAA" });
    expect(c.code).toBe("RATE_LIMITED");
  });

  test("binding: switching IP mid-flow fails the fingerprint check", async () => {
    const env = await buildEnv();
    const start = await runFree(env, "POST", "/free/start", { slug: "yuri" });
    const s1 = start.data as unknown as StartData;
    await new Promise((r) => setTimeout(r, 1100));
    const secret1 = secretFromUrl(s1.url);
    const moved = await runFree(env, "POST", "/free/step", { token: s1.token, completion_token: secret1 }, "198.51.100.77");
    expect(moved.code).toBe("BAD_REQUEST");
    const ev = await env.ctx.db.first<{ detail: string }>("SELECT detail FROM events WHERE detail = 'step-fingerprint-mismatch'", []);
    expect(ev).not.toBeNull();
  });

  test("double claim is rejected", async () => {
    const env = await buildEnv();
    const start = await runFree(env, "POST", "/free/start", { slug: "yuri" });
    const s1 = start.data as unknown as StartData;
    await new Promise((r) => setTimeout(r, 1100));
    const step1 = await runFree(env, "POST", "/free/step", { token: s1.token, completion_token: secretFromUrl(s1.url) });
    const s2 = step1.data as unknown as StartData;
    const step2 = await runFree(env, "POST", "/free/step", { token: s2.token, completion_token: secretFromUrl(s2.url) });
    const claimToken = (step2.data as unknown as { token: string }).token;
    const claim1 = await runFree(env, "POST", "/free/claim", { token: claimToken });
    expect(claim1.code).toBe("KEY_VALID");
    const claim2 = await runFree(env, "POST", "/free/claim", { token: claimToken });
    expect(claim2.code).toBe("BAD_REQUEST");
  });

  test("start rate limit: 6th start from the same IP within a minute is throttled (distinct hwids dodge the fingerprint cooldown)", async () => {
    const env = await buildEnv();
    for (let i = 0; i < 5; i++) {
      const r = await runFree(env, "POST", "/free/start", { slug: "yuri", hwid: "hw-" + i }, "203.0.113.10");
      expect(r.code).toBe("KEY_VALID");
    }
    const sixth = await runFree(env, "POST", "/free/start", { slug: "yuri", hwid: "hw-6" }, "203.0.113.10");
    expect(sixth.code).toBe("RATE_LIMITED");
  });

  test("unknown slug and no-checkpoint project fail generically (§8: generic user messages)", async () => {
    const env = await buildEnv();
    const badSlug = await runFree(env, "POST", "/free/start", { slug: "nope" });
    expect(badSlug.code).toBe("BAD_REQUEST");
    expect(badSlug.res.status).toBe(200);
  });
});

describe("checkpoints config validation (D-M9-1)", () => {
  test("malformed checkpoint config fails safe", async () => {
    const env = await buildEnv();
    await env.ctx.db.run("UPDATE checkpoints SET config = '{not-json' WHERE id = 'cp1'", []);
    const start = await runFree(env, "POST", "/free/start", { slug: "yuri" });
    expect(start.code).toBe("SERVER_ERROR");
  });

  test("timing-mode provider link (verify: timing) accepts any completion evidence but still enforces min time", async () => {
    const env = await buildEnv();
    await env.ctx.db.run("UPDATE checkpoints SET config = ? WHERE id = 'cp1'", [JSON.stringify({ url: "https://provider.example/lv/123", min_seconds: 1, verify: "timing" })]);
    const start = await runFree(env, "POST", "/free/start", { slug: "yuri" });
    const s1 = start.data as unknown as StartData;
    expect(s1.url).toBe("https://provider.example/lv/123");
    await new Promise((r) => setTimeout(r, 1100));
    const step1 = await runFree(env, "POST", "/free/step", { token: s1.token, completion_token: "whatever" });
    expect(step1.code).toBe("KEY_VALID");
  });
});

describe("direct handler reachability (routes wiring)", () => {
  test("router exposes /free/start, /free/step, /free/claim", () => {
    const routes = buildRoutes();
    expect(routes.some((r) => r.method === "POST" && r.pattern === "/free/start")).toBe(true);
    expect(routes.some((r) => r.method === "POST" && r.pattern === "/free/step")).toBe(true);
    expect(routes.some((r) => r.method === "POST" && r.pattern === "/free/claim")).toBe(true);
  });
});
