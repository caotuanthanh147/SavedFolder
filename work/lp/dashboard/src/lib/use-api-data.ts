"use client";

// Shared data-fetch hook for the dashboard views: setState only fires inside
// promise callbacks (never synchronously in the effect body), matching the
// react-hooks/set-state-in-effect contract. `refresh()` bumps the tick to
// re-run the fetch — used after mutations and by polling intervals.

import { useCallback, useEffect, useRef, useState } from "react";

export function useApiData<T>(fetcher: () => Promise<T>, deps: unknown[]): { data: T | null; error: string | null; refresh: () => void; loading: boolean } {
  const [data, setData] = useState<T | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [tick, setTick] = useState(0);
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
          setData(res);
          setError(null);
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

  const refresh = useCallback(() => setTick((t) => t + 1), []);
  return { data, error, refresh, loading: data === null && error === null };
}
