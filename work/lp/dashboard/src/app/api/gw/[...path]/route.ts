// Gateway route: forwards dashboard requests to the REAL api/ router
// (modules M1 + M9) running in-process. In dev mode (DASH_DEV_MODE, default
// on in this harness) the seeded owner admin token is injected so the demo
// is usable without credentials; production sets DASH_DEV_MODE=false and
// relies on the dashboard login (token / Discord OAuth / TOTP per doc §16).

import { NextRequest } from "next/server";
import { buildRoutes, dispatch } from "@api/src/router";
import { RequestInput } from "@api/src/flow";
import { DASH_DEV_MODE, getStore } from "@/server/store";

interface GwParams {
  params: Promise<{ path?: string[] }>;
}

async function handle(request: NextRequest, params: GwParams): Promise<Response> {
  const { path } = await params.params;
  const store = await getStore();
  const url = new URL(request.url);
  const gwPath = "/" + (path ?? []).join("/");

  const headers: Record<string, string> = {};
  request.headers.forEach((value, key) => {
    headers[key] = value;
  });
  if (DASH_DEV_MODE && !headers["authorization"]) {
    headers["authorization"] = `Bearer ${store.devAdminToken}`;
  }

  const input: RequestInput = {
    method: request.method,
    path: gwPath + url.search,
    headers,
    bodyBytes: new Uint8Array(await request.arrayBuffer()),
    ip: headers["x-real-ip"] ?? "127.0.0.1",
    colo: "DASH",
  };
  return dispatch(buildRoutes(), store.ctx, store.config, input);
}

export async function GET(request: NextRequest, params: GwParams): Promise<Response> {
  return handle(request, params);
}

export async function POST(request: NextRequest, params: GwParams): Promise<Response> {
  return handle(request, params);
}

export async function PATCH(request: NextRequest, params: GwParams): Promise<Response> {
  return handle(request, params);
}

export async function PUT(request: NextRequest, params: GwParams): Promise<Response> {
  return handle(request, params);
}

export async function DELETE(request: NextRequest, params: GwParams): Promise<Response> {
  return handle(request, params);
}
