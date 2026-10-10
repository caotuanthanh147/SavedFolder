"use client";

import { useMemo, useState } from "react";
import { Alert, AlertDescription, AlertTitle } from "@/components/ui/alert";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Skeleton } from "@/components/ui/skeleton";
import { FreshnessPill } from "@/components/dashboard/freshness";
import { ActionBadge, categorize, relTime } from "@/components/dashboard/audit";
import { TierBadge } from "@/components/dashboard/badges";
import { ActivityBarChart, DonutChart, Sparkline, Meter } from "@/components/dashboard/charts";
import { AnalyticsOverview, AuditEntry, KeyRow, NodeRow, ProtocolVersionRow, SyncData, gw, formatTime } from "@/lib/api";
import { useApiData } from "@/lib/use-api-data";
import { ArrowDownRight, ArrowUpRight, Activity, CalendarClock, CheckCircle2, History, KeyRound, Server, ShieldAlert, TrendingUp, Users, Zap } from "lucide-react";

interface OverviewData {
  analytics: AnalyticsOverview;
  sync: SyncData;
  nodes: NodeRow[];
  protocols: ProtocolVersionRow[];
  audit: AuditEntry[];
  keys: KeyRow[];
}

const DAY = 86400;

function dayKey(unix: number, now: number): number {
  return Math.floor((now - unix) / DAY);
}

// KPI drilldown targets (page.tsx `go` — typed independently to avoid a
// circular import with the view-id union).
export type DrilldownView = "keys" | "sessions" | "audit" | "leak";

