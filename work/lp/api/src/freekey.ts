import { b64urlEncode, makeEnvelope } from "./contracts";
import { hmacSha256, randomBytes, randomId, sha256Hex, utf8 } from "./crypto";
import { ApiConfig, AppContext, RequestInput, headerValue, readJsonBody, recordEvent, signedResponse } from "./flow";
import { generateKey, hashKey, hashHwid, projectHwidSalt } from "./keys";

// Module M9 — free-key flow (doc.md §14). Endpoints are public page-driven
// (no SDK x-proof per D-M9-5); protections are: per-IP rate limits, rotating
// single-use attempt tokens (D-M9-2), stateless per-step secrets (D-M9-3),
// server-side minimum time per step (D-M9-7), one attempt per fingerprint per
// cooldown window (D-M9-8), and bypass monitoring events (D-M9-10).

interface CheckpointRow {
  id: string;
  project_id: string;
  position: number;
  provider: string;
  config: string;
}

interface CheckpointConfig {
  url: string;
  min_seconds: number;
  cooldown_seconds?: number;
  verify: "secret" | "timing";
  postback_secret?: string;
}

interface AttemptRow {
  id: string;
  project_id: string;
  fingerprint: string;
  step: number;
  token_hash: string;
  started_at: number;
  step_started_at: number;
  completed_at: number | null;
}

interface ProjectRow {
  id: string;
  name: string;
  slug: string;
}

const DEFAULT_MIN_SECONDS = 30;
const DEFAULT_COOLDOWN_SEC = 6 * 3600;
const VERIFY_MODES = ["secret", "timing"] as const;

export function parseCheckpointConfig(raw: string): CheckpointConfig | null {
  let parsed: unknown;
  try {
    parsed = JSON.parse(raw);
  } catch {
    return null;
  }
  if (typeof parsed !== "object" || parsed === null) return null;
  const c = parsed as Record<string, unknown>;
  if (typeof c.url !== "string" || c.url.length === 0 || c.url.length > 2048) return null;
  if (c.min_seconds !== undefined && (typeof c.min_seconds !== "number" || !Number.isInteger(c.min_seconds) || c.min_seconds < 0 || c.min_seconds > 3600)) return null;
  if (c.cooldown_seconds !== undefined && (typeof c.cooldown_seconds !== "number" || !Number.isInteger(c.cooldown_seconds) || c.cooldown_seconds < 60 || c.cooldown_seconds > 30 * 86400)) return null;
  if (c.verify !== undefined && !(VERIFY_MODES as readonly string[]).includes(c.verify as string)) return null;
  if (c.postback_secret !== undefined && (typeof c.postback_secret !== "string" || c.postback_secret.length < 16 || c.postback_secret.length > 256)) return null;
  return {
    url: c.url,
    min_seconds: typeof c.min_seconds === "number" ? c.min_seconds : DEFAULT_MIN_SECONDS,
    cooldown_seconds: typeof c.cooldown_seconds === "number" ? c.cooldown_seconds : undefined,
    verify: c.verify === "timing" ? "timing" : "secret",
    postback_secret: typeof c.postback_secret === "string" ? c.postback_secret : undefined,
  };
}

async function macLabel(secret: Uint8Array, attemptId: string, step: number): Promise<string> {
  return b64urlEncode(await hmacSha256(secret, utf8(`free-step|${attemptId}|${step}`)));
}

async function stepSecret(config: ApiConfig, attemptId: string, step: number): Promise<string> {
  return macLabel(config.freeSecret, attemptId, step);
}

function constantTimeStringEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let same = true;
  for (let i = 0; i < a.length; i++) {
    if (a.charCodeAt(i) !== b.charCodeAt(i)) same = false;
  }
  return same;
}

async function fingerprintFor(config: ApiConfig, input: RequestInput, bodyHwid: string | null): Promise<string> {
  let hwidHash = "";
  const executorHeader = config.executorHwidHeaders
    .map((h) => headerValue(input.headers, h))
    .find((v): v is string => v !== null && v.length > 0 && v.length <= 256);
  const hwid = executorHeader ?? bodyHwid;
  if (hwid !== null && hwid.length > 0) {
    const salt = await projectHwidSalt(config.pepper, "free-flow");
    hwidHash = await hashHwid(hwid, salt);
  }
  const ipHash = await sha256Hex(config.pepper + "|ip|" + input.ip);
  return sha256Hex(config.pepper + "|fp|" + hwidHash + "|" + ipHash);
}

