"use client";

import { useState } from "react";
import { Alert, AlertDescription, AlertTitle } from "@/components/ui/alert";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Skeleton } from "@/components/ui/skeleton";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { formatTime, gw, SessionRow, shortHash } from "@/lib/api";
import { useApiData } from "@/lib/use-api-data";
import { Fingerprint, RefreshCw, Stamp } from "lucide-react";

export function SessionsView(): React.JSX.Element {
  const [keyFilter, setKeyFilter] = useState("");
  const trimmed = keyFilter.trim();
  const { data, error, refresh } = useApiData(
    () => gw<{ rows: SessionRow[]; total: number }>("GET", `/admin/sessions?limit=100${trimmed.length > 0 ? `&key_id=${encodeURIComponent(trimmed)}` : ""}`),
    [trimmed],
  );
  const rows = data?.rows ?? null;
  const total = data?.total ?? 0;

  return (
    <div className="space-y-4">
      {error && (
        <Alert variant="destructive">
          <AlertTitle>API error</AlertTitle>
          <AlertDescription>{error}</AlertDescription>
        </Alert>
      )}
      <div className="flex flex-wrap items-center gap-2">
        <Input value={keyFilter} onChange={(e) => setKeyFilter(e.target.value)} placeholder="filter by key id" className="w-64 font-mono" />
        <Button variant="outline" size="icon" onClick={() => refresh()} aria-label="refresh">
          <RefreshCw className="h-4 w-4" />
        </Button>
        <p className="text-sm text-muted-foreground">
          Every auth/init creates a session row with a unique watermark id — leak tracing joins from here (doc §12).
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
            <p className="py-8 text-center text-sm text-muted-foreground">No sessions yet — they appear when a key holder runs /auth/&lt;script&gt;/init.</p>
          ) : (
            <div className="max-h-96 overflow-auto">
              <Table>
                <TableHeader>
                  <TableRow>
                    <TableHead>Session</TableHead>
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
                  {rows.map((r) => (
                    <TableRow key={r.id}>
                      <TableCell className="font-mono text-xs">
                        <span className="inline-flex items-center gap-1">
                          <Stamp className="h-3 w-3 text-muted-foreground" />
                          {shortHash(r.watermark_id, 8)}
                        </span>
                      </TableCell>
                      <TableCell className="font-mono text-xs">
                        {r.key_id ? (
                          <span className="inline-flex items-center gap-1">
                            <Fingerprint className="h-3 w-3 text-muted-foreground" />
                            {shortHash(r.key_id, 8)}
                          </span>
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
                      <TableCell className="text-xs">{formatTime(r.expires_at)}</TableCell>
                    </TableRow>
                  ))}
                </TableBody>
              </Table>
            </div>
          )}
        </CardContent>
      </Card>
    </div>
  );
}
