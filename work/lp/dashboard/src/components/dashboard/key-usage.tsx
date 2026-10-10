"use client";

// Key usage analytics (M11 s11): inline panel for the key detail dialog.
// Fetches the key's session rows through the real CCP-2 read endpoint
// (GET /admin/sessions?key_id=…&limit=200) plus the /sync server clock and
// derives a 14-day sessions-per-day sparkline and a stats grid — all pure
// data-derived (st time base, no Date.now() in render).

import { useMemo } from "react";
import { Skeleton } from "@/components/ui/skeleton";
import { Sparkline } from "@/components/dashboard/charts";
import { gw, SessionRow, SyncData, formatTime, shortHash } from "@/lib/api";
import { useApiData } from "@/lib/use-api-data";

const DAY = 86400;

function dayKey(unix: number, now: number): number {
  return Math.floor((now - unix) / DAY);
}

export function KeyUsagePanel({ keyId }: { keyId: string }): React.JSX.Element {
  const { data, error } = useApiData(async () => {
    const [s, sync] = await Promise.all([
      gw<{ rows: SessionRow[]; total: number }>("GET", `/admin/sessions?key_id=${encodeURIComponent(keyId)}&limit=200`),
      gw<SyncData>("GET", "/sync"),
    ]);
    return { rows: s.rows, total: s.total, st: sync.st };
  }, [keyId]);

  const stats = useMemo(() => {
    if (!data) return null;
    const now = data.st;
    // 14 day buckets, oldest → newest, indexed like the Overview chart.
    const perDay = Array.from({ length: 14 }, (_, i) => 13 - i).map(
      (d) => data.rows.filter((r) => dayKey(r.created_at, now) === d).length,
    );
    const hwids = new Set(data.rows.map((r) => r.hwid_hash));
    const places = new Set(data.rows.filter((r) => r.place_id !== null).map((r) => r.place_id));
    const scripts = new Map<string, number>();
    for (const r of data.rows) scripts.set(r.script_id, (scripts.get(r.script_id) ?? 0) + 1);
    const topScript = [...scripts.entries()].sort((a, b) => b[1] - a[1])[0] ?? null;
    const last = data.rows.length > 0 ? data.rows.reduce((m, r) => Math.max(m, r.created_at), 0) : null;
    return {
      perDay,
      liveNow: data.rows.filter((r) => r.expires_at > now).length,
      hwids: hwids.size,
      places: places.size,
      topScript,
      last,
    };
  }, [data]);

  if (error) {
    return (
      <div className="rounded-md border border-dashed px-3 py-2">
        <p className="text-xs text-muted-foreground">usage unavailable — {error}</p>
      </div>
    );
  }
  if (!data || !stats) {
    return (
      <div className="rounded-md border border-dashed px-3 py-2">
        <p className="mb-2 text-[11px] font-medium uppercase tracking-wider text-muted-foreground">Usage · last 14 days</p>
        <Skeleton className="skeleton-shimmer h-8 w-full" />
      </div>
    );
  }

  const grid: { label: string; value: string }[] = [
    { label: "listed", value: String(data.rows.length) + (data.total > data.rows.length ? ` of ${data.total}` : "") },
    { label: "live now", value: String(stats.liveNow) },
    { label: "hwids", value: String(stats.hwids) },
    { label: "places", value: String(stats.places) },
    { label: "top script", value: stats.topScript ? `${shortHash(stats.topScript[0], 6)} ×${stats.topScript[1]}` : "—" },
    { label: "last activity", value: stats.last !== null ? formatTime(stats.last) : "never" },
  ];

  return (
    <div className="rounded-md border border-dashed px-3 py-2">
      <div className="mb-1 flex items-center justify-between">
        <p className="text-[11px] font-medium uppercase tracking-wider text-muted-foreground">Usage · last 14 days</p>
        <p className="text-[10px] tabular-nums text-muted-foreground">
          {stats.perDay.reduce((a, b) => a + b, 0)} sessions in window
        </p>
      </div>
      {stats.perDay.reduce((a, b) => a + b, 0) === 0 ? (
        <p className="py-1.5 text-xs text-muted-foreground">No sessions in the window — the sparkline appears on first use.</p>
      ) : (
        <Sparkline values={stats.perDay} stroke="#10b981" fill="#10b981" />
      )}
      <div className="mt-1.5 grid grid-cols-3 gap-x-3 gap-y-1">
        {grid.map((g) => (
          <div key={g.label} className="min-w-0">
            <p className="truncate text-[10px] uppercase tracking-wide text-muted-foreground/80" title={g.value}>
              {g.label}
            </p>
            <p className="truncate text-xs font-medium tabular-nums" title={g.value}>
              {g.value}
            </p>
          </div>
        ))}
      </div>
    </div>
  );
}
