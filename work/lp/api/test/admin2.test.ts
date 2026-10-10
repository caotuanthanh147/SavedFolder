import { beforeAll, describe, expect, test } from "bun:test";
import {
  ADMIN_ID,
  ADMIN_TOKEN,
  
  PEPPER,
  PROJECT_ID,
  RESELLER_TOKEN,
  SCRIPT_ID,
  TestEnv,
  buildEnv,
  makeSignedInput,
  envelopeOf,
} from "./helpers";
import { buildRoutes, dispatch } from "../src/router";
import { b64urlDecode, b64urlEncode } from "../src/contracts";
import { randomBytes, sha256Hex } from "../src/crypto";
import { projectHwidSalt, hashHwid } from "../src/keys";

let env: TestEnv;

beforeAll(async () => {
  env = await buildEnv();
});

async function adminPost(path: string, body: Record<string, unknown>, token: string = ADMIN_TOKEN, method = "POST"): Promise<{ status: number; body: Record<string, unknown> }> {
  const input = await makeSignedInput(method, path, body, { headers: { authorization: `Bearer ${token}` } });
  const res = await dispatch(buildRoutes(), env.ctx, env.config, input);
  let parsed: Record<string, unknown> = {};
  try {
    parsed = (await res.json()) as Record<string, unknown>;
  } catch {
    parsed = {};
  }
  return { status: res.status, body: parsed };
}

describe("admin token Q2 format (adm_<id>.<secret>)", () => {
  test("valid token authenticates", async () => {
    const r = await adminPost("/admin/nodes", { hostname: "auth4.example.net" });
    expect(r.status).toBe(201);
  });

  test("wrong secret → 401", async () => {
    const wrong = `adm_${ADMIN_ID}.${b64urlEncode(randomBytes(32))}`;
    const r = await adminPost("/admin/nodes", { hostname: "auth9.example.net" }, wrong);
    expect(r.status).toBe(401);
  });

  test("old whole-token format → 401 (clean break, no fallback)", async () => {
    const r = await adminPost("/admin/nodes", { hostname: "auth9.example.net" }, "owner-secret-token-1");
    expect(r.status).toBe(401);
  });

  test("unknown admin id → 401", async () => {
    const unknown = `adm_${"f".repeat(32)}.${b64urlEncode(randomBytes(32))}`;
    const r = await adminPost("/admin/nodes", { hostname: "auth9.example.net" }, unknown);
    expect(r.status).toBe(401);
  });

  test("malformed token (no dot) → 401", async () => {
    const r = await adminPost("/admin/nodes", { hostname: "auth9.example.net" }, "adm_notatoken");
    expect(r.status).toBe(401);
  });

  test("reseller token valid but forbidden on node admin", async () => {
    const r = await adminPost("/admin/nodes", { hostname: "auth9.example.net" }, RESELLER_TOKEN);
    expect(r.status).toBe(403);
  });

  test("stored hash is exactly sha256(secret bytes), no pepper", async () => {
    const secretPart = ADMIN_TOKEN.split(".")[1];
    const secretBytes = b64urlDecode(secretPart);
    const hash = await sha256Hex(secretBytes);
    const row = await env.ctx.db.first<{ api_token_hash: string }>("SELECT api_token_hash FROM admins WHERE id = ?", [ADMIN_ID]);
    expect(row!.api_token_hash).toBe(hash);
  });
});

