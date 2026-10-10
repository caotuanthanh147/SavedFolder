"use client";

import { useEffect, useMemo, useState } from "react";
import { Alert, AlertDescription, AlertTitle } from "@/components/ui/alert";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Skeleton } from "@/components/ui/skeleton";
import { ActivityBarChart, DonutChart, Sparkline, Meter } from "@/components/dashboard/charts";
import { AnalyticsOverview, AuditEntry, KeyRow, NodeRow, ProtocolVersionRow, SyncData, gw, formatTime } from "@/lib/api";
import { useApiData } from "@/lib/use-api-data";
import { Activity, CheckCircle2, KeyRound, Server, ShieldAlert, TrendingUp, Users, Zap } from "lucide-react";

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

export function OverviewView(): React.JSX.Element {
  const [copied, setCopied] = useState(false);
  const { data, error, refresh } = useApiData<OverviewData>(async () => {
    const [analytics, sync, nodes, protocols, audit, keys] = await Promise.all([
      gw<AnalyticsOverview>("GET", "/admin/analytics/overview"),
      gw<SyncData>("GET", "/sync"),
      gw<{ rows: NodeRow[] }>("GET", "/admin/nodes").then((r) => r.rows),
      gw<{ rows: ProtocolVersionRow[] }>("GET", "/admin/protocol-versions").then((r) => r.rows),
      gw<{ entries: AuditEntry[] }>("GET", "/admin/audit?limit=200").then((r) => r.entries),
      gw<{ rows: KeyRow[] }>("GET", "/admin/keys?limit=500").then((r) => r.rows),
    ]);
    return { analytics, sync, nodes, protocols, audit, keys };
  }, []);

  useEffect(() => {
    const timer = setInterval(() => refresh(), 15000);
    return () => clearInterval(timer);
  }, [refresh]);

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
  const stats: {
    label: string;
    value: number;
    icon: React.ReactNode;
    hint: React.ReactNode;
    spark: number[];
    accent: string;
    stroke: string;
  }[] = [
    {
      label: "Active keys",
      value: a.keys_active,
      icon: <KeyRound className="h-4 w-4" />,
      hint: `${a.keys_revoked} revoked`,
      spark: charts.keysPerDay,
      accent: "from-emerald-500 to-teal-600",
      stroke: "#10b981",
    },
    {
      label: "Sessions (24h)",
      value: a.sessions_24h,
      icon: <Users className="h-4 w-4" />,
      hint: `${a.sessions_live} live now`,
      spark: charts.keySeries.map((v, i) => v + charts.freeSeries[i]!),
      accent: "from-teal-500 to-emerald-600",
      stroke: "#14b8a6",
    },
    {
      label: "Validations OK (24h)",
      value: a.validate_ok_24h,
      icon: <CheckCircle2 className="h-4 w-4" />,
      hint: totalValidations === 0 ? "no traffic yet" : `${Math.round((a.validate_ok_24h / totalValidations) * 100)}% pass rate`,
      spark: charts.keySeries,
      accent: "from-lime-500 to-emerald-600",
      stroke: "#84cc16",
    },
    {
      label: "Tamper events (24h)",
      value: a.tamper_24h,
      icon: <ShieldAlert className="h-4 w-4" />,
      hint: "leak/abuse signals",
      spark: charts.securitySeries,
      accent: "from-amber-500 to-rose-600",
      stroke: "#f59e0b",
    },
  ];

  return (
    <div className="space-y-6">
      {/* stat cards */}
      <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
        {stats.map((s) => (
          <Card key={s.label} className="group relative overflow-hidden pt-0 transition-all hover:-translate-y-0.5 hover:shadow-md">
            <div className={`h-1 w-full bg-gradient-to-r ${s.accent}`} aria-hidden />
            <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-1">
              <CardTitle className="text-xs font-medium uppercase tracking-wide text-muted-foreground">{s.label}</CardTitle>
              <div className={`flex h-7 w-7 items-center justify-center rounded-md bg-gradient-to-br ${s.accent} text-white shadow-sm`}>
                {s.icon}
              </div>
            </CardHeader>
            <CardContent className="pb-3">
              <div className="text-3xl font-semibold tabular-nums leading-none">{s.value}</div>
              <p className="mt-1.5 text-xs text-muted-foreground">{s.hint}</p>
              <div className="mt-2 opacity-80">
                <Sparkline values={s.spark} stroke={s.stroke} fill={s.stroke} />
              </div>
            </CardContent>
          </Card>
        ))}
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
    </div>
  );
}
