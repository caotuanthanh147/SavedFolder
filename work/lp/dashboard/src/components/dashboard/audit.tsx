"use client";

import { useEffect, useMemo, useState } from "react";
import { toast } from "sonner";
import { Alert, AlertDescription, AlertTitle } from "@/components/ui/alert";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { ScrollArea } from "@/components/ui/scroll-area";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Skeleton } from "@/components/ui/skeleton";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { csvTimestamp, exportCsv } from "@/lib/export-utils";
import { AuditEntry, formatTime, gw } from "@/lib/api";
import { useApiData } from "@/lib/use-api-data";
import { Banknote, Download, Gift, KeyRound, RefreshCw, ScrollText, Search, ServerCog, ShieldAlert } from "lucide-react";

const CATEGORIES = [
  { value: "all", label: "all actions" },
  { value: "key", label: "key lifecycle" },
  { value: "payment", label: "payments" },
  { value: "free", label: "free flow" },
  { value: "security", label: "security" },
  { value: "script", label: "scripts" },
];

function categorize(action: string): string {
  if (action.startsWith("key.") || action.startsWith("hwid")) return "key";
  if (action.startsWith("payment")) return "payment";
  if (action.includes("free")) return "free";
  if (action.startsWith("blacklist") || action.startsWith("session")) return "security";
  if (action.startsWith("script") || action.startsWith("node") || action.startsWith("protocol")) return "script";
  return "other";
}

function ActionBadge({ action }: { action: string }): React.JSX.Element {
  const cat = categorize(action);
  if (cat === "payment")
    return (
      <Badge variant="outline" className="gap-1 border-emerald-600/30 bg-emerald-600/10 text-emerald-700 dark:text-emerald-400">
        <Banknote className="h-3 w-3" aria-hidden /> {action}
      </Badge>
    );
  if (cat === "free")
    return (
      <Badge variant="outline" className="gap-1 border-amber-600/30 bg-amber-600/10 text-amber-700 dark:text-amber-400">
        <Gift className="h-3 w-3" aria-hidden /> {action}
      </Badge>
    );
  if (cat === "security")
    return (
      <Badge variant="outline" className="gap-1 border-rose-600/30 bg-rose-600/10 text-rose-700 dark:text-rose-400">
        <ShieldAlert className="h-3 w-3" aria-hidden /> {action}
      </Badge>
    );
  if (cat === "key")
    return (
      <Badge variant="outline" className="gap-1 border-teal-600/30 bg-teal-600/10 text-teal-700 dark:text-teal-400">
        <KeyRound className="h-3 w-3" aria-hidden /> {action}
      </Badge>
    );
  if (cat === "script")
    return (
      <Badge variant="outline" className="gap-1 border-stone-500/40 bg-stone-500/10 text-stone-700 dark:text-stone-300">
        <ServerCog className="h-3 w-3" aria-hidden /> {action}
      </Badge>
    );
  return <Badge variant="secondary">{action}</Badge>;
}

function relTime(unix: number): string {
  const diff = Math.floor(Date.now() / 1000) - unix;
  if (diff < 60) return `${diff}s ago`;
  if (diff < 3600) return `${Math.floor(diff / 60)}m ago`;
  if (diff < 86400) return `${Math.floor(diff / 3600)}h ago`;
  return `${Math.floor(diff / 86400)}d ago`;
}