function ok(ctx: AppContext, config: ApiConfig, data: Record<string, unknown>): Promise<Response> {
  return signedResponse(makeEnvelope("KEY_VALID", data), config.signer, ctx.nowSec);
}

function reject(ctx: AppContext, config: ApiConfig, code: "BAD_REQUEST" | "RATE_LIMITED" | "SERVER_ERROR", retryAfterSec = 0): Promise<Response> {
  const extra: Record<string, string> = code === "RATE_LIMITED" ? { "retry-after": String(Math.max(1, retryAfterSec)) } : {};
  return signedResponse(makeEnvelope(code, null), config.signer, ctx.nowSec, extra);
}

async function ipGate(ctx: AppContext, config: ApiConfig, input: RequestInput): Promise<number> {
  const ipHash = await sha256Hex(config.pepper + "|ip|" + input.ip);
  const decision = await ctx.limiter.hit(`free:req:${ipHash}`, config.free.requestsPerIpPerMin, 60);
  return decision.ok ? 0 : decision.retryAfterSec;
}

function readBodyHwid(body: Record<string, unknown> | null): string | null {
  return body !== null && typeof body.hwid === "string" && body.hwid.length > 0 && body.hwid.length <= 256 ? body.hwid : null;
}

function renderUrl(url: string, secret: string, attemptId: string): string {
  return url.replaceAll("{{SECRET}}", secret).replaceAll("{{ATTEMPT}}", attemptId);
}

// /free/start — body: { slug: string, hwid?: string }
export async function handleFreeStart(ctx: AppContext, config: ApiConfig, input: RequestInput): Promise<Response> {
  const gate = await ipGate(ctx, config, input);
  if (gate > 0) return reject(ctx, config, "RATE_LIMITED", gate);
  const body = readJsonBody(input);
  if (!body || typeof body.slug !== "string" || body.slug.length === 0 || body.slug.length > 64) {
    return reject(ctx, config, "BAD_REQUEST");
  }
  const bodyHwid = readBodyHwid(body);
  if (bodyHwid !== null) {
    await recordEvent(ctx, null, "free_flow", "start-hwid-body");
  }

  const ipHash = await sha256Hex(config.pepper + "|ip|" + input.ip);
  const startLimited = await ctx.limiter.hit(`free:start:${ipHash}`, config.free.startsPerIpPerMin, 60);
  if (!startLimited.ok) return reject(ctx, config, "RATE_LIMITED", startLimited.retryAfterSec);

  const project = await ctx.db.first<ProjectRow>("SELECT id, name, slug FROM projects WHERE slug = ?", [body.slug]);
  if (!project) {
    await recordEvent(ctx, null, "free_flow", "start-unknown-slug");
    return reject(ctx, config, "BAD_REQUEST");
  }

  const checkpoints = await ctx.db.all<CheckpointRow>(
    "SELECT id, project_id, position, provider, config FROM checkpoints WHERE project_id = ? ORDER BY position ASC",
    [project.id],
  );
  if (checkpoints.length === 0) {
    await recordEvent(ctx, null, "free_flow", "start-no-checkpoints");
    return reject(ctx, config, "BAD_REQUEST");
  }
  const firstCfg = parseCheckpointConfig(checkpoints[0].config);
  if (!firstCfg) {
    await recordEvent(ctx, null, "free_flow", "start-bad-checkpoint-config");
    return reject(ctx, config, "SERVER_ERROR");
  }
  const cooldownSec = firstCfg.cooldown_seconds ?? DEFAULT_COOLDOWN_SEC;

  const fingerprint = await fingerprintFor(config, input, bodyHwid);
  const recent = await ctx.db.first<{ n: number }>(
    "SELECT COUNT(*) AS n FROM free_attempts WHERE fingerprint = ? AND started_at > ?",
    [fingerprint, Math.floor(ctx.nowSec) - cooldownSec],
  );
  if ((recent?.n ?? 0) > 0) {
    await recordEvent(ctx, null, "free_bypass", "cooldown-reentry");
    return reject(ctx, config, "RATE_LIMITED", cooldownSec);
  }

  const burst = await ctx.limiter.hit(`free:hourly:${ipHash}`, config.free.attemptsPerIpPerHour, 3600);
  if (!burst.ok) {
    await recordEvent(ctx, null, "free_bypass", "ip-burst");
  }

  const attemptId = randomId();
  const token = b64urlEncode(randomBytes(32));
  const tokenHash = await sha256Hex(token);
  const now = Math.floor(ctx.nowSec);
  await ctx.db.run(
    "INSERT INTO free_attempts (id, project_id, fingerprint, step, token_hash, started_at, step_started_at, completed_at) VALUES (?, ?, ?, 1, ?, ?, ?, NULL)",
    [attemptId, project.id, fingerprint, tokenHash, now, now],
  );
  await recordEvent(ctx, null, "free_flow", "start:" + project.slug);

  const secret = await stepSecret(config, attemptId, 1);
  return ok(ctx, config, {
    token,
    step: 1,
    total_steps: checkpoints.length,
    url: renderUrl(firstCfg.url, secret, attemptId),
    min_seconds: firstCfg.min_seconds,
  });
}

