"use client";

import { useState } from "react";
import { toast } from "sonner";
import { Alert, AlertDescription, AlertTitle } from "@/components/ui/alert";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle, DialogTrigger } from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { ScrollArea } from "@/components/ui/scroll-area";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Skeleton } from "@/components/ui/skeleton";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { formatTime, gw, shortHash } from "@/lib/api";
import { csvTimestamp, exportCsv } from "@/lib/export-utils";
import { useApiData } from "@/lib/use-api-data";
import { Banknote, CreditCard, Download, Play, Plus, RefreshCw, ShieldAlert, ShieldCheck } from "lucide-react";

const DEMO_PROJECT_ID = "11111111111111111111111111111111";

interface OrderRow {
  id: string;
  provider: string;
  provider_order_id: string;
  product_ref: string;
  key_id: string | null;
  discord_id: string | null;
  email: string | null;
  amount_minor: number | null;
  currency: string | null;
  status: string;
  created_at: number;
  updated_at: number;
}

interface ProductRow {
  id: string;
  provider: string;
  product_ref: string;
  project_id: string;
  project_name: string | null;
  tier: string;
  days: number | null;
  refund_blacklists: boolean;
  active: boolean;
}

interface ReconcileReport {
  counts: { paid_key_missing_or_revoked: number; refunded_or_disputed_but_active: number; keys_without_order: number };
  provider_cross_check: string;
  provider_order_count: number;
  provider_error: string | null;
  generated_at: number;
  report: {
    paid_key_missing_or_revoked: OrderRow[];
    refunded_or_disputed_but_active: OrderRow[];
    keys_without_order: { id: string; tier: string; status: string; created_by: string }[];
  };
}

function money(minor: number | null, currency: string | null): string {
  if (minor === null) return "—";
  const c = currency ?? "usd";
  try {
    return new Intl.NumberFormat("en-US", { style: "currency", currency: c }).format(minor / 100);
  } catch {
    return `${(minor / 100).toFixed(2)} ${c.toUpperCase()}`;
  }
}

function OrderStatusBadge({ status }: { status: string }): React.JSX.Element {
  if (status === "paid") return <Badge className="bg-emerald-600 hover:bg-emerald-600">{status}</Badge>;
  if (status === "refunded") return <Badge className="bg-amber-600 hover:bg-amber-600">{status}</Badge>;
  if (status === "disputed") return <Badge variant="destructive">{status}</Badge>;
  return <Badge variant="secondary">{status}</Badge>;
}