export function AuditView(): React.JSX.Element {
  const { data, error, refresh } = useApiData(() => gw<{ entries: AuditEntry[] }>("GET", "/admin/audit?limit=200"), []);
  const [category, setCategory] = useState("all");
  const [query, setQuery] = useState("");

  useEffect(() => {
    const timer = setInterval(() => refresh(), 20000);
    return () => clearInterval(timer);
  }, [refresh]);

  const rows: AuditEntry[] | null = data?.entries ?? null;
  const filtered = useMemo(() => {
    if (!rows) return null;
    let out = rows;
    if (category !== "all") out = out.filter((r) => categorize(r.action) === category);
    const q = query.trim().toLowerCase();
    if (q.length > 0)
      out = out.filter(
        (r) => r.action.toLowerCase().includes(q) || (r.detail ?? "").toLowerCase().includes(q) || (r.target ?? "").toLowerCase().includes(q) || r.actor_id.toLowerCase().includes(q),
      );
    return out;
  }, [rows, category, query]);

  function exportAuditCsv(): void {
    if (!filtered) return;
    exportCsv(`yuri-audit-${csvTimestamp()}`, ["time", "actor", "action", "target", "detail"], filtered.map((r) => [formatTime(r.created_at), r.actor_id, r.action, r.target ?? "", r.detail ?? ""]));
    toast.info("CSV exported", { description: `${filtered.length} audit entries (current filters).` });
  }

  return (
    <div className="space-y-4">
      {error && (
        <Alert variant="destructive">
          <AlertTitle>API error</AlertTitle>
          <AlertDescription>{error}</AlertDescription>
        </Alert>
      )}
      <div className="flex items-center gap-2">
        <p className="hidden flex-1 text-sm text-muted-foreground lg:block">
          Every mutation through the admin API lands here — key creates/revokes, HWID resets, script versions, blacklists, node and
          protocol changes, and free-flow claims. Polls every 20s.
        </p>
        <div className="relative flex-1 lg:max-w-52">
          <Search className="absolute left-2.5 top-2.5 h-4 w-4 text-muted-foreground" />
          <Input value={query} onChange={(e) => setQuery(e.target.value)} placeholder="search actor/action/detail" className="pl-8" />
        </div>
        <Select value={category} onValueChange={setCategory}>
          <SelectTrigger className="w-40" aria-label="filter by category">
            <SelectValue />
          </SelectTrigger>
          <SelectContent>
            {CATEGORIES.map((c) => (
              <SelectItem key={c.value} value={c.value}>
                {c.label}
              </SelectItem>
            ))}
          </SelectContent>
        </Select>
        <Button variant="outline" size="icon" onClick={() => refresh()} aria-label="refresh">
          <RefreshCw className="h-4 w-4" />
        </Button>
      </div>
      <Card>
        <CardHeader className="pb-2">
          <CardTitle className="flex flex-wrap items-center gap-2 text-sm text-muted-foreground">
            <ScrollText className="h-4 w-4" />
            {filtered === null ? "loading…" : `${filtered.length} of ${rows?.length ?? 0} audit entries`}
            <Button variant="outline" size="sm" className="ml-auto h-7" onClick={exportAuditCsv} disabled={!filtered || filtered.length === 0}>
              <Download className="mr-1 h-3.5 w-3.5" /> CSV
            </Button>
          </CardTitle>
        </CardHeader>
        <CardContent>
          {filtered === null ? (
            <div className="space-y-2">
              {Array.from({ length: 6 }).map((_, i) => (
                <Skeleton key={i} className="skeleton-shimmer h-9" />
              ))}
            </div>
          ) : filtered.length === 0 ? (
            <div className="flex flex-col items-center justify-center gap-2 py-12 text-center">
              <div className="flex h-12 w-12 items-center justify-center rounded-full bg-muted">
                <ScrollText className="h-6 w-6 text-muted-foreground" />
              </div>
              <p className="text-sm font-medium">No audit entries match</p>
              <p className="text-xs text-muted-foreground">Try clearing the search or category filter.</p>
            </div>
          ) : (
            <ScrollArea className="max-h-96">
              <Table>
                <TableHeader>
                  <TableRow className="hover:bg-transparent">
                    <TableHead>Time</TableHead>
                    <TableHead>Actor</TableHead>
                    <TableHead>Action</TableHead>
                    <TableHead>Target</TableHead>
                    <TableHead>Detail</TableHead>
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {filtered.map((r) => (
                    <TableRow key={r.id}>
                      <TableCell className="whitespace-nowrap text-xs">
                        <span title={formatTime(r.created_at)}>{relTime(r.created_at)}</span>
                      </TableCell>
                      <TableCell className="font-mono text-xs">{r.actor_id.slice(0, 10)}…</TableCell>
                      <TableCell>
                        <ActionBadge action={r.action} />
                      </TableCell>
                      <TableCell className="font-mono text-xs">{r.target ? r.target.slice(0, 12) + "…" : "—"}</TableCell>
                      <TableCell className="max-w-64 truncate text-xs text-muted-foreground" title={r.detail ?? undefined}>
                        {r.detail || "—"}
                      </TableCell>
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