// /free/step — body: { token: string, completion_token?: string, hwid?: string }
export async function handleFreeStep(ctx: AppContext, config: ApiConfig, input: RequestInput): Promise<Response> {
  const gate = await ipGate(ctx, config, input);
  if (gate > 0) return reject(ctx, config, "RATE_LIMITED", gate);
  const body = readJsonBody(input);
  if (
    !body ||
    typeof body.token !== "string" ||
    body.token.length === 0 ||
    body.token.length > 128 ||
    (body.completion_token !== undefined && (typeof body.completion_token !== "string" || body.completion_token.length > 256))
  ) {
    return reject(ctx, config, "BAD_REQUEST");
  }
  const tokenHash = await sha256Hex(body.token);
  const attempt = await ctx.db.first<AttemptRow>(
    "SELECT id, project_id, fingerprint, step, token_hash, started_at, step_started_at, completed_at FROM free_attempts WHERE token_hash = ?",
    [tokenHash],
  );
  if (!attempt) {
    await recordEvent(ctx, null, "free_bypass", "step-unknown-token");
    return reject(ctx, config, "BAD_REQUEST");
  }

  const fingerprint = await fingerprintFor(config, input, readBodyHwid(body));
  if (fingerprint !== attempt.fingerprint) {
    await recordEvent(ctx, null, "free_bypass", "step-fingerprint-mismatch");
    return reject(ctx, config, "BAD_REQUEST");
  }
  if (attempt.completed_at !== null) {
    await recordEvent(ctx, null, "free_bypass", "step-after-complete");
    return reject(ctx, config, "BAD_REQUEST");
  }
  const now = Math.floor(ctx.nowSec);
  if (now > attempt.started_at + config.free.attemptTtlSec) {
    await recordEvent(ctx, null, "free_flow", "step-attempt-expired");
    return reject(ctx, config, "BAD_REQUEST");
  }

  const checkpoints = await ctx.db.all<CheckpointRow>(
    "SELECT id, project_id, position, provider, config FROM checkpoints WHERE project_id = ? ORDER BY position ASC",
    [attempt.project_id],
  );
  if (checkpoints.length === 0 || attempt.step < 1 || attempt.step > checkpoints.length) {
    return reject(ctx, config, "BAD_REQUEST");
  }
  const checkpoint = checkpoints[attempt.step - 1];
  const cfg = parseCheckpointConfig(checkpoint.config);
  if (!cfg) return reject(ctx, config, "SERVER_ERROR");

  if (now < attempt.step_started_at + cfg.min_seconds) {
    await recordEvent(ctx, null, "free_bypass", "step-too-fast:" + checkpoint.position);
    return reject(ctx, config, "BAD_REQUEST");
  }

  const mode = cfg.verify;
  const supplied = typeof body.completion_token === "string" ? body.completion_token : "";
  if (mode === "secret") {
    const expected = await stepSecret(config, attempt.id, attempt.step);
    if (!constantTimeStringEqual(supplied, expected)) {
      await recordEvent(ctx, null, "free_bypass", "step-bad-secret:" + checkpoint.position);
      return reject(ctx, config, "BAD_REQUEST");
    }
  } else if (cfg.postback_secret) {
    const expected = await macLabel(utf8(cfg.postback_secret), attempt.id, attempt.step);
    if (!constantTimeStringEqual(supplied, expected)) {
      await recordEvent(ctx, null, "free_bypass", "step-bad-postback:" + checkpoint.position);
      return reject(ctx, config, "BAD_REQUEST");
    }
  }

  const nextStep = attempt.step + 1;
  const newToken = b64urlEncode(randomBytes(32));
  const newTokenHash = await sha256Hex(newToken);
  await ctx.db.run(
    "UPDATE free_attempts SET step = ?, token_hash = ?, step_started_at = ? WHERE id = ?",
    [nextStep, newTokenHash, now, attempt.id],
  );
  await recordEvent(ctx, null, "free_flow", "step:" + nextStep + "/" + checkpoints.length);

  if (nextStep > checkpoints.length) {
    return ok(ctx, config, { token: newToken, step: nextStep, total_steps: checkpoints.length, done: true, claim_window_sec: config.free.claimWindowSec });
  }
  const nextCfg = parseCheckpointConfig(checkpoints[nextStep - 1].config);
  if (!nextCfg) return reject(ctx, config, "SERVER_ERROR");
  const secret = await stepSecret(config, attempt.id, nextStep);
  return ok(ctx, config, {
    token: newToken,
    step: nextStep,
    total_steps: checkpoints.length,
    url: renderUrl(nextCfg.url, secret, attempt.id),
    min_seconds: nextCfg.min_seconds,
  });
}