describe("POST /admin/nodes", () => {
  test("add new node → appears in /sync list", async () => {
    const r = await adminPost("/admin/nodes", { hostname: "auth3.example.net", region: "ap" });
    expect(r.status).toBe(201);
    const sync = await makeSignedInput("GET", "/sync", null);
    const res = await dispatch(buildRoutes(), env.ctx, env.config, sync);
    const data = (await res.json()) as { nodes: string[] };
    expect(data.nodes).toContain("https://auth3.example.net");
  });

  test("re-adding existing node reactivates it", async () => {
    await adminPost("/admin/nodes", { hostname: "auth3.example.net", action: "disable" });
    const r = await adminPost("/admin/nodes", { hostname: "auth3.example.net" });
    expect(r.status).toBe(200);
    expect(r.body.reactivated).toBe(true);
  });

  test("disable removes from /sync", async () => {
    await adminPost("/admin/nodes", { hostname: "auth3.example.net" });
    await adminPost("/admin/nodes", { hostname: "auth3.example.net", action: "disable" });
    const sync = await makeSignedInput("GET", "/sync", null);
    const res = await dispatch(buildRoutes(), env.ctx, env.config, sync);
    const data = (await res.json()) as { nodes: string[] };
    expect(data.nodes).not.toContain("https://auth3.example.net");
  });

  test("invalid hostname → 400", async () => {
    const r = await adminPost("/admin/nodes", { hostname: "not a hostname" });
    expect(r.status).toBe(400);
  });

  test("disable unknown hostname → 404", async () => {
    const r = await adminPost("/admin/nodes", { hostname: "nope.example.net", action: "disable" });
    expect(r.status).toBe(404);
  });
});

describe("POST /admin/protocol-versions", () => {
  test("register new version then retire it", async () => {
    const reg = await adminPost("/admin/protocol-versions", { version: "3", handler: "auth", min_loader: "1.1.0" });
    expect(reg.status).toBe(201);
    const status = await makeSignedInput("GET", "/status", null);
    const res = await dispatch(buildRoutes(), env.ctx, env.config, status);
    const data = (await res.json()) as { versions: Record<string, string> };
    expect(data.versions["3"]).toBe("auth");
    const retire = await adminPost("/admin/protocol-versions", { version: "3", action: "retire" });
    expect(retire.status).toBe(200);
    const res2 = await dispatch(buildRoutes(), env.ctx, env.config, await makeSignedInput("GET", "/status", null));
    const data2 = (await res2.json()) as { versions: Record<string, string> };
    expect(data2.versions["3"]).toBeUndefined();
  });

  test("re-register updates handler (upsert)", async () => {
    await adminPost("/admin/protocol-versions", { version: "9", handler: "auth", min_loader: "1.0.0" });
    const r = await adminPost("/admin/protocol-versions", { version: "9", handler: "check_key", min_loader: "1.0.0" });
    expect(r.status).toBe(201);
    const row = await env.ctx.db.first<{ handler: string; active: number }>("SELECT handler, active FROM protocol_versions WHERE version = '9'", []);
    expect(row!.handler).toBe("check_key");
    expect(row!.active).toBe(1);
  });

  test("retire unknown → 404; bad fields → 400", async () => {
    expect((await adminPost("/admin/protocol-versions", { version: "nope", action: "retire" })).status).toBe(404);
    expect((await adminPost("/admin/protocol-versions", { version: "10", handler: "bad handler!" })).status).toBe(400);
  });
});

describe("POST /admin/scripts/:id/versions + activate", () => {
  test("upload version 2, activate, auth init follows active version", async () => {
    env.blobs.put("bundle/v2", new TextEncoder().encode("-- v2 bundle"));
    const up = await adminPost(`/admin/scripts/${SCRIPT_ID}/versions`, {
      blob_ref: "bundle/v2",
      build_hash: "cd".repeat(32),
      init_build: "init-b2",
      notes: "second build",
      activate: true,
    });
    expect(up.status).toBe(201);
    expect(up.body.version).toBe(2);
    const script = await env.ctx.db.first<{ active_version: number }>("SELECT active_version FROM scripts WHERE id = ?", [SCRIPT_ID]);
    expect(script!.active_version).toBe(2);

    const rollback = await adminPost(`/admin/scripts/${SCRIPT_ID}/activate`, { version: 1 });
    expect(rollback.status).toBe(200);
    const script2 = await env.ctx.db.first<{ active_version: number }>("SELECT active_version FROM scripts WHERE id = ?", [SCRIPT_ID]);
    expect(script2!.active_version).toBe(1);
  });

  test("activate unknown version → 404", async () => {
    const r = await adminPost(`/admin/scripts/${SCRIPT_ID}/activate`, { version: 99 });
    expect(r.status).toBe(404);
  });

  test("bad build_hash → 400", async () => {
    const r = await adminPost(`/admin/scripts/${SCRIPT_ID}/versions`, {
      blob_ref: "x", build_hash: "nothex", init_build: "init-b3",
    });
    expect(r.status).toBe(400);
  });
});

