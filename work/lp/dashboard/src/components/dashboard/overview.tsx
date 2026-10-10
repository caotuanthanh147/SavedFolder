"use client";

import { useEffect, useState } from "react";
import { Alert, AlertDescription, AlertTitle } from "@/components/ui/alert";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Skeleton } from "@/components/ui/skeleton";
import { AnalyticsOverview, NodeRow, ProtocolVersionRow, SyncData, gw, formatTime } from "@/lib/api";
import { useApiData } from "@/lib/use-api-data";
import { Activity, CheckCircle2, KeyRound, Server, ShieldAlert, Users } from "lucide-react";

interface OverviewData {
  analytics: AnalyticsOverview;
  sync: SyncData;
  nodes: NodeRow[];
  protocols: ProtocolVersionRow[];
  freeEvents: { type: string; detail: string; created_at: number }[];
}

export function OverviewView(): React.JSX.Element {
  const [copied, setCopied] = useState(false);
  const { data, error, refresh } = useApiData<OverviewData>(async () => {
    const [analytics, sync, nodes, protocols] = await Promise.all([
      gw<AnalyticsOverview>("GET", "/admin/analytics/overview"),
      gw<SyncData>("GET", "/sync"),
      gw<{ rows: NodeRow[] }>("GET", "/admin/nodes").then((r) => r.rows),
      gw<{ rows: ProtocolVersionRow[] }>("GET", "/admin/protocol-versions").then((r) => r.rows),
    ]);
    return { analytics, sync, nodes, protocols, freeEvents: [] };
  }, []);

  useEffect(() => {
    const timer = setInterval(() => refresh(), 15000);
    return () => clearInterval(timer);
  }, [refresh]);

  if (error) {
    return (
      <Alert variant="destructive">
        <ShieldAlert className="h-4 w-4" />
        <AlertTitle>API error</AlertTitle>
        <AlertDescription>{error}</AlertDescription>
      </Alert>
    );
  }
  if (!data) {
    return (
      <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
        {Array.from({ length: 8 }).map((_, i) => (
          <Skeleton key={i} className="h-28" />
        ))}
      </div>
    );
  }

  const a = data.analytics;
  const stats: { label: string; value: number; icon: React.ReactNode; hint: string }[] = [
    { label: "Active keys", value: a.keys_active, icon: <KeyRound className="h-4 w-4" />, hint: `${a.keys_revoked} revoked` },
    { label: "Sessions (24h)", value: a.sessions_24h, icon: <Users className="h-4 w-4" />, hint: `${a.sessions_live} live now` },
    { label: "Validations OK (24h)", value: a.validate_ok_24h, icon: <CheckCircle2 className="h-4 w-4" />, hint: `${a.validate_fail_24h} failed` },
    { label: "Tamper events (24h)", value: a.tamper_24h, icon: <ShieldAlert className="h-4 w-4" />, hint: "leak/abuse signals" },
  ];

  return (
    <div className="space-y-6">
      <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
        {stats.map((s) => (
          <Card key={s.label}>
            <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
              <CardTitle className="text-sm font-medium text-muted-foreground">{s.label}</CardTitle>
              {s.icon}
            </CardHeader>
            <CardContent>
              <div className="text-3xl font-semibold tabular-nums">{s.value}</div>
              <p className="mt-1 text-xs text-muted-foreground">{s.hint}</p>
            </CardContent>
          </Card>
        ))}
      </div>

      <div className="grid gap-4 lg:grid-cols-3">
        <Card>
          <CardHeader>
            <CardTitle className="flex items-center gap-2 text-base">
              <Server className="h-4 w-4" /> Auth nodes
            </CardTitle>
          </CardHeader>
          <CardContent className="space-y-2">
            {data.nodes.map((n) => (
              <div key={n.id} className="flex items-center justify-between rounded-md border p-2">
                <div>
                  <p className="font-mono text-sm">{n.hostname}</p>
                  <p className="text-xs text-muted-foreground">{n.region ?? "global"}</p>
                </div>
                <Badge variant={n.active ? "default" : "secondary"}>{n.active ? "active" : "disabled"}</Badge>
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
              <Activity className="h-4 w-4" /> Protocol versions
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
              Retiring every row = kill switch for its handler class (doc §19).
            </p>
          </CardContent>
        </Card>

        <Card>
          <CardHeader>
            <CardTitle className="text-base">Window</CardTitle>
          </CardHeader>
          <CardContent className="space-y-2 text-sm text-muted-foreground">
            <p>
              Analytics window: <span className="font-medium text-foreground">{a.window}</span> (last 24 hours)
            </p>
            <p>
              Live sessions: <span className="font-medium text-foreground">{a.sessions_live}</span>
            </p>
            <p>
              Failed validations are blocked before key lookup and lock out repeat offenders (5 fails / 10 min).
            </p>
            <p>Rendered at {formatTime(data.sync.st)} from the real /sync endpoint.</p>
          </CardContent>
        </Card>
      </div>
    </div>
  );
}
