import { makeEnvelope } from "./contracts";
import { ApiConfig, AppContext, RequestInput, bodyWithinLimit, recordEvent, signedResponse } from "./flow";
import { handleCheckKey } from "./checkkey";
import { handleStatus, handleSync } from "./syncstatus";
import {
  handleAdminAnalytics,
  handleAdminAudit,
  handleAdminBlacklist,
  handleAdminCreateKeys,
  handleAdminNodes,
  handleAdminPatchKey,
  handleAdminProtocolVersions,
  handleAdminResetHwid,
  handleAdminRevokeKey,
  handleAdminScriptActivate,
  handleAdminScriptVersion,
  handleAdminCreateReseller,
} from "./admin";
import { handleAuthHeartbeat, handleAuthInit, handleAuthPayload } from "./auth";
import { handleFreeClaim, handleFreeStart, handleFreeStep } from "./freekey";
import {
  handleAdminListKeys,
  handleAdminListScripts,
  handleAdminListBlacklist,
  handleAdminListNodes,
  handleAdminListProtocolVersions,
  handleAdminListSessions,
  handleAdminListAdmins,
  handleAdminListUsers,
} from "./adminread";
import {
  handlePaymentsWebhook,
  handleAdminListOrders,
  handleAdminListProducts,
  handleAdminUpsertProduct,
  handleAdminReconcile,
} from "./payments";
import { handleAdminLeakLookup, handleAdminLeakRevoke, handleAdminAbuseScores } from "./leak";

export interface RouteHandlerArgs {
  ctx: AppContext;
  config: ApiConfig;
  input: RequestInput;
  params: Record<string, string>;
}

export interface Route {
  method: string;
  pattern: string;
  handler: (args: RouteHandlerArgs) => Promise<Response>;
}

export interface RouteMatch {
  route: Route;
  params: Record<string, string>;
}

export function matchRoute(routes: Route[], method: string, path: string): RouteMatch | null {
  let pathExists = false;
  for (const route of routes) {
    const params = matchPattern(route.pattern, path);
    if (params === null) continue;
    pathExists = true;
    if (route.method !== method) continue;
    return { route, params };
  }
  return pathExists ? { route: { method: "*", pattern: "", handler: methodNotAllowed }, params: {} } : null;
}

function methodNotAllowed(): Promise<Response> {
  return Promise.resolve(new Response(JSON.stringify({ error: "method_not_allowed" }), { status: 405, headers: { "content-type": "application/json" } }));
}

function matchPattern(pattern: string, path: string): Record<string, string> | null {
  // Query strings are not part of route matching (the Workers entry passes
  // url.pathname; handlers that need the query keep it in input.path).
  const cleanPath = path.split("?")[0];
  const pParts = pattern.split("/");
  const uParts = cleanPath.split("/");
  if (pParts.length !== uParts.length) return null;
  const params: Record<string, string> = {};
  for (let i = 0; i < pParts.length; i++) {
    const p = pParts[i];
    if (p.startsWith(":")) {
      if (uParts[i].length === 0) return null;
      params[p.slice(1)] = decodeURIComponent(uParts[i]);
    } else if (p !== uParts[i]) {
      return null;
    }
  }
  return params;
}

