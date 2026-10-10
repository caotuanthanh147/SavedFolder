"use client";

import { useState } from "react";
import { Alert, AlertDescription, AlertTitle } from "@/components/ui/alert";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle, DialogTrigger } from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { ScrollArea } from "@/components/ui/scroll-area";
import { Skeleton } from "@/components/ui/skeleton";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { formatTime, gw } from "@/lib/api";
import { useApiData } from "@/lib/use-api-data";
import { CircleCheck, KeyRound, RefreshCw, UserPlus } from "lucide-react";

interface AdminRow {
  id: string;
  discord_id: string | null;
  role: string;
  quota_keys: number | null;
  created_at: number;
  keys_created: number;
}

export function ResellersView(): React.JSX.Element {
  const [notice, setNotice] = useState<string | null>(null);
  const [actionError, setActionError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const { data, error, refresh } = useApiData<{ rows: AdminRow[] }>(() => gw<{ rows: AdminRow[] }>("GET", "/admin/admins"), []);
  const rows = data?.rows ?? null;
  const resellers = rows?.filter((r) => r.role === "reseller") ?? null;

  const [open, setOpen] = useState(false);
  const [discordId, setDiscordId] = useState("");
  const [quota, setQuota] = useState("50");
  const [minted, setMinted] = useState<{ token: string } | null>(null);

  async function createReseller(): Promise<void> {
    setBusy(true);
    try {
      const res = await gw<{ token: string }>("POST", "/admin/resellers", {
        discord_id: discordId.trim().length > 0 ? discordId.trim() : null,
        quota_keys: Math.max(1, parseInt(quota, 10) || 50),
      });
      setMinted({ token: res.token });
      setOpen(false);
      setNotice("Reseller created (audited). API token shown once below.");
      refresh();
    } catch (e) {
      setActionError(e instanceof Error ? e.message : "create failed");
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="space-y-4">
      {(error || actionError) && (
        <Alert variant="destructive">
          <AlertTitle>{error ? "API error" : "Action failed"}</AlertTitle>
          <AlertDescription>{error ?? actionError}</AlertDescription>
        </Alert>
      )}
      {notice && (
        <Alert>
          <CircleCheck className="h-4 w-4" />
          <AlertTitle>OK</AlertTitle>
          <AlertDescription>{notice}</AlertDescription>
        </Alert>
      )}

      {minted && (
        <Card className="border-emerald-600/40 bg-emerald-50/50 dark:bg-emerald-950/20">
          <CardHeader className="pb-2">
            <CardTitle className="flex items-center gap-2 text-sm">
              <KeyRound className="h-4 w-4" /> Reseller API token — shown once
            </CardTitle>
          </CardHeader>
          <CardContent>
            <p className="break-all rounded-md border bg-background p-2 font-mono text-xs">{minted.token}</p>
            <p className="mt-2 text-xs text-muted-foreground">
              Only a SHA-256 of the secret is stored (owner Q2 scheme). Hand it to the reseller over a private channel — it cannot be
              recovered.
            </p>
          </CardContent>
        </Card>
      )}

      <div className="flex flex-wrap items-center gap-2">
        <Dialog open={open} onOpenChange={setOpen}>
          <DialogTrigger asChild>
            <Button size="sm">
              <UserPlus className="mr-1 h-4 w-4" /> New reseller
            </Button>
          </DialogTrigger>
          <DialogContent>
            <DialogHeader>
              <DialogTitle>Mint a reseller</DialogTitle>
              <DialogDescription>
                Resellers authenticate with their own admin token and see only keys they created. quota_keys caps issuance.
              </DialogDescription>
            </DialogHeader>
            <div className="grid gap-3 py-1">
              <div className="grid gap-1.5">
                <Label htmlFor="res-discord">Discord id (optional)</Label>
                <Input id="res-discord" value={discordId} onChange={(e) => setDiscordId(e.target.value)} placeholder="123456789012345678" inputMode="numeric" className="font-mono" />
              </div>
              <div className="grid gap-1.5">
                <Label htmlFor="res-quota">Key quota</Label>
                <Input id="res-quota" value={quota} onChange={(e) => setQuota(e.target.value)} inputMode="numeric" />
              </div>
            </div>
            <DialogFooter>
              <Button onClick={createReseller} disabled={busy}>
                {busy ? "Minting…" : "Create reseller"}
              </Button>
            </DialogFooter>
          </DialogContent>
        </Dialog>
        <Button variant="outline" size="icon" onClick={() => refresh()} aria-label="refresh">
          <RefreshCw className="h-4 w-4" />
        </Button>
        <p className="text-sm text-muted-foreground">
          Reseller roles: own-keys-only listing, quota-capped issuance, audited minting (doc §6 admins table, G13).
        </p>
      </div>

      <Card>
        <CardHeader className="pb-2">
          <CardTitle className="text-sm text-muted-foreground">
            {resellers === null ? "loading…" : `${resellers.length} reseller${resellers.length === 1 ? "" : "s"} · ${rows?.length ?? 0} admin rows total`}
          </CardTitle>
        </CardHeader>
        <CardContent>
          {rows === null ? (
            <div className="space-y-2">
              {Array.from({ length: 3 }).map((_, i) => (
                <Skeleton key={i} className="h-10" />
              ))}
            </div>
          ) : (
            <ScrollArea className="max-h-96">
              <Table>
                <TableHeader>
                  <TableRow>
                    <TableHead>Admin</TableHead>
                    <TableHead>Role</TableHead>
                    <TableHead>Discord</TableHead>
                    <TableHead>Quota</TableHead>
                    <TableHead>Keys created</TableHead>
                    <TableHead>Created</TableHead>
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {rows.map((r) => (
                    <TableRow key={r.id}>
                      <TableCell className="font-mono text-xs">{r.id.slice(0, 10)}…</TableCell>
                      <TableCell>
                        {r.role === "owner" ? (
                          <Badge className="bg-emerald-600 hover:bg-emerald-600">{r.role}</Badge>
                        ) : r.role === "reseller" ? (
                          <Badge className="bg-amber-600 hover:bg-amber-600">{r.role}</Badge>
                        ) : (
                          <Badge variant="secondary">{r.role}</Badge>
                        )}
                      </TableCell>
                      <TableCell className="font-mono text-xs">{r.discord_id ?? "—"}</TableCell>
                      <TableCell className="tabular-nums">{r.quota_keys ?? "∞"}</TableCell>
                      <TableCell className="tabular-nums">{r.keys_created}</TableCell>
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
