"use client";

// Shared data-fetch hook for the dashboard views: setState only fires inside
// promise callbacks (never synchronously in the effect body), matching the
// react-hooks/set-state-in-effect contract. `refresh()` bumps the tick to
// re-run the fetch — used after mutations and by polling intervals.
//
// opts.pollMs: optional auto-refresh. The timer calls refresh() (a state bump
// inside an interval callback — allowed), and lastUpdatedAt tracks when the
// last fetch SETTLED (client-only Date.now() in a callback — never rendered
// during SSR, so no hydration/prerender concerns) for freshness pills.
//
// prevData: the snapshot before the current one (set inside the same promise
// callback as data, so the react-hooks/set-state-in-effect contract holds).
// Lets views render poll-over-poll deltas — "+2 since last refresh".

import { useCallback, useEffect, useRef, useState } from "react";

export interface UseApiDataOptions {
  pollMs?: number;
}

export function useApiData<T>(
  fetcher: () => Promise<T>,
  deps: unknown[],
  opts?: UseApiDataOptions,
): { data: T | null; prevData: T | null; error: string | null; refresh: () => void; loading: boolean; lastUpdatedAt: number | null } {
  const [data, setData] = useState<T | null>(null);
  const [prevData, setPrevData] = useState<T | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [tick, setTick] = useState(0);
  const [lastUpdatedAt, setLastUpdatedAt] = useState<number | null>(null);
  // Last settled snapshot, kept in a ref so the promise callback can promote
  // it to prevData state BEFORE writing the new data (all inside the callback
  // — never inside a setState updater, which must stay pure).
  const dataRef = useRef<T | null>(null);
  const fetcherRef = useRef(fetcher);
  useEffect(() => {
    fetcherRef.current = fetcher;
  });

  useEffect(() => {
    let active = true;
    fetcherRef
      .current()
      .then((res: T) => {
        if (active) {
          if (dataRef.current !== null) setPrevData(dataRef.current);
          dataRef.current = res;
          setData(res);
          setError(null);
          setLastUpdatedAt(Date.now());
        }
      })
      .catch((e: unknown) => {
        if (active) setError(e instanceof Error ? e.message : "load failed");
      });
    return () => {
      active = false;
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [tick, ...deps]);

  useEffect(() => {
    if (opts?.pollMs === undefined || opts.pollMs <= 0) return;
    const timer = setInterval(() => setTick((t) => t + 1), opts.pollMs);
    return () => clearInterval(timer);
  }, [opts?.pollMs]);

  const refresh = useCallback(() => setTick((t) => t + 1), []);
  return { data, prevData, error, refresh, loading: data === null && error === null, lastUpdatedAt };
}
