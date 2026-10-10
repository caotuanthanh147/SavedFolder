"use client";

import { useEffect, useState, useSyncExternalStore } from "react";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Kbd } from "@/components/ui/kbd";
import {
  clearApiLog,
  getApiLogSnapshot,
  getInflightSnapshot,
  subscribeApiLog,
  type ApiLogEntry,
} from "@/lib/api-log";
import { Activity, CircleSlash2, Loader2, Trash2, X } from "lucide-react";

function relMs(at: number): string {
  const d = Date.now() - at;
  if (d < 1000) return `${d}s`;
  if (d < 60000) return `${Math.floor(d / 1000)}s`;
  if (d < 3600000) return `${Math.floor(d / 60000)}m`;
  return `${Math.floor(d / 3600000)}h`;
}

function statusClass(status: number | null): string {
  if (status === null) return "bg-muted text-muted-foreground";
  if (status >= 500) return "bg-rose-600/15 text-rose-700 dark:text-rose-400";
  if (status >= 400) return "bg-amber-600/15 text-amber-700 dark:text-amber-400";
  if (status >= 200) return "bg-emerald-600/15 text-emerald-700 dark:text-emerald-400";
  return "bg-stone-500/15 text-stone-600 dark:text-stone-300";
}

const METHOD_STYLES: Record<string, string> = {
  GET: "text-emerald-600 dark:text-emerald-400",
  POST: "text-amber-600 dark:text-amber-400",
  PATCH: "text-teal-600 dark:text-teal-400",
};

export function useApiLog(): ApiLogEntry[] {
  return useSyncExternalStore(subscribeApiLog, getApiLogSnapshot, getApiLogSnapshot);
}

export function useInflight(): number {
  return useSyncExternalStore(subscribeApiLog, getInflightSnapshot, getInflightSnapshot);
}

/** Header button: opens the inspector; pulses while requests are in flight. */
export function ApiInspectorButton({ onClick }: { onClick: () => void }): React.JSX.Element {
  const inFlight = useInflight();
  const entries = useApiLog();
  const errors = entries.filter((e) => (e.status ?? 0) >= 400).length;
  return (
    <Button
      variant="ghost"
      size="icon"
      onClick={onClick}
      aria-label={`open API request inspector (${entries.length} logged, ${inFlight} in flight)`}
      title="API request inspector — every dashboard call through the real router"
      className="relative h-8 w-8"
    >
      <Activity className={`h-4 w-4 ${inFlight > 0 ? "text-emerald-600 dark:text-emerald-400" : ""}`} />
      {errors > 0 && (
        <span className="absolute -right-0.5 -top-0.5 flex h-3.5 min-w-3.5 items-center justify-center rounded-full bg-rose-600 px-0.5 text-[9px] font-semibold text-white">
          {errors > 9 ? "9+" : errors}
        </span>
      )}
      {inFlight > 0 && (
        <span className="absolute -bottom-0.5 -right-0.5 h-2 w-2 animate-pulse rounded-full bg-emerald-500" aria-hidden />
      )}
    </Button>
  );
}

/** Top progress bar: visible while any request is in flight. */
export function ApiProgressBar(): React.JSX.Element | null {
  const inFlight = useInflight();
  if (inFlight === 0) return null;
  return (
    <div className="fixed inset-x-0 top-0 z-[60] h-0.5 overflow-hidden" aria-hidden>
      <div className="h-full w-1/3 animate-[progress-slide_1.1s_ease-in-out_infinite] bg-gradient-to-r from-transparent via-emerald-500 to-transparent" />
    </div>
  );
}

