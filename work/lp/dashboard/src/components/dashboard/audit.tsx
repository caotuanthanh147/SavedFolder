"use client";

import { useEffect } from "react";
import { Alert, AlertDescription, AlertTitle } from "@/components/ui/alert";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { ScrollArea } from "@/components/ui/scroll-area";
import { Skeleton } from "@/components/ui/skeleton";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { AuditEntry, formatTime, gw } from "@/lib/api";
import { useApiData } from "@/lib/use-api-data";
import { RefreshCw, ScrollText } from "lucide-react";

function actionBadge(action: string): React.JSX.Element {
  const isFree = action.startsWith("free") || action.includes("free");
  const isAdmin = action.startsWith("admin.");
  if (isFree) return <Badge variant="secondary">{action}</Badge>;
  if (isAdmin) return <Badge variant="outline">{action}</Badge>;
  return <Badge>{action}</Badge>;
}

export function AuditView(): React.JSX.Element {
  const { data, error, refresh } = useApiData(() => gw<{ entries: AuditEntry[] }>("GET", "/admin/audit"), []);
  const rows: AuditEntry[] | null = data?.entries ?? null;

  useEffect(() => {
    const timer = setInterval(() => refresh(), 20000);
    return () => clearInterval(timer);
  }, [refresh]);

  return (
    <div className="space-y-4">
      {error && (
        <Alert variant="destructive">
          <AlertTitle>API error</AlertTitle>
          <AlertDescription>{error}</AlertDescription>
        </Alert>
      )}
      <div className="flex items-center justify-between">
        <p className="text-sm text-muted-foreground">
          Every mutation through the admin API lands here — key creates/revokes, HWID resets, script versions, blacklists, node and protocol changes, and free-flow claims.
        </p>
        <Button variant="outline" size="icon" onClick={() => refresh()} aria-label="refresh">
          <RefreshCw className="h-4 w-4" />
        </Button>
      </div>
      <Card>
        <CardHeader className="pb-2">
          <CardTitle className="flex items-center gap-2 text-sm text-muted-foreground">
            <ScrollText className="h-4 w-4" /> {rows === null ? "loading…" : `${rows.length} most recent audit entries`}
          </CardTitle>
        </CardHeader>
        <CardContent>
          {rows === null ? (
            <div className="space-y-2">
              {Array.from({ length: 6 }).map((_, i) => (
                <Skeleton key={i} className="h-9" />
              ))}
            </div>
          ) : rows.length === 0 ? (
            <p className="py-8 text-center text-sm text-muted-foreground">No audit entries yet — trigger a mutation.</p>
          ) : (
            <ScrollArea className="max-h-96">
              <Table>
                <TableHeader>
                  <TableRow>
                    <TableHead>Time</TableHead>
                    <TableHead>Actor</TableHead>
                    <TableHead>Action</TableHead>
                    <TableHead>Target</TableHead>
                    <TableHead>Detail</TableHead>
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {rows.map((r) => (
                    <TableRow key={r.id}>
                      <TableCell className="text-xs whitespace-nowrap">{formatTime(r.created_at)}</TableCell>
                      <TableCell className="font-mono text-xs">{r.actor_id.slice(0, 10)}…</TableCell>
                      <TableCell>{actionBadge(r.action)}</TableCell>
                      <TableCell className="font-mono text-xs">{r.target ? r.target.slice(0, 12) + "…" : "—"}</TableCell>
                      <TableCell className="max-w-64 truncate text-xs text-muted-foreground">{r.detail || "—"}</TableCell>
                    </TableRow>
                  ))}
                </TableBody>
              </Table>
            </ScrollArea>
          )}
        </CardContent>
      </Card>
    </div>
  );
}
