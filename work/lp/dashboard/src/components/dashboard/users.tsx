"use client";

import { useState } from "react";
import { Alert, AlertDescription, AlertTitle } from "@/components/ui/alert";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { ScrollArea } from "@/components/ui/scroll-area";
import { Skeleton } from "@/components/ui/skeleton";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { formatTime, gw } from "@/lib/api";
import { useApiData } from "@/lib/use-api-data";
import { Gamepad2, RefreshCw, Search, Users } from "lucide-react";

interface UserRow {
  identity: string;
  kind: string;
  key_count: number;
  active_keys: number;
  hwids: number;
  total_executions: number;
  first_seen: number;
  last_used: number | null;
}

export function UsersView(): React.JSX.Element {
  const [query, setQuery] = useState("");
  const trimmed = query.trim();
  const { data, error, refresh } = useApiData<{ rows: UserRow[] }>(
    () => gw<{ rows: UserRow[] }>("GET", `/admin/users${trimmed.length > 0 ? `?q=${encodeURIComponent(trimmed)}` : ""}`),
    [trimmed],
  );
  const rows = data?.rows ?? null;

  return (
    <div className="space-y-4">
      {error && (
        <Alert variant="destructive">
          <AlertTitle>API error</AlertTitle>
          <AlertDescription>{error}</AlertDescription>
        </Alert>
      )}
      <div className="flex flex-wrap items-center gap-2">
        <div className="relative">
          <Search className="absolute left-2.5 top-1/2 h-4 w-4 -translate-y-1/2 text-muted-foreground" aria-hidden />
          <Input value={query} onChange={(e) => setQuery(e.target.value)} placeholder="search discord id or roblox user" className="w-72 pl-8 font-mono" aria-label="search users" />
        </div>
        <Button variant="outline" size="icon" onClick={() => refresh()} aria-label="refresh">
          <RefreshCw className="h-4 w-4" />
        </Button>
        <p className="text-sm text-muted-foreground">
          End-user identities aggregated across keys: discord link first, roblox user fallback (doc §16 Users page).
        </p>
      </div>
      <Card>
        <CardHeader className="pb-2">
          <CardTitle className="flex items-center gap-2 text-sm text-muted-foreground">
            <Users className="h-4 w-4" />
            {rows === null ? "loading…" : `${rows.length} user${rows.length === 1 ? "" : "s"} (CCP-2 read endpoint)`}
          </CardTitle>
        </CardHeader>
        <CardContent>
          {rows === null ? (
            <div className="space-y-2">
              {Array.from({ length: 4 }).map((_, i) => (
                <Skeleton key={i} className="h-10" />
              ))}
            </div>
          ) : rows.length === 0 ? (
            <p className="py-8 text-center text-sm text-muted-foreground">
              No users — identities appear when keys carry a discord id or roblox user (redeem linking, purchases).
            </p>
          ) : (
            <ScrollArea className="max-h-96">
              <Table>
                <TableHeader>
                  <TableRow>
                    <TableHead>Identity</TableHead>
                    <TableHead>Kind</TableHead>
                    <TableHead>Keys</TableHead>
                    <TableHead>Active</TableHead>
                    <TableHead>HWIDs</TableHead>
                    <TableHead>Executions</TableHead>
                    <TableHead>First seen</TableHead>
                    <TableHead>Last used</TableHead>
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {rows.map((r) => (
                    <TableRow key={r.kind + ":" + r.identity}>
                      <TableCell className="font-mono text-xs">
                        <span className="inline-flex items-center gap-1.5">
                          {r.kind === "discord" ? (
                            <span className="inline-block h-2 w-2 rounded-full bg-emerald-500" aria-hidden />
                          ) : (
                            <Gamepad2 className="h-3 w-3 text-muted-foreground" aria-hidden />
                          )}
                          {r.identity}
                        </span>
                      </TableCell>
                      <TableCell>
                        <Badge variant={r.kind === "discord" ? "default" : "secondary"}>{r.kind}</Badge>
                      </TableCell>
                      <TableCell className="tabular-nums">{r.key_count}</TableCell>
                      <TableCell className="tabular-nums">
                        <span className={r.active_keys > 0 ? "font-medium text-emerald-600 dark:text-emerald-400" : "text-muted-foreground"}>
                          {r.active_keys}
                        </span>
                      </TableCell>
                      <TableCell className="tabular-nums text-muted-foreground">{r.hwids}</TableCell>
                      <TableCell className="tabular-nums text-muted-foreground">{r.total_executions}</TableCell>
                      <TableCell className="text-xs">{formatTime(r.first_seen)}</TableCell>
                      <TableCell className="text-xs">{formatTime(r.last_used)}</TableCell>
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