/** Right-side slide-over with the live request log. */
export function ApiInspectorPanel({ open, onClose }: { open: boolean; onClose: () => void }): React.JSX.Element {
  const entries = useApiLog();
  const inFlight = useInflight();
  const [hidePolls, setHidePolls] = useState(false);

  useEffect(() => {
    if (!open) return;
    function onKey(e: KeyboardEvent): void {
      if (e.key === "Escape") onClose();
    }
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [open, onClose]);

  const shown = hidePolls ? entries.filter((e) => !(e.method === "GET" && (e.status ?? 0) < 400)) : entries;
  const okCount = entries.filter((e) => (e.status ?? 0) >= 200 && (e.status ?? 0) < 400).length;
  const errCount = entries.filter((e) => (e.status ?? 0) >= 400).length;
  const avgMs = (() => {
    const done = entries.filter((e) => e.ms !== null);
    if (done.length === 0) return null;
    return Math.round(done.reduce((a, e) => a + (e.ms ?? 0), 0) / done.length);
  })();

  return (
    <div className={`fixed inset-0 z-50 ${open ? "" : "pointer-events-none"}`} aria-hidden={!open}>
      {/* backdrop */}
      <div
        className={`absolute inset-0 bg-black/25 backdrop-blur-[2px] transition-opacity duration-200 ${open ? "opacity-100" : "opacity-0"}`}
        onClick={onClose}
      />
      {/* panel */}
      <aside
        role="dialog"
        aria-label="API request inspector"
        className={`absolute inset-y-0 right-0 flex w-full max-w-md flex-col border-l bg-background shadow-xl transition-transform duration-200 ease-out ${
          open ? "translate-x-0" : "translate-x-full"
        }`}
      >
        <div className="flex items-center justify-between border-b px-4 py-3">
          <div>
            <p className="flex items-center gap-2 text-sm font-semibold">
              <Activity className="h-4 w-4 text-emerald-600" /> API request inspector
            </p>
            <p className="text-xs text-muted-foreground">
              Live log of every dashboard call dispatched through the real api/ router
            </p>
          </div>
          <Button variant="ghost" size="icon" onClick={onClose} aria-label="close inspector">
            <X className="h-4 w-4" />
          </Button>
        </div>

        <div className="grid grid-cols-4 divide-x border-b bg-muted/30 text-center">
          <div className="px-2 py-2">
            <p className="text-lg font-semibold tabular-nums leading-none">{entries.length}</p>
            <p className="text-[10px] uppercase tracking-wide text-muted-foreground">logged</p>
          </div>
          <div className="px-2 py-2">
            <p className="text-lg font-semibold tabular-nums leading-none text-emerald-600 dark:text-emerald-400">{okCount}</p>
            <p className="text-[10px] uppercase tracking-wide text-muted-foreground">ok</p>
          </div>
          <div className="px-2 py-2">
            <p className={`text-lg font-semibold tabular-nums leading-none ${errCount > 0 ? "text-rose-600 dark:text-rose-400" : ""}`}>{errCount}</p>
            <p className="text-[10px] uppercase tracking-wide text-muted-foreground">errors</p>
          </div>
          <div className="px-2 py-2">
            <p className="text-lg font-semibold tabular-nums leading-none">{avgMs === null ? "—" : `${avgMs}ms`}</p>
            <p className="text-[10px] uppercase tracking-wide text-muted-foreground">avg</p>
          </div>
        </div>

        <div className="flex items-center justify-between gap-2 border-b px-4 py-2">
          <label className="flex cursor-pointer items-center gap-2 text-xs text-muted-foreground">
            <input
              type="checkbox"
              checked={hidePolls}
              onChange={(e) => setHidePolls(e.target.checked)}
              className="h-3.5 w-3.5 accent-emerald-600"
            />
            hide successful GETs (poll noise)
          </label>
          <Button variant="ghost" size="sm" onClick={clearApiLog} className="h-7 gap-1 text-xs" disabled={entries.length === 0}>
            <Trash2 className="h-3 w-3" /> clear
          </Button>
        </div>

        <div className="min-h-0 flex-1 overflow-y-auto">
          {shown.length === 0 ? (
            <div className="flex flex-col items-center justify-center gap-2 py-14 text-center">
              <CircleSlash2 className="h-8 w-8 text-muted-foreground/50" />
              <p className="text-sm font-medium">{entries.length === 0 ? "No requests yet" : "All filtered out"}</p>
              <p className="max-w-56 text-xs text-muted-foreground">
                {entries.length === 0
                  ? "Interact with the dashboard — every /api/gw call lands here with status and latency."
                  : "Turn off the filter to see successful GET polling calls."}
              </p>
            </div>
          ) : (
            <ul className="divide-y">
              {shown.map((e) => (
                <li key={e.id} className="flex items-center gap-3 px-4 py-2 transition-colors hover:bg-muted/40">
                  <span className={`w-10 shrink-0 font-mono text-[11px] font-semibold ${METHOD_STYLES[e.method] ?? ""}`}>{e.method}</span>
                  <span className="min-w-0 flex-1 truncate font-mono text-xs" title={e.path}>{e.path}</span>
                  {e.status === null ? (
                    <Loader2 className="h-3.5 w-3.5 shrink-0 animate-spin text-emerald-600" aria-label="in flight" />
                  ) : (
                    <Badge variant="outline" className={`shrink-0 tabular-nums ${statusClass(e.status)}`}>{e.status}</Badge>
                  )}
                  <span className="w-12 shrink-0 text-right font-mono text-[11px] tabular-nums text-muted-foreground">
                    {e.ms === null ? "…" : `${e.ms}ms`}
                  </span>
                  <span className="w-8 shrink-0 text-right text-[10px] tabular-nums text-muted-foreground/70">{relMs(e.at)}</span>
                </li>
              ))}
            </ul>
          )}
        </div>

        <div className="flex items-center justify-between border-t bg-muted/30 px-4 py-2 text-[11px] text-muted-foreground">
          <span>
            {inFlight > 0 ? (
              <span className="flex items-center gap-1.5">
                <span className="pulse-dot relative inline-flex h-1.5 w-1.5 rounded-full bg-emerald-500 text-emerald-500" aria-hidden />
                {inFlight} in flight
              </span>
            ) : (
              "idle"
            )}
          </span>
          <span className="flex items-center gap-1">
            <Kbd className="border bg-background">esc</Kbd> close · cap 80
          </span>
        </div>
      </aside>
    </div>
  );
}