// /free/claim — body: { token: string, hwid?: string }
export async function handleFreeClaim(ctx: AppContext, config: ApiConfig, input: RequestInput): Promise<Response> {
  const gate = await ipGate(ctx, config, input);
  if (gate > 0) return reject(ctx, config, "RATE_LIMITED", gate);
  const body = readJsonBody(input);
  if (!body || typeof body.token !== "string" || body.token.length === 0 || body.token.length > 128) {
    return reject(ctx, config, "BAD_REQUEST");
  }
  const tokenHash = await sha256Hex(body.token);
  const attempt = await ctx.db.first<AttemptRow>(
    "SELECT id, project_id, fingerprint, step, token_hash, started_at, step_started_at, completed_at FROM free_attempts WHERE token_hash = ?",
    [tokenHash],
  );
  if (!attempt) {
    await recordEvent(ctx, null, "free_bypass", "claim-unknown-token");
    return reject(ctx, config, "BAD_REQUEST");
  }
  const fingerprint = await fingerprintFor(config, input, readBodyHwid(body));
  if (fingerprint !== attempt.fingerprint) {
    await recordEvent(ctx, null, "free_bypass", "claim-fingerprint-mismatch");
    return reject(ctx, config, "BAD_REQUEST");
  }
  const now = Math.floor(ctx.nowSec);
  if (attempt.completed_at !== null) {
    await recordEvent(ctx, null, "free_bypass", "claim-already-claimed");
    return reject(ctx, config, "BAD_REQUEST");
  }
  if (now > attempt.started_at + config.free.attemptTtlSec) {
    return reject(ctx, config, "BAD_REQUEST");
  }

  const checkpoints = await ctx.db.all<{ id: string }>(
    "SELECT id FROM checkpoints WHERE project_id = ? ORDER BY position ASC",
    [attempt.project_id],
  );
  if (checkpoints.length === 0 || attempt.step !== checkpoints.length + 1) {
    await recordEvent(ctx, null, "free_bypass", "claim-uncompleted-steps");
    return reject(ctx, config, "BAD_REQUEST");
  }
  if (now > attempt.step_started_at + config.free.claimWindowSec) {
    await recordEvent(ctx, null, "free_flow", "claim-window-expired");
    return reject(ctx, config, "BAD_REQUEST");
  }

  const project = await ctx.db.first<ProjectRow>("SELECT id, name, slug FROM projects WHERE id = ?", [attempt.project_id]);
  if (!project) return reject(ctx, config, "SERVER_ERROR");

  const generated = generateKey();
  const keyHash = await hashKey(generated.plaintext, config.pepper);
  const keyId = "k" + generated.body.slice(0, 31).toLowerCase();
  const expiresAt = now + config.free.keyDays * 86400;
  await ctx.db.run(
    "INSERT INTO keys (id, project_id, key_hash, tier, status, note, total_executions, created_by, created_at, expires_at) VALUES (?, ?, ?, 'free', 'active', 'free flow', 0, 'free-flow', ?, ?)",
    [keyId, project.id, keyHash, now, expiresAt],
  );
  await ctx.db.run(
    "INSERT INTO key_scripts (key_id, script_id) SELECT ?, id FROM scripts WHERE project_id = ? AND keyless = 0",
    [keyId, project.id],
  );
  await ctx.db.run(
    "UPDATE free_attempts SET completed_at = ?, token_hash = ? WHERE id = ?",
    [now, "claimed:" + (await sha256Hex(randomBytes(32))), attempt.id],
  );
  await ctx.db.run(
    "INSERT INTO audit_log (id, actor_id, action, target, detail, created_at) VALUES (?, 'free-flow', 'create_key', ?, ?, ?)",
    [randomId(), keyId, "free claim attempt " + attempt.id, now],
  );
  await recordEvent(ctx, null, "free_flow", "claim:" + project.slug);

  return ok(ctx, config, { key: generated.plaintext, expires_at: expiresAt, tier: "free" });
}
