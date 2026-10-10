// POST /api/dash/simulate-webhook — DEV-ONLY (DASH_DEV_MODE) helper for the
// Payments view: builds a custom-provider payment event, signs it with the
// dev webhook secret SERVER-SIDE (the secret never reaches the client), and
// dispatches it through the REAL /webhooks/payments/custom router path —
// signature verification, the idempotency gate, issuance and refund paths
// are all the production code. `tamper: true` corrupts the signature to
// demonstrate the 400 invalid_signature path.

import { NextRequest, NextResponse } from "next/server";
import { buildRoutes, dispatch } from "@api/src/router";
import { RequestInput } from "@api/src/flow";
import { hmacSha256, randomId, utf8 } from "@api/src/crypto";
import { DASH_DEV_MODE, DEV_WEBHOOK_SECRET, getStore } from "@/server/store";

interface SimBody {
  type?: unknown;
  order_id?: unknown;
  product_ref?: unknown;
  discord_id?: unknown;
  email?: unknown;
  amount_minor?: unknown;
  tamper?: unknown;
}

const TYPES = ["payment.confirmed", "payment.refunded", "payment.disputed"];

export async function POST(request: NextRequest): Promise<Response> {
  if (!DASH_DEV_MODE) {
    return NextResponse.json({ error: "dev_only" }, { status: 404 });
  }
  let body: SimBody | null = null;
  try {
    body = (await request.json()) as SimBody;
  } catch {
    body = null;
  }
  const type = typeof body?.type === "string" && TYPES.includes(body.type) ? body.type : "payment.confirmed";
  const eventId = "evt_sim_" + randomId().slice(0, 12);
  const orderId =
    typeof body?.order_id === "string" && body.order_id.length > 0 && body.order_id.length <= 64
      ? body.order_id
      : "ord_sim_" + randomId().slice(0, 10);
  const event = {
    id: eventId,
    type,
    order_id: orderId,
    product_ref: typeof body?.product_ref === "string" && body.product_ref.length > 0 ? body.product_ref : "prod_demo_30d",
    amount_minor: typeof body?.amount_minor === "number" ? body.amount_minor : 999,
    currency: "usd",
    discord_id: typeof body?.discord_id === "string" && body.discord_id.length > 0 ? body.discord_id : "778899",
    email: typeof body?.email === "string" && body.email.length > 0 ? body.email : "simulated@example.test",
  };
  const bodyBytes = utf8(JSON.stringify(event));
  const mac = await hmacSha256(utf8(DEV_WEBHOOK_SECRET), bodyBytes);
  const signature = Array.from(mac, (b) => b.toString(16).padStart(2, "0")).join("");
  const headers: Record<string, string> = {
    "X-Event-Id": eventId,
    "X-Signature": body?.tamper === true ? "0".repeat(128) : signature,
  };
  const store = await getStore();
  const input: RequestInput = {
    method: "POST",
    path: "/webhooks/payments/custom",
    headers,
    bodyBytes,
    ip: "203.0.113.77",
    colo: "DASH",
  };
  const res = await dispatch(buildRoutes(), store.ctx, store.config, input);
  const text = await res.text();
  let parsed: unknown = null;
  try {
    parsed = JSON.parse(text);
  } catch {
    parsed = { raw: text };
  }
  return NextResponse.json({ status: res.status, event, response: parsed });
}