describe("POST /admin/blacklist", () => {
  test("blacklist an ip → check_key denied with KEY_BLACKLISTED", async () => {
    const created = await env.createKey({});
    const r = await adminPost("/admin/blacklist", { kind: "ip", value: "198.51.100.77", reason: "abuse" });
    expect(r.status).toBe(201);
    const input = await makeSignedInput("POST", "/check_key", {
      key: created.plaintext, script_id: SCRIPT_ID, lv: "1.0.0",
    }, { ip: "198.51.100.77" });
    const res = await dispatch(buildRoutes(), env.ctx, env.config, input);
    expect((await envelopeOf(res)).code).toBe("KEY_BLACKLISTED");
  });

  test("blacklist a hwid with project salt → auth init denied", async () => {
    const salt = await projectHwidSalt(PEPPER, PROJECT_ID);
    expect(await hashHwid("SUSPECT-HWID", salt)).toBeTruthy();
    const r = await adminPost("/admin/blacklist", { kind: "hwid", value: "SUSPECT-HWID", project_id: PROJECT_ID });
    expect(r.status).toBe(201);
    const row = await env.ctx.db.first<{ value_hash: string }>("SELECT value_hash FROM blacklist WHERE id = ?", [r.body.id as string]);
    expect(row!.value_hash).toBe(await hashHwid("SUSPECT-HWID", salt));
  });

  test("duplicate entry is idempotent", async () => {
    const first = await adminPost("/admin/blacklist", { kind: "ip", value: "198.51.100.99" });
    const second = await adminPost("/admin/blacklist", { kind: "ip", value: "198.51.100.99" });
    expect(second.body.already).toBe(true);
    expect(second.body.id).toBe(first.body.id);
  });

  test("hwid without project_id → 400; unknown kind → 400", async () => {
    expect((await adminPost("/admin/blacklist", { kind: "hwid", value: "X" })).status).toBe(400);
    expect((await adminPost("/admin/blacklist", { kind: "email", value: "x@y" })).status).toBe(400);
  });
});

describe("GET /admin/analytics/overview", () => {
  test("counts keys/sessions/events in 24h window", async () => {
    const input = await makeSignedInput("GET", "/admin/analytics/overview", null, {
      headers: { authorization: `Bearer ${ADMIN_TOKEN}` },
    });
    const res = await dispatch(buildRoutes(), env.ctx, env.config, input);
    const data = (await res.json()) as Record<string, number | string>;
    expect(data.window).toBe("24h");
    expect(data.keys_active).toBeGreaterThanOrEqual(1);
    expect(data.sessions_24h).toBeGreaterThanOrEqual(0);
    expect(data.validate_fail_24h).toBeGreaterThanOrEqual(0);
  });

  test("unauthenticated → 401", async () => {
    const input = await makeSignedInput("GET", "/admin/analytics/overview", null);
    const res = await dispatch(buildRoutes(), env.ctx, env.config, input);
    expect(res.status).toBe(401);
  });
});

describe("audit coverage for new endpoints", () => {
  test("every new mutation writes an audit entry", async () => {
    await adminPost("/admin/nodes", { hostname: "auth-audit.example.net" });
    await adminPost("/admin/protocol-versions", { version: "8", handler: "auth" });
    await adminPost(`/admin/scripts/${SCRIPT_ID}/versions`, { blob_ref: "b", build_hash: "ef".repeat(32), init_build: "i" });
    await adminPost("/admin/blacklist", { kind: "discord", value: "999" });
    const input = await makeSignedInput("GET", "/admin/audit", null, { headers: { authorization: `Bearer ${ADMIN_TOKEN}` } });
    const res = await dispatch(buildRoutes(), env.ctx, env.config, input);
    const data = (await res.json()) as { entries: { action: string; actor_id: string }[] };
    const actions = data.entries.map((e) => e.action);
    expect(actions).toContain("admin.node.add");
    expect(actions).toContain("admin.protocol.register");
    expect(actions).toContain("admin.script.version");
    expect(actions).toContain("admin.blacklist.add");
    expect(data.entries.every((e) => e.actor_id === ADMIN_ID)).toBe(true);
  });
});
