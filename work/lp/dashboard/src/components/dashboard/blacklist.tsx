"use client";

import { useState } from "react";
import { Alert, AlertDescription, AlertTitle } from "@/components/ui/alert";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle, DialogTrigger } from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { ScrollArea } from "@/components/ui/scroll-area";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Skeleton } from "@/components/ui/skeleton";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { BlacklistRow, formatTime, gw } from "@/lib/api";
import { useApiData } from "@/lib/use-api-data";
import { Ban, Plus, RefreshCw } from "lucide-react";

const KINDS = ["hwid", "ip", "roblox_user", "discord"] as const;

export function BlacklistView(): React.JSX.Element {
  const { data, error, refresh } = useApiData(() => gw<{ rows: BlacklistRow[] }>("GET", "/admin/blacklist"), []);
  const rows: BlacklistRow[] | null = data?.rows ?? null;
  const [notice, setNotice] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [kind, setKind] = useState<string>("hwid");
  const [value, setValue] = useState("");
  const [reason, setReason] = useState("");
  const [open, setOpen] = useState(false);



  async function add(): Promise<void> {
    setBusy(true);
    try {
      await gw("POST", "/admin/blacklist", {
        kind,
        value: value.trim(),
        reason: reason.trim().length > 0 ? reason.trim() : null,
        project_id: kind === "hwid" ? "11111111111111111111111111111111" : undefined,
      });
      setNotice(`Blacklisted ${kind} (value hashed server-side${kind === "hwid" ? " with the project salt" : ""}, audited).`);
      setOpen(false);
      setValue("");
      setReason("");
      refresh();
    } catch (e) {
      setError(e instanceof Error ? e.message : "add failed");
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="space-y-4">
      {notice && (
        <Alert>
          <Ban className="h-4 w-4" />
          <AlertDescription>{notice}</AlertDescription>
        </Alert>
      )}
      {error && (
        <Alert variant="destructive">
          <AlertTitle>API error</AlertTitle>
          <AlertDescription>{error}</AlertDescription>
        </Alert>
      )}
      <div className="flex items-center justify-between">
        <p className="text-sm text-muted-foreground">
          Values are stored hashed — hwid with per-project salt, ip/roblox_user/discord with the server pepper. Blacklist hits block check_key and auth init.
        </p>
        <Dialog open={open} onOpenChange={setOpen}>
          <DialogTrigger asChild>
            <Button size="sm">
              <Plus className="mr-1 h-4 w-4" /> Add entry
            </Button>
          </DialogTrigger>
          <DialogContent>
            <DialogHeader>
              <DialogTitle>Blacklist an identifier</DialogTitle>
              <DialogDescription>POST /admin/blacklist — the raw value is hashed before storage and never logged.</DialogDescription>
            </DialogHeader>
            <div className="space-y-3">
              <div className="space-y-1">
                <Label>Kind</Label>
                <Select value={kind} onValueChange={setKind}>
                  <SelectTrigger>
                    <SelectValue />
                  </SelectTrigger>
                  <SelectContent>
                    {KINDS.map((k) => (
                      <SelectItem key={k} value={k}>
                        {k}
                      </SelectItem>
                    ))}
                  </SelectContent>
                </Select>
              </div>
              <div className="space-y-1">
                <Label htmlFor="bl-value">Value (hwid string / ip / roblox user id / discord id)</Label>
                <Input id="bl-value" value={value} onChange={(e) => setValue(e.target.value)} className="font-mono" />
              </div>
              <div className="space-y-1">
                <Label htmlFor="bl-reason">Reason</Label>
                <Input id="bl-reason" value={reason} onChange={(e) => setReason(e.target.value)} placeholder="abuse / chargeback / leak" />
              </div>
            </div>
            <DialogFooter>
              <Button onClick={() => void add()} disabled={busy || value.trim().length === 0}>
                {busy ? "adding…" : "Add"}
              </Button>
            </DialogFooter>
          </DialogContent>
        </Dialog>
      </div>
      <Card>
        <CardHeader className="pb-2">
          <CardTitle className="text-sm text-muted-foreground">{rows === null ? "loading…" : `${rows.length} entr${rows.length === 1 ? "y" : "ies"}`}</CardTitle>
          <CardDescription>
            <Button variant="ghost" size="sm" onClick={() => refresh()}>
              <RefreshCw className="mr-1 h-3 w-3" /> refresh
            </Button>
          </CardDescription>
        </CardHeader>
        <CardContent>
          {rows === null ? (
            <div className="space-y-2">
              {Array.from({ length: 4 }).map((_, i) => (
                <Skeleton key={i} className="skeleton-shimmer h-10" />
              ))}
            </div>
          ) : rows.length === 0 ? (
            <p className="py-8 text-center text-sm text-muted-foreground">Blacklist is empty.</p>
          ) : (
            <ScrollArea className="max-h-96">
              <Table>
                <TableHeader>
                  <TableRow>
                    <TableHead>Kind</TableHead>
                    <TableHead>Value hash</TableHead>
                    <TableHead>Reason</TableHead>
                    <TableHead>Added by</TableHead>
                    <TableHead>Added</TableHead>
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {rows.map((r) => (
                    <TableRow key={r.id}>
                      <TableCell>
                        <Badge variant={r.kind === "hwid" || r.kind === "ip" ? "destructive" : "outline"}>{r.kind}</Badge>
                      </TableCell>
                      <TableCell className="font-mono text-xs">{r.value_hash.slice(0, 16)}…</TableCell>
                      <TableCell className="text-xs text-muted-foreground">{r.reason ?? "—"}</TableCell>
                      <TableCell className="font-mono text-xs">{r.created_by.slice(0, 8)}…</TableCell>
                      <TableCell className="text-xs">{formatTime(r.created_at)}</TableCell>
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