export function buildRoutes(): Route[] {
  return [
    { method: "GET", pattern: "/sync", handler: ({ ctx, input }) => handleSync(ctx, input.colo) },
    { method: "GET", pattern: "/status", handler: ({ ctx, config }) => handleStatus(ctx, config.statusActive) },
    { method: "POST", pattern: "/check_key", handler: ({ ctx, config, input }) => handleCheckKey(ctx, config, input) },
    { method: "POST", pattern: "/auth/:script_id/init", handler: (a) => handleAuthInit(a.ctx, a.config, a.input, a.params.script_id) },
    { method: "POST", pattern: "/auth/:script_id/payload", handler: (a) => handleAuthPayload(a.ctx, a.config, a.input, a.params.script_id) },
    { method: "POST", pattern: "/auth/:script_id/heartbeat", handler: (a) => handleAuthHeartbeat(a.ctx, a.config, a.input, a.params.script_id) },
    { method: "POST", pattern: "/free/start", handler: ({ ctx, config, input }) => handleFreeStart(ctx, config, input) },
    { method: "POST", pattern: "/free/step", handler: ({ ctx, config, input }) => handleFreeStep(ctx, config, input) },
    { method: "POST", pattern: "/free/claim", handler: ({ ctx, config, input }) => handleFreeClaim(ctx, config, input) },
    { method: "POST", pattern: "/webhooks/payments/:provider", handler: (a) => handlePaymentsWebhook(a.ctx, a.config, a.input, a.params.provider) },
    { method: "GET", pattern: "/admin/keys", handler: ({ ctx, config, input }) => handleAdminListKeys(ctx, config, input) },
    { method: "GET", pattern: "/admin/scripts", handler: ({ ctx, config, input }) => handleAdminListScripts(ctx, config, input) },
    { method: "GET", pattern: "/admin/blacklist", handler: ({ ctx, config, input }) => handleAdminListBlacklist(ctx, config, input) },
    { method: "GET", pattern: "/admin/nodes", handler: ({ ctx, config, input }) => handleAdminListNodes(ctx, config, input) },
    { method: "GET", pattern: "/admin/protocol-versions", handler: ({ ctx, config, input }) => handleAdminListProtocolVersions(ctx, config, input) },
    { method: "GET", pattern: "/admin/sessions", handler: ({ ctx, config, input }) => handleAdminListSessions(ctx, config, input) },
    { method: "GET", pattern: "/admin/admins", handler: ({ ctx, config, input }) => handleAdminListAdmins(ctx, config, input) },
    { method: "GET", pattern: "/admin/users", handler: ({ ctx, config, input }) => handleAdminListUsers(ctx, config, input) },
    { method: "POST", pattern: "/admin/keys", handler: ({ ctx, config, input }) => handleAdminCreateKeys(ctx, config, input) },
    { method: "PATCH", pattern: "/admin/keys/:id", handler: (a) => handleAdminPatchKey(a.ctx, a.config, a.input, a.params.id) },
    { method: "POST", pattern: "/admin/keys/:id/revoke", handler: (a) => handleAdminRevokeKey(a.ctx, a.config, a.input, a.params.id) },
    { method: "POST", pattern: "/admin/keys/:id/reset-hwid", handler: (a) => handleAdminResetHwid(a.ctx, a.config, a.input, a.params.id) },
    { method: "POST", pattern: "/admin/blacklist", handler: ({ ctx, config, input }) => handleAdminBlacklist(ctx, config, input) },
    { method: "POST", pattern: "/admin/nodes", handler: ({ ctx, config, input }) => handleAdminNodes(ctx, config, input) },
    { method: "POST", pattern: "/admin/protocol-versions", handler: ({ ctx, config, input }) => handleAdminProtocolVersions(ctx, config, input) },
    { method: "POST", pattern: "/admin/scripts/:id/versions", handler: (a) => handleAdminScriptVersion(a.ctx, a.config, a.input, a.params.id) },
    { method: "POST", pattern: "/admin/scripts/:id/activate", handler: (a) => handleAdminScriptActivate(a.ctx, a.config, a.input, a.params.id) },
    { method: "POST", pattern: "/admin/resellers", handler: ({ ctx, config, input }) => handleAdminCreateReseller(ctx, config, input) },
    { method: "GET", pattern: "/admin/analytics/overview", handler: ({ ctx, config, input }) => handleAdminAnalytics(ctx, config, input) },
    { method: "GET", pattern: "/admin/audit", handler: ({ ctx, config, input }) => handleAdminAudit(ctx, config, input) },
    { method: "GET", pattern: "/admin/payments/orders", handler: ({ ctx, config, input }) => handleAdminListOrders(ctx, config, input) },
    { method: "GET", pattern: "/admin/payments/products", handler: ({ ctx, config, input }) => handleAdminListProducts(ctx, config, input) },
    { method: "POST", pattern: "/admin/payments/products", handler: ({ ctx, config, input }) => handleAdminUpsertProduct(ctx, config, input) },
    { method: "GET", pattern: "/admin/abuse-scores", handler: ({ ctx, config, input }) => handleAdminAbuseScores(ctx, config, input) },
    { method: "POST", pattern: "/admin/leak/lookup", handler: ({ ctx, config, input }) => handleAdminLeakLookup(ctx, config, input) },
    { method: "POST", pattern: "/admin/leak/revoke", handler: ({ ctx, config, input }) => handleAdminLeakRevoke(ctx, config, input) },
    { method: "POST", pattern: "/admin/payments/reconcile", handler: ({ ctx, config, input }) => handleAdminReconcile(ctx, config, input) },
  ];
}

export async function dispatch(routes: Route[], ctx: AppContext, config: ApiConfig, input: RequestInput): Promise<Response> {
  if (!bodyWithinLimit(input)) {
    return signedResponse(makeEnvelope("BAD_REQUEST", null), config.signer, ctx.nowSec);
  }
  const match = matchRoute(routes, input.method, input.path);
  if (!match) {
    return new Response(JSON.stringify({ error: "not_found" }), { status: 404, headers: { "content-type": "application/json" } });
  }
  try {
    return await match.route.handler({ ctx, config, input, params: match.params });
  } catch (err) {
    await recordEvent(ctx, null, "server_error", err instanceof Error ? err.name : "unknown");
    return signedResponse(makeEnvelope("SERVER_ERROR", null), config.signer, ctx.nowSec);
  }
}