export function PaymentsView(): React.JSX.Element {
  const [actionError, setActionError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [statusFilter, setStatusFilter] = useState("all");

  const orders = useApiData<{ rows: OrderRow[]; total: number }>(
    () => gw<{ rows: OrderRow[]; total: number }>("GET", `/admin/payments/orders${statusFilter !== "all" ? `?status=${statusFilter}` : ""}`),
    [statusFilter],
  );
  const products = useApiData<{ rows: ProductRow[] }>(() => gw<{ rows: ProductRow[] }>("GET", "/admin/payments/products"), []);
  const orderRows = orders.data?.rows ?? null;

  // webhook simulator state
  const [simType, setSimType] = useState("payment.confirmed");
  const [simProduct, setSimProduct] = useState("prod_demo_30d");
  const [simOrder, setSimOrder] = useState("");
  const [simResult, setSimResult] = useState<{ status: number; event: Record<string, unknown>; response: Record<string, unknown> } | null>(null);

  // product dialog state
  const [prodOpen, setProdOpen] = useState(false);
  const [prodRef, setProdRef] = useState("");
  const [prodTier, setProdTier] = useState("paid");
  const [prodDays, setProdDays] = useState("30");
  const [prodBlacklist, setProdBlacklist] = useState(false);

  // reconcile state
  const [reconcile, setReconcile] = useState<ReconcileReport | null>(null);

  async function runSim(tamper: boolean): Promise<void> {
    setBusy(true);
    try {
      const res = await fetch("/api/dash/simulate-webhook", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({
          type: simType,
          product_ref: simProduct,
          order_id: simOrder.trim().length > 0 ? simOrder.trim() : undefined,
          tamper,
        }),
      });
      const j = (await res.json()) as { status: number; event: Record<string, unknown>; response: Record<string, unknown> };
      setSimResult(j);
      orders.refresh();
      products.refresh();
      const outcome = (j.response as { outcome?: string; error?: string }).outcome ?? (j.response as { error?: string }).error ?? "?";
      const ok = j.status === 200 && outcome === "issued";
      if (ok) {
        toast.success(`Webhook → HTTP ${j.status} (${outcome})`, { description: "Real signature verify + idempotency gate ran server-side." });
      } else {
        toast.error(`Webhook → HTTP ${j.status} (${outcome})`, { description: "Rejected by the real verifier — see the response below." });
      }
    } catch (e) {
      const msg = e instanceof Error ? e.message : "simulation failed";
      setActionError(msg);
      toast.error("Simulation failed", { description: msg });
    } finally {
      setBusy(false);
    }
  }

  async function saveProduct(): Promise<void> {
    setBusy(true);
    try {
      await gw("POST", "/admin/payments/products", {
        provider: "custom",
        product_ref: prodRef.trim(),
        project_id: DEMO_PROJECT_ID,
        tier: prodTier,
        days: prodTier === "lifetime" ? null : Math.max(1, parseInt(prodDays, 10) || 30),
        scripts: [],
        refund_blacklists: prodBlacklist,
      });
      toast.success(`Product mapping ${prodRef.trim()} saved`, { description: "Mutation audit-logged." });
      setProdOpen(false);
      setProdRef("");
      products.refresh();
    } catch (e) {
      setActionError(e instanceof Error ? e.message : "product save failed");
    } finally {
      setBusy(false);
    }
  }

  async function runReconcile(): Promise<void> {
    setBusy(true);
    try {
      const res = await gw<ReconcileReport>("POST", "/admin/payments/reconcile", {});
      setReconcile(res);
      const drift = res.counts.refunded_or_disputed_but_active + res.counts.paid_key_missing_or_revoked;
      if (drift > 0) {
        toast.warning(`Reconcile: ${drift} drift rows`, {
          description: `${res.counts.refunded_or_disputed_but_active} refunded-but-active, ${res.counts.paid_key_missing_or_revoked} broken, ${res.counts.keys_without_order} orphan keys.`,
        });
      } else {
        toast.success("Reconcile clean", {
          description: `${res.counts.keys_without_order} orphan keys, 0 broken, 0 refunded-but-active.`,
        });
      }
    } catch (e) {
      setActionError(e instanceof Error ? e.message : "reconcile failed");
    } finally {
      setBusy(false);
    }
  }

  function exportOrdersCsv(): void {
    if (!orderRows) return;
    exportCsv(`yuri-orders-${csvTimestamp()}`, ["order", "provider", "product", "key_id", "discord", "email", "amount_minor", "currency", "status", "created_at", "updated_at"], orderRows.map((r) => [r.provider_order_id, r.provider, r.product_ref, r.key_id ?? "", r.discord_id ?? "", r.email ?? "", r.amount_minor ?? "", r.currency ?? "", r.status, formatTime(r.created_at), formatTime(r.updated_at)]));
    toast.info("CSV exported", { description: `${orderRows.length} order rows (current filter).` });
  }

  return (
    <div className="space-y-4">
      {error0(orders.error, actionError)}

      <Tabs defaultValue="orders">
        <TabsList>
          <TabsTrigger value="orders">Orders</TabsTrigger>
          <TabsTrigger value="products">Products</TabsTrigger>
          <TabsTrigger value="webhook">Webhook simulator</TabsTrigger>
          <TabsTrigger value="reconcile">Reconcile</TabsTrigger>
        </TabsList>

        <TabsContent value="orders" className="mt-4 space-y-4">
          <div className="flex flex-wrap items-center gap-2">
            <Select value={statusFilter} onValueChange={setStatusFilter}>
              <SelectTrigger className="w-36" aria-label="filter by status">
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value="all">all status</SelectItem>
                <SelectItem value="paid">paid</SelectItem>
                <SelectItem value="refunded">refunded</SelectItem>
                <SelectItem value="disputed">disputed</SelectItem>
              </SelectContent>
            </Select>
            <Button variant="outline" size="icon" onClick={() => orders.refresh()} aria-label="refresh orders">
              <RefreshCw className="h-4 w-4" />
            </Button>
            <Button variant="outline" onClick={exportOrdersCsv} disabled={!orderRows || orderRows.length === 0}>
              <Download className="mr-1 h-4 w-4" /> CSV
            </Button>
            <p className="text-sm text-muted-foreground">
              Confirmed payments issue keys through the real M9-style path; refunds revoke, disputes blacklist (doc §17).
            </p>
          </div>
          <Card>
            <CardHeader className="pb-2">
              <CardTitle className="text-sm text-muted-foreground">
                {orderRows === null ? "loading…" : `${orders.data?.total ?? 0} order${(orders.data?.total ?? 0) === 1 ? "" : "s"} (provider references stored verbatim)`}
              </CardTitle>
            </CardHeader>
            <CardContent>
              {orderRows === null ? (
                <div className="space-y-2">
                  {Array.from({ length: 4 }).map((_, i) => (
                    <Skeleton key={i} className="skeleton-shimmer h-10" />
                  ))}
                </div>
              ) : orderRows.length === 0 ? (
                <p className="py-8 text-center text-sm text-muted-foreground">No orders — run the webhook simulator to create one.</p>
              ) : (
                <ScrollArea className="max-h-96">
                  <Table>
                    <TableHeader>
                      <TableRow>
                        <TableHead>Order</TableHead>
                        <TableHead>Provider</TableHead>
                        <TableHead>Product</TableHead>
                        <TableHead>Key</TableHead>
                        <TableHead>Buyer</TableHead>
                        <TableHead>Amount</TableHead>
                        <TableHead>Status</TableHead>
                        <TableHead>Updated</TableHead>
                      </TableRow>
                    </TableHeader>
                    <TableBody>
                      {orderRows.map((r) => (
                        <TableRow key={r.id}>
                          <TableCell className="font-mono text-xs">{r.provider_order_id}</TableCell>
                          <TableCell>
                            <Badge variant="outline">{r.provider}</Badge>
                          </TableCell>
                          <TableCell className="font-mono text-xs">{r.product_ref}</TableCell>
                          <TableCell className="font-mono text-xs">{r.key_id ? shortHash(r.key_id, 8) : "—"}</TableCell>
                          <TableCell className="text-xs">
                            <span className="flex flex-col">
                              {r.discord_id ? <span className="font-mono">discord {r.discord_id}</span> : null}
                              {r.email ? <span className="text-muted-foreground">{r.email}</span> : null}
                            </span>
                          </TableCell>
                          <TableCell className="tabular-nums text-xs">{money(r.amount_minor, r.currency)}</TableCell>
                          <TableCell>
                            <OrderStatusBadge status={r.status} />
                          </TableCell>
                          <TableCell className="text-xs">{formatTime(r.updated_at)}</TableCell>
                        </TableRow>
                      ))}
                    </TableBody>
                  </Table>
                </ScrollArea>
              )}
            </CardContent>
          </Card>
        </TabsContent>

        <TabsContent value="products" className="mt-4 space-y-4">
          <div className="flex flex-wrap items-center gap-2">
            <Dialog open={prodOpen} onOpenChange={setProdOpen}>
              <DialogTrigger asChild>
                <Button size="sm">
                  <Plus className="mr-1 h-4 w-4" /> Product mapping
                </Button>
              </DialogTrigger>
              <DialogContent>
                <DialogHeader>
                  <DialogTitle>Product → key mapping</DialogTitle>
                  <DialogDescription>
                    A provider product reference maps to tier, duration, and script entitlements. Confirmed payments for an unmapped
                    product are accepted but ignored (logged, no key).
                  </DialogDescription>
                </DialogHeader>
                <div className="grid gap-3 py-1">
                  <div className="grid gap-1.5">
                    <Label htmlFor="prod-ref">Product ref (provider price id)</Label>
                    <Input id="prod-ref" value={prodRef} onChange={(e) => setProdRef(e.target.value)} placeholder="prod_my_30d" className="font-mono" />
                  </div>
                  <div className="grid gap-1.5">
                    <Label>Tier</Label>
                    <Select value={prodTier} onValueChange={(v) => setProdTier(v)}>
                      <SelectTrigger aria-label="tier">
                        <SelectValue />
                      </SelectTrigger>
                      <SelectContent>
                        <SelectItem value="paid">paid</SelectItem>
                        <SelectItem value="lifetime">lifetime</SelectItem>
                        <SelectItem value="reseller">reseller</SelectItem>
                      </SelectContent>
                    </Select>
                  </div>
                  {prodTier !== "lifetime" && (
                    <div className="grid gap-1.5">
                      <Label htmlFor="prod-days">Duration (days)</Label>
                      <Input id="prod-days" value={prodDays} onChange={(e) => setProdDays(e.target.value)} inputMode="numeric" />
                    </div>
                  )}
                  <label className="flex items-center gap-2 text-sm">
                    <input type="checkbox" checked={prodBlacklist} onChange={(e) => setProdBlacklist(e.target.checked)} className="h-4 w-4 accent-emerald-600" />
                    Refunds blacklist the buyer (disputes always do)
                  </label>
                </div>
                <DialogFooter>
                  <Button onClick={saveProduct} disabled={busy || prodRef.trim().length === 0}>
                    {busy ? "Saving…" : "Save mapping"}
                  </Button>
                </DialogFooter>
              </DialogContent>
            </Dialog>
            <Button variant="outline" size="icon" onClick={() => products.refresh()} aria-label="refresh products">
              <RefreshCw className="h-4 w-4" />
            </Button>
          </div>
          <Card>
            <CardHeader className="pb-2">
              <CardTitle className="text-sm text-muted-foreground">
                {products.data === null ? "loading…" : `${products.data.rows.length} product mapping${products.data.rows.length === 1 ? "" : "s"}`}
              </CardTitle>
            </CardHeader>
            <CardContent>
              {products.data === null ? (
                <Skeleton className="skeleton-shimmer h-24" />
              ) : products.data.rows.length === 0 ? (
                <p className="py-8 text-center text-sm text-muted-foreground">No product mappings yet.</p>
              ) : (
                <ScrollArea className="max-h-96">
                  <Table>
                    <TableHeader>
                      <TableRow>
                        <TableHead>Provider</TableHead>
                        <TableHead>Product ref</TableHead>
                        <TableHead>Project</TableHead>
                        <TableHead>Tier</TableHead>
                        <TableHead>Duration</TableHead>
                        <TableHead>Refund → blacklist</TableHead>
                        <TableHead>Active</TableHead>
                      </TableRow>
                    </TableHeader>
                    <TableBody>
                      {products.data.rows.map((p) => (
                        <TableRow key={p.id}>
                          <TableCell>
                            <Badge variant="outline">{p.provider}</Badge>
                          </TableCell>
                          <TableCell className="font-mono text-xs">{p.product_ref}</TableCell>
                          <TableCell className="text-xs">{p.project_name ?? shortHash(p.project_id, 8)}</TableCell>
                          <TableCell>
                            <Badge variant="secondary">{p.tier}</Badge>
                          </TableCell>
                          <TableCell className="text-xs">{p.days === null ? "lifetime" : `${p.days}d`}</TableCell>
                          <TableCell>
                            {p.refund_blacklists ? (
                              <Badge className="bg-amber-600 hover:bg-amber-600">yes</Badge>
                            ) : (
                              <Badge variant="secondary">no</Badge>
                            )}
                          </TableCell>
                          <TableCell>
                            {p.active ? (
                              <Badge className="bg-emerald-600 hover:bg-emerald-600">active</Badge>
                            ) : (
                              <Badge variant="outline">off</Badge>
                            )}
                          </TableCell>
                        </TableRow>
                      ))}
                    </TableBody>
                  </Table>
                </ScrollArea>
              )}
            </CardContent>
          </Card>
        </TabsContent>

        <TabsContent value="webhook" className="mt-4 space-y-4">
          <Card>
            <CardHeader className="pb-2">
              <CardTitle className="flex items-center gap-2 text-sm">
                <Play className="h-4 w-4 text-muted-foreground" /> Webhook simulator (dev mode)
              </CardTitle>
            </CardHeader>
            <CardContent className="space-y-3">
              <p className="text-sm text-muted-foreground">
                Signs a custom-provider event with the dev secret <em>server-side</em> and POSTs it through the real
                <code className="mx-1 rounded bg-muted px-1 py-0.5 font-mono text-xs">/webhooks/payments/custom</code>
                dispatch: signature verification, the UNIQUE(provider, event_id) idempotency gate, key issuance and refund revocation
                all run for real.
              </p>
              <div className="grid gap-3 sm:grid-cols-3">
                <div className="grid gap-1.5">
                  <Label>Event type</Label>
                  <Select value={simType} onValueChange={setSimType}>
                    <SelectTrigger aria-label="event type">
                      <SelectValue />
                    </SelectTrigger>
                    <SelectContent>
                      <SelectItem value="payment.confirmed">payment.confirmed</SelectItem>
                      <SelectItem value="payment.refunded">payment.refunded</SelectItem>
                      <SelectItem value="payment.disputed">payment.disputed</SelectItem>
                    </SelectContent>
                  </Select>
                </div>
                <div className="grid gap-1.5">
                  <Label htmlFor="sim-product">Product ref</Label>
                  <Input id="sim-product" value={simProduct} onChange={(e) => setSimProduct(e.target.value)} className="font-mono" />
                </div>
                <div className="grid gap-1.5">
                  <Label htmlFor="sim-order">Order id (blank = new)</Label>
                  <Input id="sim-order" value={simOrder} onChange={(e) => setSimOrder(e.target.value)} placeholder="auto" className="font-mono" />
                </div>
              </div>
              <div className="flex flex-wrap gap-2">
                <Button onClick={() => runSim(false)} disabled={busy}>
                  <ShieldCheck className="mr-1 h-4 w-4" /> Send signed webhook
                </Button>
                <Button variant="outline" onClick={() => runSim(true)} disabled={busy}>
                  <ShieldAlert className="mr-1 h-4 w-4" /> Send tampered signature
                </Button>
              </div>
              {simResult && (
                <div className="rounded-md border bg-muted/40 p-3">
                  <p className="mb-1 text-xs font-medium uppercase tracking-wide text-muted-foreground">
                    HTTP {simResult.status} — response
                  </p>
                  <pre className="max-h-52 overflow-auto whitespace-pre-wrap break-all rounded bg-background p-2 font-mono text-xs">
                    {JSON.stringify({ event: simResult.event, response: simResult.response }, null, 2)}
                  </pre>
                </div>
              )}
            </CardContent>
          </Card>
        </TabsContent>

        <TabsContent value="reconcile" className="mt-4 space-y-4">
          <div className="flex flex-wrap items-center gap-2">
            <Button onClick={runReconcile} disabled={busy}>
              <Banknote className="mr-1 h-4 w-4" /> Run reconciliation
            </Button>
            <p className="text-sm text-muted-foreground">Compares stored orders against issued keys and flags drift (doc §17 row 4).</p>
          </div>
          {reconcile && (
            <div className="space-y-4">
              <div className="grid gap-3 sm:grid-cols-3">
                <ReconcileStat
                  icon={<CreditCard className="h-4 w-4" />}
                  label="paid, key missing/revoked"
                  value={reconcile.counts.paid_key_missing_or_revoked}
                  bad={reconcile.counts.paid_key_missing_or_revoked > 0}
                />
                <ReconcileStat
                  icon={<ShieldAlert className="h-4 w-4" />}
                  label="refunded/disputed, key still active"
                  value={reconcile.counts.refunded_or_disputed_but_active}
                  bad={reconcile.counts.refunded_or_disputed_but_active > 0}
                />
                <ReconcileStat
                  icon={<ShieldCheck className="h-4 w-4" />}
                  label="m10 keys without an order"
                  value={reconcile.counts.keys_without_order}
                  bad={reconcile.counts.keys_without_order > 0}
                />
              </div>
              <p className="text-xs text-muted-foreground">
                Provider cross-check: {reconcile.provider_cross_check}
                {reconcile.provider_error ? ` (${reconcile.provider_error})` : ""}
                {reconcile.provider_cross_check === "fetched" ? ` — ${reconcile.provider_order_count} provider orders` : ""} · generated{" "}
                {formatTime(reconcile.generated_at)}
              </p>
              {reconcile.report.refunded_or_disputed_but_active.map((o) => (
                <Alert key={o.id} variant="destructive">
                  <AlertTitle>drift: {o.provider_order_id}</AlertTitle>
                  <AlertDescription>
                    order {o.status} but key {shortHash(o.key_id ?? "", 8)} is still active — revoke it.
                  </AlertDescription>
                </Alert>
              ))}
              {reconcile.report.paid_key_missing_or_revoked.map((o) => (
                <Alert key={o.id} variant="destructive">
                  <AlertTitle>broken: {o.provider_order_id}</AlertTitle>
                  <AlertDescription>order is paid but its key is missing or revoked — reissue or investigate.</AlertDescription>
                </Alert>
              ))}
              {reconcile.report.keys_without_order.map((k) => (
                <Alert key={k.id}>
                  <AlertTitle>orphan key: {shortHash(k.id, 8)}</AlertTitle>
                  <AlertDescription>
                    created by {k.created_by} with no order row — manual issuance or event-log drift.
                  </AlertDescription>
                </Alert>
              ))}
            </div>
          )}
        </TabsContent>
      </Tabs>
    </div>
  );
}

function error0(err: string | null, actionErr: string | null): React.JSX.Element | null {
  if (!err && !actionErr) return null;
  return (
    <Alert variant="destructive">
      <AlertTitle>{err ? "API error" : "Action failed"}</AlertTitle>
      <AlertDescription>{err ?? actionErr}</AlertDescription>
    </Alert>
  );
}

function ReconcileStat({ icon, label, value, bad }: { icon: React.ReactNode; label: string; value: number; bad: boolean }): React.JSX.Element {
  return (
    <div className="flex items-center gap-3 rounded-lg border p-3">
      <div className={`flex h-9 w-9 items-center justify-center rounded-md ${bad ? "bg-rose-100 text-rose-700 dark:bg-rose-950 dark:text-rose-300" : "bg-emerald-100 text-emerald-700 dark:bg-emerald-950 dark:text-emerald-300"}`}>
        {icon}
      </div>
      <div>
        <p className="text-xl font-semibold tabular-nums leading-none">{value}</p>
        <p className="text-xs text-muted-foreground">{label}</p>
      </div>
    </div>
  );
}
