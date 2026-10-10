"use client";

import { useState } from "react";
import { Alert, AlertDescription, AlertTitle } from "@/components/ui/alert";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Skeleton } from "@/components/ui/skeleton";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { formatTime, gw, SessionRow, shortHash, SyncData } from "@/lib/api";
import { useApiData } from "@/lib/use-api-data";
import { copyText, csvTimestamp, exportCsv } from "@/lib/export-utils";
import { FreshnessPill } from "@/components/dashboard/freshness";
import { ArrowUpRight, Download, Fingerprint, RefreshCw, Stamp } from "lucide-react";

export function SessionsView({
  prefill,
  onTrace,
  onOpenKey,
}: {
  prefill?: string;
  onTrace?: (watermarkId: string) => void;
  onOpenKey?: (keyId: string) => void;
}): React.JSX.Element {
  const [keyFilter, setKeyFilter] = useState(prefill ?? "");
  const trimmed = keyFilter.trim();
  const { data, error, refresh, lastUpdatedAt } = useApiData(
    () => gw<{ rows: SessionRow[]; total: number }>("GET", `/admin/sessions?limit=100${trimmed.length > 0 ? `&key_id=${encodeURIComponent(trimmed)}` : ""}`),
    [trimmed],
    { pollMs: 30000 },
  );
  // Server clock (M11 s10): the live/expired pill is computed against /sync's
  // st — pure data-derived, no Date.now() in render (hydration-safe).
  const sync = useApiData(() => gw<SyncData>("GET", "/sync"), []);
  const st = sync.data?.st ?? null;
  const rows = data?.rows ?? null;
  const total = data?.total ?? 0;
  const liveCount = rows !== null && st !== null ? rows.filter((r) => r.expires_at > st).length : null;

  function exportSessionsCsv(): void {
    if (rows === null) return;
    exportCsv(`sessions-${csvTimestamp()}`, ["session_id", "watermark_id", "key_id", "script_id", "version", "hwid_hash", "ip_hash", "place_id", "created_at", "expires_at"], rows.map((r) => [r.id, r.watermark_id, r.key_id ?? "", r.script_id, r.version, r.hwid_hash, r.ip_hash, r.place_id ?? "", r.created_at, r.expires_at]));
  }

  return (
    <div className="space-y-4">
      {error && (
        <Alert variant="destructive">
          <AlertTitle>API error</AlertTitle>
          <AlertDescription>{error}</AlertDescription>
        </Alert>
      )}
      <div className="flex flex-wrap items-center gap-2">
        <Input value={keyFilter} onChange={(e) => setKeyFilter(e.target.value)} placeholder="filter by key id" className="w-64 font-mono" aria-label="filter sessions by key id" />
        <FreshnessPill lastUpdatedAt={lastUpdatedAt} onRefresh={refresh} pollMs={30000} />
        <Button variant="outline" size="icon" onClick={() => refresh()} aria-label="refresh">
          <RefreshCw className="h-4 w-4" />
        </Button>
        <Button variant="outline" size="icon" onClick={exportSessionsCsv} disabled={rows === null || rows.length === 0} aria-label="export sessions as CSV" title="export CSV">
          <Download className="h-4 w-4" />
        </Button>
        <p className="text-sm text-muted-foreground">
          Every auth/init creates a session row with a unique watermark id — leak tracing joins from here (doc §12).
          {liveCount !== null && <span className="ml-1 tabular-nums">· {liveCount} live of {total} listed.</span>}
        </p>
      </div>
      <Card>
        <CardHeader className="pb-2">
          <CardTitle className="text-sm text-muted-foreground">
            {rows === null ? "loading…" : `${total} session${total === 1 ? "" : "s"} (CCP-2 read endpoint)`}
          </CardTitle>
        </CardHeader>
        <CardContent>
          {rows === null ? (
            <div className="space-y-2">
              {Array.from({ length: 5 }).map((_, i) => (
                <Skeleton key={i} className="skeleton-shimmer h-10" />
              ))}
            </div>
          ) : rows.length === 0 ? (
            <p className="py-8 text-center text-sm text-muted-foreground">
              {trimmed.length > 0
                ? `No sessions for key ${trimmed.slice(0, 12)}… in the latest 100 rows.`
                : "No sessions yet — they appear when a key holder runs /auth/<script>/init."}
            </p>
          ) : (
            <div className="max-h-96 overflow-auto">
              <Table className="table-sticky">
                <TableHeader>
                  <TableRow>
                    <TableHead>Session</TableHead>
                    <TableHead>Status</TableHead>
                    <TableHead>Key</TableHead>
                    <TableHead>Script</TableHead>
                    <TableHead>v</TableHead>
                    <TableHead>HWID</TableHead>
                    <TableHead>IP</TableHead>
                    <TableHead>Place</TableHead>
                    <TableHead>Created</TableHead>
                    <TableHead>Expires</TableHead>
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {rows.map((r) => {
                    const live = st !== null && r.expires_at > st;
                    const kid = r.key_id;
                    return (
                    <TableRow key={r.id}>
                      <TableCell className="font-mono text-xs">
                        <span className="inline-flex items-center gap-1">
                          <Stamp className="h-3 w-3 text-muted-foreground" />
                          <button
                            type="button"
                            className="rounded-sm transition-colors hover:text-emerald-600 hover:underline dark:hover:text-emerald-400 focus-visible:outline-2 focus-visible:outline-offset-2"
                            onClick={() => copyText(r.watermark_id, "Watermark copied")}
                            title="click to copy watermark id"
                          >
                            {shortHash(r.watermark_id, 8)}
                          </button>
                          {onTrace !== undefined && (
                            <button
                              type="button"
                              className="rounded p-0.5 text-muted-foreground transition-colors hover:bg-muted hover:text-emerald-600 dark:hover:text-emerald-400 focus-visible:outline-2 focus-visible:outline-offset-2"
                              onClick={() => onTrace(r.watermark_id)}
                              aria-label={`trace watermark ${r.watermark_id} in leak tools`}
                              title="trace in Leak tools"
                            >
                              <Fingerprint className="h-3.5 w-3.5" />
                            </button>
                          )}
                        </span>
                      </TableCell>
                      <TableCell>
                        {st === null ? (
                          <Badge variant="secondary" className="text-[10px]">…</Badge>
                        ) : live ? (
                          <span className="inline-flex items-center gap-1.5 text-[10px] font-medium uppercase tracking-wide text-emerald-600 dark:text-emerald-400">
                            <span className="pulse-dot relative inline-flex h-1.5 w-1.5 rounded-full bg-emerald-500 text-emerald-500" aria-hidden />
                            live
                          </span>
                        ) : (
                          <span className="inline-flex items-center gap-1.5 text-[10px] font-medium uppercase tracking-wide text-muted-foreground">
                            <span className="inline-flex h-1.5 w-1.5 rounded-full bg-stone-400" aria-hidden />
                            expired
                          </span>
                        )}
                      </TableCell>
                      <TableCell className="font-mono text-xs">
                        {kid !== null ? (
                          onOpenKey !== undefined ? (
                            <button
                              type="button"
                              className="group inline-flex items-center gap-1 rounded-sm transition-colors hover:text-emerald-600 dark:hover:text-emerald-400 focus-visible:outline-2 focus-visible:outline-offset-2"
                              onClick={() => onOpenKey(kid)}
                              title={`open key ${shortHash(kid, 8)} in Keys view`}
                            >
                              <Fingerprint className="h-3 w-3 text-muted-foreground" aria-hidden />
                              {shortHash(kid, 8)}
                              <ArrowUpRight className="h-3 w-3 opacity-0 transition-opacity group-hover:opacity-100" aria-hidden />
                            </button>
                          ) : (
                            <span className="inline-flex items-center gap-1">
                              <Fingerprint className="h-3 w-3 text-muted-foreground" />
                              {shortHash(kid, 8)}
                            </span>
                          )
                        ) : (
                          <Badge variant="secondary">keyless</Badge>
                        )}
                      </TableCell>
                      <TableCell className="font-mono text-xs">{shortHash(r.script_id, 8)}</TableCell>
                      <TableCell className="tabular-nums">{r.version}</TableCell>
                      <TableCell className="font-mono text-xs">{shortHash(r.hwid_hash, 8)}</TableCell>
                      <TableCell className="font-mono text-xs">{shortHash(r.ip_hash, 8)}</TableCell>
                      <TableCell className="tabular-nums text-xs">{r.place_id ?? "—"}</TableCell>
                      <TableCell className="text-xs">{formatTime(r.created_at)}</TableCell>
                      <TableCell className="text-xs">
                        <span className={live ? "text-foreground" : "text-muted-foreground"}>{formatTime(r.expires_at)}</span>
                      </TableCell>
                    </TableRow>
                    );
                  })}
                </TableBody>
              </Table>
            </div>
          )}
        </CardContent>
      </Card>
    </div>
  );
}