export function OverviewView({ onNavigate }: { onNavigate?: (v: DrilldownView) => void }): React.JSX.Element {
  const [copied, setCopied] = useState(false);
  const { data, prevData, error, refresh, lastUpdatedAt } = useApiData<OverviewData>(async () => {
    const [analytics, sync, nodes, protocols, audit, keys] = await Promise.all([
      gw<AnalyticsOverview>("GET", "/admin/analytics/overview"),
      gw<SyncData>("GET", "/sync"),
      gw<{ rows: NodeRow[] }>("GET", "/admin/nodes").then((r) => r.rows),
      gw<{ rows: ProtocolVersionRow[] }>("GET", "/admin/protocol-versions").then((r) => r.rows),
      gw<{ entries: AuditEntry[] }>("GET", "/admin/audit?limit=200").then((r) => r.entries),
      gw<{ rows: KeyRow[] }>("GET", "/admin/keys?limit=500").then((r) => r.rows),
    ]);
    return { analytics, sync, nodes, protocols, audit, keys };
  }, [], { pollMs: 15000 });

  // 14-day chart series, computed from real rows. "now" comes from the
  // server /sync timestamp (pure per fetched data — no Date.now() in render).
  const charts = useMemo(() => {
    if (!data) return null;
    const now = data.sync.st;
    const days = Array.from({ length: 14 }, (_, i) => 13 - i);
    const labels = days.map((d) => {
      const dt = new Date((now - d * DAY) * 1000);
      return `${dt.getMonth() + 1}/${dt.getDate()}`;
    });

    const series = (match: (a: string) => boolean): number[] =>
      days.map(
        (d) => data.audit.filter((e) => dayKey(e.created_at, now) === d && match(e.action)).length,
      );

    const keySeries = series((a) => a.startsWith("key."));
    const paymentSeries = series((a) => a.startsWith("payment."));
    const freeSeries = series((a) => a.includes("free"));
    const securitySeries = series((a) => a.startsWith("blacklist") || a.startsWith("hwid") || a.startsWith("session"));

    const totals = days.map((d) =>
      data.audit.filter((e) => dayKey(e.created_at, now) === d).length,
    );
    const points = days.map((d, i) => ({
      label: labels[i]!,
      sublabel: new Date((now - d * DAY) * 1000).toLocaleDateString(undefined, { weekday: "short", month: "short", day: "numeric" }),
      value: totals[i] ?? 0,
    }));

    // Tier distribution across all fetched keys
    const tiers = new Map<string, number>();
    for (const k of data.keys) tiers.set(k.tier, (tiers.get(k.tier) ?? 0) + 1);
    const segments = ["paid", "lifetime", "free", "reseller"]
      .map((name) => ({ name, value: tiers.get(name) ?? 0 }))
      .filter((s) => s.value > 0);

    // Keys created per day (sparkline)
    const keysPerDay = days.map((d) => data.keys.filter((k) => dayKey(k.created_at, now) === d).length);

    // Validations split (last 24h)
    const ok = data.analytics.validate_ok_24h;
    const fail = data.analytics.validate_fail_24h;

    return { labels, keySeries, paymentSeries, freeSeries, securitySeries, points, segments, keysPerDay, ok, fail };
  }, [data]);

  if (error) {
    return (
      <Alert variant="destructive">
        <ShieldAlert className="h-4 w-4" />
        <AlertTitle>API error</AlertTitle>
        <AlertDescription>{error}</AlertDescription>
      </Alert>
    );
  }
  if (!data || !charts) {
    return (
      <div className="space-y-4">
        <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
          {Array.from({ length: 4 }).map((_, i) => (
            <Skeleton key={i} className="skeleton-shimmer h-32" />
          ))}
        </div>
        <div className="grid gap-4 lg:grid-cols-3">
          <Skeleton className="skeleton-shimmer h-72 lg:col-span-2" />
          <Skeleton className="skeleton-shimmer h-72" />
        </div>
      </div>
    );
  }

  const a = data.analytics;
  const totalValidations = a.validate_ok_24h + a.validate_fail_24h;

  // Poll-over-poll deltas (24h rolling window movement vs the previous
  // snapshot). Direction semantics are per-metric: tamper up is BAD, the
  // other three up are good.
  function deltaOf(prev: number | undefined, cur: number, upIsGood: boolean): { value: number; good: boolean } | undefined {
    if (prev === undefined) return undefined;
    const d = cur - prev;
    if (d === 0) return undefined;
    return { value: d, good: d > 0 ? upIsGood : !upIsGood };
  }
  const deltas: Record<string, { value: number; good: boolean } | undefined> = {
    active: deltaOf(prevData?.analytics?.keys_active, a.keys_active, true),
    sessions: deltaOf(prevData?.analytics?.sessions_24h, a.sessions_24h, true),
    validations: deltaOf(prevData?.analytics?.validate_ok_24h, a.validate_ok_24h, true),
    tamper: deltaOf(prevData?.analytics?.tamper_24h, a.tamper_24h, false),
  };

  const stats: {
    label: string;
    value: number;
    icon: React.ReactNode;
    hint: React.ReactNode;
    spark: number[];
    accent: string;
    stroke: string;
    drill?: DrilldownView;
    delta?: { value: number; good: boolean };
  }[] = [
    {
      label: "Active keys",
      value: a.keys_active,
      icon: <KeyRound className="h-4 w-4" />,
      hint: `${a.keys_revoked} revoked`,
      spark: charts.keysPerDay,
      accent: "from-emerald-500 to-teal-600",
      stroke: "#10b981",
      drill: "keys",
      delta: deltas.active,
    },
    {
      label: "Sessions (24h)",
      value: a.sessions_24h,
      icon: <Users className="h-4 w-4" />,
      hint: `${a.sessions_live} live now`,
      spark: charts.keySeries.map((v, i) => v + charts.freeSeries[i]!),
      accent: "from-teal-500 to-emerald-600",
      stroke: "#14b8a6",
      drill: "sessions",
      delta: deltas.sessions,
    },
    {
      label: "Validations OK (24h)",
      value: a.validate_ok_24h,
      icon: <CheckCircle2 className="h-4 w-4" />,
      hint: totalValidations === 0 ? "no traffic yet" : `${Math.round((a.validate_ok_24h / totalValidations) * 100)}% pass rate`,
      spark: charts.keySeries,
      accent: "from-lime-500 to-emerald-600",
      stroke: "#84cc16",
      delta: deltas.validations,
    },
    {
      label: "Tamper events (24h)",
      value: a.tamper_24h,
      icon: <ShieldAlert className="h-4 w-4" />,
      hint: "leak/abuse signals",
      spark: charts.securitySeries,
      accent: "from-amber-500 to-rose-600",
      stroke: "#f59e0b",
      drill: "leak",
      delta: deltas.tamper,
    },
  ];

  // Ops watchlists, computed from already-fetched rows (zero new requests).
  // Plain computation (no hook) — this code runs below the loading guard.
  const recentActivity = data.audit.slice(0, 8);
  const expiringSoon = data.keys
    .filter((k) => k.status === "active" && k.expires_at !== null && k.expires_at - data.sync.st <= 7 * 86400)
    .sort((x, y) => (x.expires_at ?? 0) - (y.expires_at ?? 0))
    .slice(0, 6);

  return (
    <div className="space-y-6">
      {/* live freshness + stat cards */}
      {onNavigate !== undefined && (
        <div className="flex items-center justify-between">
          <p className="flex items-center gap-1.5 text-xs text-muted-foreground">
            <Activity className="h-3.5 w-3.5 text-emerald-600 dark:text-emerald-400" aria-hidden />
            Live analytics from the real /admin/analytics/overview endpoint — stat cards drill down.
          </p>
          <FreshnessPill lastUpdatedAt={lastUpdatedAt} onRefresh={refresh} pollMs={15000} />
        </div>
      )}
      <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
        {stats.map((s) => {
          const drillable = s.drill !== undefined && onNavigate !== undefined;
          return (
          <Card
            key={s.label}
            className={`group relative overflow-hidden pt-0 transition-all hover:-translate-y-0.5 hover:shadow-md ${
              drillable ? "cursor-pointer hover:ring-1 hover:ring-emerald-500/40" : ""
            }`}
            onClick={drillable ? () => onNavigate(s.drill as DrilldownView) : undefined}
            role={drillable ? "button" : undefined}
            tabIndex={drillable ? 0 : undefined}
            aria-label={drillable ? `${s.label}: ${s.value} — open the ${s.drill} view` : undefined}
            onKeyDown={
              drillable
                ? (e) => {
                    if (e.key === "Enter" || e.key === " ") {
                      e.preventDefault();
                      onNavigate(s.drill as DrilldownView);
                    }
                  }
                : undefined
            }
          >
            <div className={`h-1 w-full bg-gradient-to-r ${s.accent}`} aria-hidden />
            <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-1">
              <CardTitle className="text-xs font-medium uppercase tracking-wide text-muted-foreground">{s.label}</CardTitle>
              <div className="flex h-7 w-7 items-center justify-center rounded-md bg-gradient-to-br ${s.accent} text-white shadow-sm">
                {s.icon}
              </div>
            </CardHeader>
            <CardContent className="pb-3">
              <div className="flex items-baseline gap-2">
                <div className="text-3xl font-semibold tabular-nums leading-none">{s.value}</div>
                {s.delta && (
                  <span
                    className={`delta-pop inline-flex items-center gap-0.5 rounded-full px-1.5 py-0.5 text-[10px] font-semibold tabular-nums ${
                      s.delta.good
                        ? "bg-emerald-500/15 text-emerald-700 dark:text-emerald-300"
                        : "bg-rose-500/15 text-rose-700 dark:text-rose-300"
                    }`}
                    title="change since the previous poll (24h rolling window)"
                  >
                    {s.delta.value > 0 ? <ArrowUpRight className="h-3 w-3" aria-hidden /> : <ArrowDownRight className="h-3 w-3" aria-hidden />}
                    {s.delta.value > 0 ? "+" : ""}
                    {s.delta.value}
                  </span>
                )}
              </div>
              <p className="mt-1.5 text-xs text-muted-foreground">{s.hint}</p>
              <div className="mt-2 opacity-80">
                <Sparkline values={s.spark} stroke={s.stroke} fill={s.stroke} />
              </div>
            </CardContent>
            {drillable && (
              <span
                className="absolute right-3 top-3 flex h-5 w-5 items-center justify-center rounded-md bg-background/80 text-muted-foreground opacity-0 shadow-sm transition-opacity group-hover:opacity-100"
                aria-hidden
              >
                <ArrowUpRight className="h-3.5 w-3.5" />
              </span>
            )}
          </Card>
          );
        })}
      </div>

      {/* charts row */}
      <div className="grid gap-4 lg:grid-cols-3">
        <Card className="lg:col-span-2">
          <CardHeader className="flex flex-row items-center justify-between">
            <CardTitle className="flex items-center gap-2 text-base">
              <Activity className="h-4 w-4 text-emerald-600" /> Platform activity
              <Badge variant="secondary" className="text-[10px]">14 days</Badge>
            </CardTitle>
            <div className="flex items-center gap-3 text-[11px] text-muted-foreground">
              <span className="flex items-center gap-1"><span className="inline-block h-2 w-2 rounded-sm bg-emerald-500" /> keys</span>
              <span className="flex items-center gap-1"><span className="inline-block h-2 w-2 rounded-sm" style={{ background: "var(--color-chart-1)" }} /> payments</span>
              <span className="flex items-center gap-1"><span className="inline-block h-2 w-2 rounded-sm" style={{ background: "var(--color-chart-4)" }} /> free flow</span>
              <span className="flex items-center gap-1"><span className="inline-block h-2 w-2 rounded-sm" style={{ background: "var(--color-chart-5)" }} /> security</span>
            </div>
          </CardHeader>
          <CardContent>
            <ActivityBarChart
              data={charts.points}
              series={[
                { name: "keys", values: charts.keySeries },
                { name: "payments", values: charts.paymentSeries },
                { name: "free flow", values: charts.freeSeries },
                { name: "security", values: charts.securitySeries },
              ]}
            />
            <p className="mt-2 text-xs text-muted-foreground">
              Stacked audit-log actions per day, bucketed client-side from <code className="rounded bg-muted px-1 py-0.5 font-mono text-[10px]">GET /admin/audit?limit=200</code>.
            </p>
          </CardContent>
        </Card>

        <Card>
          <CardHeader>
            <CardTitle className="flex items-center gap-2 text-base">
              <TrendingUp className="h-4 w-4 text-emerald-600" /> Key tiers
            </CardTitle>
          </CardHeader>
          <CardContent>
            <DonutChart segments={charts.segments} centerLabel="keys" centerValue={data.keys.length} />
            <div className="mt-4 rounded-md border border-dashed p-2.5">
              <p className="flex items-center gap-1.5 text-xs text-muted-foreground">
                <Zap className="h-3.5 w-3.5 text-amber-500" />
                <span>
                  <span className="font-semibold text-foreground">{charts.keysPerDay[13] ?? 0}</span> new today ·
                  live from <code className="mx-0.5 rounded bg-muted px-1 font-mono text-[10px]">/admin/keys</code>
                </span>
              </p>
            </div>
          </CardContent>
        </Card>
      </div>

      {/* infra + validation health row */}
      <div className="grid gap-4 lg:grid-cols-3">
        <Card>
          <CardHeader>
            <CardTitle className="flex items-center gap-2 text-base">
              <Server className="h-4 w-4" /> Auth nodes
            </CardTitle>
          </CardHeader>
          <CardContent className="space-y-2">
            {data.nodes.map((n) => (
              <div key={n.id} className="flex items-center justify-between rounded-md border p-2 transition-colors hover:bg-muted/50">
                <div>
                  <p className="font-mono text-sm">{n.hostname}</p>
                  <p className="text-xs text-muted-foreground">{n.region ?? "global"}</p>
                </div>
                <Badge variant={n.active ? "default" : "secondary"} className={n.active ? "gap-1 bg-emerald-600 hover:bg-emerald-600" : ""}>
                  {n.active && <span className="pulse-dot relative inline-flex h-1.5 w-1.5 rounded-full bg-white" aria-hidden />}
                  {n.active ? "active" : "disabled"}
                </Badge>
              </div>
            ))}
            <div className="flex items-center justify-between rounded-md border p-2">
              <div>
                <p className="text-sm font-medium">/sync</p>
                <p className="text-xs text-muted-foreground">server time · colo</p>
              </div>
              <div className="flex items-center gap-2">
                <Badge variant="outline" className="font-mono">{data.sync.colo || "—"}</Badge>
                <Button
                  variant="ghost"
                  size="sm"
                  onClick={() => {
                    void navigator.clipboard.writeText(String(data.sync.st)).then(() => {
                      setCopied(true);
                      setTimeout(() => setCopied(false), 1500);
                    });
                  }}
                >
                  {copied ? "copied" : new Date(data.sync.st * 1000).toLocaleTimeString()}
                </Button>
              </div>
            </div>
          </CardContent>
        </Card>

        <Card>
          <CardHeader>
            <CardTitle className="flex items-center gap-2 text-base">
              <Zap className="h-4 w-4" /> Validation health (24h)
            </CardTitle>
          </CardHeader>
          <CardContent className="space-y-3">
            <div className="flex items-end justify-between">
              <div>
                <p className="text-3xl font-semibold tabular-nums leading-none">{totalValidations}</p>
                <p className="mt-1 text-xs text-muted-foreground">total validations</p>
              </div>
              <div className="text-right text-xs">
                <p className="font-medium text-emerald-600 dark:text-emerald-400">{a.validate_ok_24h} ok</p>
                <p className="font-medium text-rose-600 dark:text-rose-400">{a.validate_fail_24h} failed</p>
              </div>
            </div>
            <Meter value={a.validate_ok_24h} max={totalValidations} />
            <p className="text-xs leading-relaxed text-muted-foreground">
              Failed validations are blocked before key lookup and lock out repeat offenders (5 fails / 10 min).
            </p>
          </CardContent>
        </Card>

        <Card>
          <CardHeader>
            <CardTitle className="flex items-center gap-2 text-base">
              <TrendingUp className="h-4 w-4" /> Protocol versions
            </CardTitle>
          </CardHeader>
          <CardContent className="space-y-2">
            {data.protocols.map((p) => (
              <div key={p.version} className="flex items-center justify-between rounded-md border p-2">
                <div>
                  <p className="font-mono text-sm">v{p.version}</p>
                  <p className="text-xs text-muted-foreground">handler {p.handler} · min loader {p.min_loader ?? "any"}</p>
                </div>
                <Badge variant={p.active ? "default" : "secondary"}>{p.active ? "active" : "retired"}</Badge>
              </div>
            ))}
            <p className="text-xs text-muted-foreground">
              Retiring every row = kill switch for its handler class (doc §19). Rendered at {formatTime(data.sync.st)} from the real /sync endpoint.
            </p>
          </CardContent>
        </Card>
      </div>

      {/* ops row: recent audit timeline + expiring-soon watchlist (both derived
          from rows already fetched above — zero extra requests) */}
      <div className="grid gap-4 lg:grid-cols-3">
        <Card className="lg:col-span-2">
          <CardHeader className="flex flex-row items-center justify-between">
            <CardTitle className="flex items-center gap-2 text-base">
              <History className="h-4 w-4" /> Recent activity
            </CardTitle>
            <Badge variant="secondary" className="text-[10px]">
              last {recentActivity.length} of {data.audit.length} audit entries
            </Badge>
          </CardHeader>
          <CardContent>
            <ol className="relative space-y-0 border-l border-border/70 pl-4">
              {recentActivity.map((e) => {
                const cat = categorize(e.action);
                return (
                <li key={e.id} className="relative py-1.5 transition-colors hover:bg-muted/40 hover:rounded-r-md">
                  <span
                    className={`timeline-dot absolute -left-[21px] top-1/2 mt-[-3px] h-1.5 w-1.5 rounded-full ${
                      cat === "key"
                        ? "timeline-cat-keys"
                        : cat === "payment"
                          ? "timeline-cat-payments"
                          : cat === "free"
                            ? "timeline-cat-free"
                            : cat === "security"
                              ? "timeline-cat-security"
                              : cat === "script"
                                ? "timeline-cat-script"
                                : ""
                    }`}
                    aria-hidden
                  />
                  <div className="flex flex-wrap items-center gap-2">
                    <span className="w-16 shrink-0 text-[11px] tabular-nums text-muted-foreground" title={formatTime(e.created_at)}>
                      {relTime(e.created_at)}
                    </span>
                    <ActionBadge action={e.action} />
                    {e.target && <span className="font-mono text-[11px] text-muted-foreground">{e.target.slice(0, 10)}…</span>}
                  </div>
                </li>
                );
              })}
            </ol>
            <p className="mt-3 text-xs text-muted-foreground">
              From the same <code className="rounded bg-muted px-1 py-0.5 font-mono text-[10px]">GET /admin/audit?limit=200</code> fetch that powers the activity chart — the full Audit log view has filters and CSV.
            </p>
          </CardContent>
        </Card>

        <Card>
          <CardHeader className="flex flex-row items-center justify-between">
            <CardTitle className="flex items-center gap-2 text-base">
              <CalendarClock className="h-4 w-4" /> Expiring soon
            </CardTitle>
            <Badge variant="secondary" className="text-[10px]">≤ 7 days</Badge>
          </CardHeader>
          <CardContent className="space-y-2">
            {expiringSoon.length === 0 ? (
              <div className="flex flex-col items-center justify-center gap-2 py-8 text-center">
                <div className="flex h-10 w-10 items-center justify-center rounded-full bg-muted">
                  <CalendarClock className="h-5 w-5 text-muted-foreground" />
                </div>
                <p className="text-sm font-medium">No keys expiring this week</p>
                <p className="text-xs text-muted-foreground">Lifetime keys never expire; actives renew via Extend.</p>
              </div>
            ) : (
              <>
                {expiringSoon.map((k) => {
                  const daysLeft = Math.ceil(((k.expires_at ?? 0) - data.sync.st) / 86400);
                  return (
                    <div key={k.id} className="flex items-center justify-between gap-2 rounded-md border p-2 transition-colors hover:bg-muted/50">
                      <div className="min-w-0">
                        <p className="truncate font-mono text-xs">{k.id.slice(0, 14)}…</p>
                        <p className="text-[11px] text-muted-foreground">{k.note ?? k.tier}</p>
                      </div>
                      <div className="flex shrink-0 items-center gap-1.5">
                        <TierBadge tier={k.tier} />
                        <Badge
                          variant="outline"
                          className={`tabular-nums ${
                            daysLeft <= 3
                              ? "border-rose-600/40 bg-rose-600/10 text-rose-700 dark:text-rose-300"
                              : "border-amber-600/40 bg-amber-600/10 text-amber-700 dark:text-amber-300"
                          }`}
                        >
                          {daysLeft <= 0 ? "today" : `${daysLeft}d`}
                        </Badge>
                      </div>
                    </div>
                  );
                })}
                <p className="text-xs text-muted-foreground">
                  Active keys with <code className="rounded bg-muted px-1 font-mono text-[10px]">expires_at</code> within 7 days — extend from the key detail dialog (PATCH /admin/keys/:id).
                </p>
              </>
            )}
          </CardContent>
        </Card>
      </div>
    </div>
  );
}
