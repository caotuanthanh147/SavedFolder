"use client";

// Gateway health monitor (M11 s11): derives connection state from the shared
// API request log (lib/api-log) — the last settled request decides. status 0
// (fetch threw — network unreachable) → offline banner; >= 500 → degraded.
// Any later success clears it automatically (pure derived state, no timers).
// The "check now" ping goes through loggedFetch so the result feeds back into
// the same store — and shows up in the API inspector.

import { useCallback, useSyncExternalStore } from "react";
import { AlertTriangle, RefreshCw, WifiOff } from "lucide-react";
import { getApiLogSnapshot, loggedFetch, subscribeApiLog, type ApiLogEntry } from "@/lib/api-log";

const EMPTY: ApiLogEntry[] = [];

type Health = "unknown" | "offline" | "degraded" | "online";

function derive(entries: ApiLogEntry[]): Health {
  // Last settled entry (in-flight ones have status null and don't count).
  const settled = entries.find((e) => e.status !== null);
  if (settled === undefined || settled.status === null) return "unknown";
  if (settled.status === 0) return "offline";
  if (settled.status >= 500) return "degraded";
  return "online";
}

export function useGatewayHealth(): Health {
  const entries = useSyncExternalStore(subscribeApiLog, getApiLogSnapshot, () => EMPTY);
  return derive(entries);
}

export function GatewayHealthBanner(): React.JSX.Element | null {
  const health = useGatewayHealth();
  const ping = useCallback(() => {
    void loggedFetch("/api/gw/sync", { cache: "no-store" }).catch(() => {
      /* the failed ping itself records status 0 — the banner stays */
    });
  }, []);

  if (health === "offline") {
    return (
      <div role="status" aria-live="polite" className="banner-in border-b border-rose-600/30 bg-rose-500/10">
        <div className="mx-auto flex max-w-7xl flex-wrap items-center gap-x-3 gap-y-1 px-4 py-1.5 text-xs">
          <WifiOff className="h-3.5 w-3.5 shrink-0 text-rose-600 dark:text-rose-400" aria-hidden />
          <p className="text-rose-700 dark:text-rose-300">
            <span className="font-medium">Gateway unreachable</span>
            <span className="ml-1.5 text-rose-600/80 dark:text-rose-400/80">
              background refreshes keep retrying — this clears itself when a request succeeds.
            </span>
          </p>
          <button
            type="button"
            onClick={ping}
            className="ml-auto inline-flex items-center gap-1 rounded-md border border-rose-600/30 px-2 py-0.5 font-medium text-rose-700 transition-colors hover:bg-rose-500/15 focus-visible:outline-2 focus-visible:outline-offset-2 dark:text-rose-300"
          >
            <RefreshCw className="h-3 w-3" aria-hidden /> check now
          </button>
        </div>
      </div>
    );
  }
  if (health === "degraded") {
    return (
      <div role="status" aria-live="polite" className="banner-in border-b border-amber-600/30 bg-amber-500/10">
        <div className="mx-auto flex max-w-7xl flex-wrap items-center gap-x-3 gap-y-1 px-4 py-1.5 text-xs">
          <AlertTriangle className="h-3.5 w-3.5 shrink-0 text-amber-600 dark:text-amber-400" aria-hidden />
          <p className="text-amber-700 dark:text-amber-300">
            <span className="font-medium">Gateway degraded</span>
            <span className="ml-1.5 text-amber-600/80 dark:text-amber-400/80">last request answered 5xx — retrying on the next poll.</span>
          </p>
          <button
            type="button"
            onClick={ping}
            className="ml-auto inline-flex items-center gap-1 rounded-md border border-amber-600/30 px-2 py-0.5 font-medium text-amber-700 transition-colors hover:bg-amber-500/15 focus-visible:outline-2 focus-visible:outline-offset-2 dark:text-amber-300"
          >
            <RefreshCw className="h-3 w-3" aria-hidden /> check now
          </button>
        </div>
      </div>
    );
  }
  return null;
}
