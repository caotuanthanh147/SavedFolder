"use client";

// FreshnessPill — live-ops affordance for polling views: "updated 4s ago"
// with a soft pulse while a poll is in flight, click = refresh now.
// Age ticks via a 1s interval; setState lives inside the interval callback
// (lint-safe). Mount-only rendering of "—" until the first settle.

import { useEffect, useState } from "react";
import { Loader2, RefreshCw } from "lucide-react";

function ageText(ms: number): string {
  const s = Math.max(0, Math.floor(ms / 1000));
  if (s < 60) return `${s}s ago`;
  const m = Math.floor(s / 60);
  if (m < 60) return `${m}m ago`;
  return `${Math.floor(m / 60)}h ago`;
}

export function FreshnessPill({
  lastUpdatedAt,
  onRefresh,
  pollMs,
  refreshing = false,
}: {
  lastUpdatedAt: number | null;
  onRefresh: () => void;
  pollMs?: number;
  refreshing?: boolean;
}): React.JSX.Element {
  const [now, setNow] = useState<number | null>(null);
  useEffect(() => {
    const timer = setInterval(() => setNow(Date.now()), 1000);
    return () => clearInterval(timer);
  }, []);

  const label =
    lastUpdatedAt === null || now === null ? "connecting…" : ageText(now - lastUpdatedAt);
  const stale = lastUpdatedAt !== null && now !== null && pollMs !== undefined && now - lastUpdatedAt > pollMs * 2;

  return (
    <button
      type="button"
      onClick={onRefresh}
      aria-label={`data refreshed ${label} — click to refresh now`}
      title={pollMs !== undefined ? `auto-refresh every ${Math.round(pollMs / 1000)}s — click to refresh now` : "click to refresh now"}
      className="inline-flex h-7 items-center gap-1.5 rounded-full border bg-muted/40 px-2.5 text-[11px] font-medium text-muted-foreground transition-colors hover:bg-muted hover:text-foreground focus-visible:ring-2 focus-visible:ring-ring/50"
    >
      {refreshing ? (
        <Loader2 className="h-3 w-3 animate-spin" aria-hidden />
      ) : (
        <RefreshCw className="h-3 w-3" aria-hidden />
      )}
      <span className={`tabular-nums ${stale ? "text-amber-600 dark:text-amber-400" : ""}`}>{label}</span>
      {pollMs !== undefined && (
        <span className={`relative inline-block h-1.5 w-1.5 rounded-full ${stale ? "bg-amber-500" : "pulse-dot bg-emerald-500"}`} aria-hidden />
      )}
    </button>
  );
}
