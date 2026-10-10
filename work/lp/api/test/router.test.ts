import { beforeAll, describe, expect, test } from "bun:test";
import { buildEnv, makeSignedInput, TestEnv } from "./helpers";
import { buildRoutes, dispatch } from "../src/router";
import { MAX_BODY_BYTES } from "../src/contracts";

let env: TestEnv;

beforeAll(async () => {
  env = await buildEnv();
});

describe("GET /sync", () => {
  test("returns server time, node URLs, and the edge colo", async () => {
    const input = await makeSignedInput("GET", "/sync", null, { ip: "192.0.2.10" });
    const res = await dispatch(buildRoutes(), env.ctx, env.config, input);
    expect(res.status).toBe(200);
    const body = (await res.json()) as { st: number; nodes: string[]; colo: string };
    expect(body.st).toBeGreaterThan(0);
    expect(body.nodes).toEqual(["https://auth1.example.net", "https://auth2.example.net"]);
    expect(body.colo).toBe("TST");
  });
});

describe("GET /status", () => {
  test("reports active flag, protocol versions, and node hostnames", async () => {
    const input = await makeSignedInput("GET", "/status", null, { ip: "192.0.2.11" });
    const res = await dispatch(buildRoutes(), env.ctx, env.config, input);
    expect(res.status).toBe(200);
    const body = (await res.json()) as { active: boolean; versions: Record<string, string>; nodes: string[] };
    expect(body.active).toBe(true);
    expect(body.versions).toEqual({ "1": "check_key", "2": "auth" });
    expect(body.nodes).toEqual(["auth1.example.net", "auth2.example.net"]);
  });
});

describe("routing behavior", () => {
  test("unknown paths are 404 and wrong methods are 405", async () => {
    const unknown = await dispatch(buildRoutes(), env.ctx, env.config, await makeSignedInput("GET", "/nope", null, { ip: "192.0.2.12" }));
    expect(unknown.status).toBe(404);
    const wrongMethod = await dispatch(buildRoutes(), env.ctx, env.config, await makeSignedInput("PATCH", "/check_key", null, { ip: "192.0.2.13" }));
    expect(wrongMethod.status).toBe(405);
  });

  test("oversized bodies are rejected before handlers run", async () => {
    const big = new Uint8Array(MAX_BODY_BYTES + 1);
    const input = await makeSignedInput("POST", "/check_key", null, { bodyBytes: big, ip: "192.0.2.14" });
    const res = await dispatch(buildRoutes(), env.ctx, env.config, input);
    expect(res.status).toBe(200);
    const body = (await res.json()) as { code: string };
    expect(body.code).toBe("BAD_REQUEST");
  });
});
