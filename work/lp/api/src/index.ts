import { b64urlDecode } from "./contracts";
import { makeSigner, Signer } from "./crypto";
import { D1Adapter } from "./db";
import { R2BlobStore } from "./blobs";
import { refSealKey } from "./auth";
import { AppContext, ApiConfig, RequestInput } from "./flow";
import { buildRoutes, dispatch } from "./router";
import { NonceStore, RateLimiter } from "./state";
import { RateCounterDO, NonceDO } from "./durable";

export { RateCounterDO, NonceDO };

interface Env {
  DB: unknown;
  RATE_COUNTER: unknown;
  NONCE: unknown;
  BUNDLES: unknown;
  SERVER_PEPPER: string;
  SIGNING_PRIVATE_KEY_B64URL: string;
  PROOF_KEY_B64URL: string;
  EXECUTOR_HWID_HEADERS: string;
  STATUS_ACTIVE: string;
  SESSION_SEAL_KEY: string;
  SESSION_TTL_SEC: string;
  PROJECT_SIGNING_KEYS: string;
  FREE_SECRET: string;
  FREE_KEY_DAYS: string;
  FREE_ATTEMPT_TTL_SEC: string;
  FREE_CLAIM_WINDOW_SEC: string;
  PAYMENTS_STRIPE_SECRET: string;
  PAYMENTS_CUSTOM_SECRET: string;
  PAYMENTS_SIG_TOLERANCE_SEC: string;
  PAYMENTS_PROVIDER_BASE: string;
  PAYMENTS_PROVIDER_API_KEY: string;
}

interface RateStub {
  hit: (limit: number, windowSec: number) => Promise<{ ok: boolean; retryAfterSec: number }>;
  blocked: (limit: number, windowSec: number) => Promise<{ ok: boolean; retryAfterSec: number }>;
}

interface NonceStub {
  seen: (nonce: string, expiresAtSec: number) => Promise<boolean>;
}

interface Namespace {
  idFromName: (name: string) => { name: string };
  get: (id: { name: string }) => unknown;
}

class DurableRateLimiter implements RateLimiter {
  constructor(private readonly ns: Namespace) {}

  async hit(bucket: string, limit: number, windowSec: number): Promise<{ ok: boolean; retryAfterSec: number }> {
    const stub = this.ns.get(this.ns.idFromName(bucket)) as RateStub;
    return stub.hit(limit, windowSec);
  }

  async blocked(bucket: string, limit: number, windowSec: number): Promise<{ ok: boolean; retryAfterSec: number }> {
    const stub = this.ns.get(this.ns.idFromName(bucket)) as RateStub;
    return stub.blocked(limit, windowSec);
  }
}

class DurableNonceStore implements NonceStore {
  constructor(private readonly ns: Namespace) {}

  async seen(nonce: string, expiresAtSec: number): Promise<boolean> {
    const stub = this.ns.get(this.ns.idFromName(nonce)) as NonceStub;
    return stub.seen(nonce, expiresAtSec);
  }
}

const routes = buildRoutes();

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);
    const cf = (request as Request & { cf?: { colo?: string } }).cf;
    const input: RequestInput = {
      method: request.method,
      path: url.pathname,
      headers: Object.fromEntries(request.headers.entries()),
      bodyBytes: new Uint8Array(await request.arrayBuffer()),
      ip: request.headers.get("cf-connecting-ip") ?? "0.0.0.0",
      colo: cf?.colo ?? "",
    };
    const signer = await makeSigner(env.SIGNING_PRIVATE_KEY_B64URL);

    // Per-project bundle signing keys (doc.md §18): env map of
    // signing_key_id -> PKCS8 base64url. Falls back to the default signer so
    // a single-project deployment needs no map.
    const bundleSigners = new Map<string, Signer>();
    if (env.PROJECT_SIGNING_KEYS) {
      try {
        const parsed = JSON.parse(env.PROJECT_SIGNING_KEYS) as Record<string, string>;
        for (const [keyId, pkcs8] of Object.entries(parsed)) {
          bundleSigners.set(keyId, await makeSigner(pkcs8));
        }
      } catch {
        // Malformed env: fall back to the default signer; the error surfaces
        // in ops logs via the SERVER_ERROR envelope if a payload is signed.
      }
    }
    const bundleSignerFor = (_projectId: string, signingKeyId: string): Signer =>
      bundleSigners.get(signingKeyId) ?? signer;

    const config: ApiConfig = {
      pepper: env.SERVER_PEPPER,
      proofKey: b64urlDecode(env.PROOF_KEY_B64URL),
      signer,
      executorHwidHeaders: (env.EXECUTOR_HWID_HEADERS ?? "")
        .split(",")
        .map((s) => s.trim())
        .filter((s) => s.length > 0),
      statusActive: (env.STATUS_ACTIVE ?? "true") !== "false",
      sessionTtlSec: Number(env.SESSION_TTL_SEC ?? "3600") || 3600,
      refSealKey: await refSealKey(env.SESSION_SEAL_KEY),
      bundleStore: new R2BlobStore(env.BUNDLES as never),
      bundleSignerFor,
      free: {
        requestsPerIpPerMin: 30,
        startsPerIpPerMin: 5,
        attemptsPerIpPerHour: 10,
        attemptTtlSec: Number(env.FREE_ATTEMPT_TTL_SEC ?? "7200") || 7200,
        claimWindowSec: Number(env.FREE_CLAIM_WINDOW_SEC ?? "900") || 900,
        keyDays: Number(env.FREE_KEY_DAYS ?? "3") || 3,
      },
      freeSecret: b64urlDecode(env.FREE_SECRET ?? ""),
      payments: {
        // Comma-separated lists: rotation windows accept every listed secret.
        webhookSecrets: {
          ...(env.PAYMENTS_STRIPE_SECRET ? { stripe: env.PAYMENTS_STRIPE_SECRET.split(",").map((s) => s.trim()).filter((s) => s.length > 0) } : {}),
          ...(env.PAYMENTS_CUSTOM_SECRET ? { custom: env.PAYMENTS_CUSTOM_SECRET.split(",").map((s) => s.trim()).filter((s) => s.length > 0) } : {}),
        },
        signatureToleranceSec: Number(env.PAYMENTS_SIG_TOLERANCE_SEC ?? "300") || 300,
        requestsPerIpPerMin: 30,
        ...(env.PAYMENTS_PROVIDER_BASE ? { providerBase: env.PAYMENTS_PROVIDER_BASE } : {}),
        ...(env.PAYMENTS_PROVIDER_API_KEY ? { providerApiKey: env.PAYMENTS_PROVIDER_API_KEY } : {}),
      },
    };
    const ctx: AppContext = {
      db: new D1Adapter(env.DB as never),
      limiter: new DurableRateLimiter(env.RATE_COUNTER as Namespace),
      nonce: new DurableNonceStore(env.NONCE as Namespace),
      nowSec: Date.now() / 1000,
    };
    return dispatch(routes, ctx, config, input);
  },
};
