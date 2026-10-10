"use client";

import { useState } from "react";
import { toast } from "sonner";
import { Alert, AlertDescription, AlertTitle } from "@/components/ui/alert";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle, DialogTrigger } from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { ScrollArea } from "@/components/ui/scroll-area";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Separator } from "@/components/ui/separator";
import { Skeleton } from "@/components/ui/skeleton";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { copyText, csvTimestamp, exportCsv } from "@/lib/export-utils";
import { formatTime, gw, KeyRow } from "@/lib/api";
import { useApiData } from "@/lib/use-api-data";
import { CalendarClock, Copy, Download, FileKey2, KeyRound, Plus, RefreshCw, Search, ShieldOff, Undo2 } from "lucide-react";

const DEMO_PROJECT_ID = "11111111111111111111111111111111";
const DEMO_SCRIPT_ID = "22222222222222222222222222222222";

const TIER_STYLES: Record<string, string> = {
  paid: "border-emerald-600/30 bg-emerald-600/10 text-emerald-700 dark:text-emerald-400",
  lifetime: "border-teal-600/30 bg-teal-600/10 text-teal-700 dark:text-teal-400",
  free: "border-amber-600/30 bg-amber-600/10 text-amber-700 dark:text-amber-400",
  reseller: "border-rose-600/30 bg-rose-600/10 text-rose-700 dark:text-rose-400",
};

function TierBadge({ tier }: { tier: string }): React.JSX.Element {
  return (
    <Badge variant="outline" className={`gap-1 ${TIER_STYLES[tier] ?? ""}`}>
      <span className="inline-block h-1.5 w-1.5 rounded-full bg-current opacity-70" aria-hidden />
      {tier}
    </Badge>
  );
}

function StatusBadge({ status }: { status: string }): React.JSX.Element {
  if (status === "active")
    return (
      <Badge className="gap-1 bg-emerald-600 hover:bg-emerald-600">
        <span className="pulse-dot relative inline-flex h-1.5 w-1.5 rounded-full bg-white" aria-hidden />
        {status}
      </Badge>
    );
  if (status === "revoked") return <Badge variant="destructive">{status}</Badge>;
  return <Badge variant="secondary">{status}</Badge>;
}

function DetailRow({ label, children }: { label: string; children: React.ReactNode }): React.JSX.Element {
  return (
    <div className="flex items-start justify-between gap-4 py-1.5">
      <span className="text-xs text-muted-foreground">{label}</span>
      <span className="text-right font-mono text-xs">{children}</span>
    </div>
  );
}

export function KeysView(): React.JSX.Element {
  const [actionError, setActionError] = useState<string | null>(null);
  const [query, setQuery] = useState("");
  const [tier, setTier] = useState("all");
  const [status, setStatus] = useState("all");
  const [busy, setBusy] = useState(false);
  const [detail, setDetail] = useState<KeyRow | null>(null);
  const trimmed = query.trim();
  const { data, error, refresh } = useApiData(
    () => {
      const params = new URLSearchParams({ limit: "100" });
      if (trimmed.length > 0) params.set("q", trimmed);
      if (tier !== "all") params.set("tier", tier);
      if (status !== "all") params.set("status", status);
      return gw<{ rows: KeyRow[]; total: number }>("GET", `/admin/keys?${params.toString()}`);
    },
    [trimmed, tier, status],
  );
  const rows: KeyRow[] | null = data?.rows ?? null;
  const total = data?.total ?? 0;

  const [createOpen, setCreateOpen] = useState(false);
  const [newTier, setNewTier] = useState("paid");
  const [newDays, setNewDays] = useState("30");
  const [newCount, setNewCount] = useState("1");
  const [newNote, setNewNote] = useState("");
  const [createdKeys, setCreatedKeys] = useState<string[] | null>(null);

  const [validateKey, setValidateKey] = useState("");
  const [validateResult, setValidateResult] = useState<{ code: string; message: string; data: unknown } | null>(null);
  const [validating, setValidating] = useState(false);

  async function createKeys(): Promise<void> {
    setBusy(true);
    try {
      const res = await gw<{ keys: { key: string }[] }>("POST", "/admin/keys", {
        project_id: DEMO_PROJECT_ID,
        tier: newTier,
        count: Math.max(1, Math.min(50, parseInt(newCount, 10) || 1)),
        days: newTier === "lifetime" ? null : Math.max(1, parseInt(newDays, 10) || 30),
        note: newNote.trim().length > 0 ? newNote.trim() : null,
        script_ids: [DEMO_SCRIPT_ID],
      });
      setCreatedKeys(res.keys.map((k) => k.key));
      setCreateOpen(false);
      toast.success(`Created ${res.keys.length} key${res.keys.length > 1 ? "s" : ""}`, {
        description: "Every creation is audit-logged. Plaintext shown once below.",
      });
      refresh();
    } catch (e) {
      const msg = e instanceof Error ? e.message : "create failed";
      setActionError(msg);
      toast.error("Create failed", { description: msg });
    } finally {
      setBusy(false);
    }
  }

  async function revokeKey(id: string): Promise<void> {
    setBusy(true);
    try {
      await gw("POST", `/admin/keys/${id}/revoke`, {});
      toast.success(`Key ${id.slice(0, 8)}… revoked`, { description: "Mutation audit-logged." });
      refresh();
    } catch (e) {
      const msg = e instanceof Error ? e.message : "revoke failed";
      setActionError(msg);
      toast.error("Revoke failed", { description: msg });
    } finally {
      setBusy(false);
    }
  }

  async function resetHwid(id: string): Promise<void> {
    setBusy(true);
    try {
      await gw("POST", `/admin/keys/${id}/reset-hwid`, {});
      toast.success(`HWID reset for ${id.slice(0, 8)}…`, { description: "7-day cooldown, 2/month cap enforced server-side." });
      refresh();
    } catch (e) {
      const msg = e instanceof Error ? e.message : "reset failed (cooldown?)";
      setActionError(msg);
      toast.error("HWID reset failed", { description: msg });
    } finally {
      setBusy(false);
    }
  }

  async function runValidate(): Promise<void> {
    if (validateKey.trim().length === 0) return;
    setValidating(true);
    try {
      const res = await fetch("/api/dash/validate-key", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ key: validateKey.trim() }),
      });
      const json = (await res.json()) as { code: string; message: string; data: unknown };
      setValidateResult(json);
      if (json.code === "KEY_VALID") toast.success("KEY_VALID", { description: json.message });
      else toast.error(json.code, { description: json.message });
    } catch {
      setValidateResult({ code: "SERVER_ERROR", message: "request failed", data: null });
    } finally {
      setValidating(false);
    }
  }

  function exportKeysCsv(): void {
    if (!rows) return;
    exportCsv(`yuri-keys-${csvTimestamp()}`, ["id", "tier", "status", "note", "executions", "hwid_bound", "hwid_resets", "discord_id", "roblox_user_id", "created_at", "expires_at", "last_used_at", "created_by"], rows.map((r) => [r.id, r.tier, r.status, r.note ?? "", r.total_executions, r.hwid_bound, r.hwid_resets, r.discord_id ?? "", r.roblox_user_id ?? "", formatTime(r.created_at), formatTime(r.expires_at), formatTime(r.last_used_at), r.created_by]));
    toast.info("CSV exported", { description: `${rows.length} key rows (current filters).` });
  }

  return (
    <div className="space-y-4">
      {(error ?? actionError) && (
        <Alert variant="destructive">
          <AlertTitle>API error</AlertTitle>
          <AlertDescription>{error ?? actionError}</AlertDescription>
        </Alert>
      )}
      {createdKeys && (
        <Card className="border-emerald-600/40 shadow-sm">
          <CardHeader className="pb-2">
            <CardTitle className="flex items-center gap-2 text-sm">
              <FileKey2 className="h-4 w-4 text-emerald-600" /> New keys — copy now, plaintext is never shown again (§6)
            </CardTitle>
          </CardHeader>
          <CardContent className="space-y-2">
            {createdKeys.map((k) => (
              <div key={k} className="flex items-center justify-between gap-2 rounded-md border bg-muted/30 p-2">
                <code className="text-sm font-semibold">{k}</code>
                <Button variant="outline" size="sm" onClick={() => copyText(k, "Key copied")}>
                  <Copy className="mr-1 h-3.5 w-3.5" /> copy
                </Button>
              </div>
            ))}
            <Button variant="ghost" size="sm" onClick={() => setCreatedKeys(null)}>
              dismiss
            </Button>
          </CardContent>
        </Card>
      )}

      <div className="flex flex-wrap items-center gap-2">
        <div className="relative min-w-48 flex-1">
          <Search className="absolute left-2.5 top-2.5 h-4 w-4 text-muted-foreground" />
          <Input value={query} onChange={(e) => setQuery(e.target.value)} placeholder="search id / note / discord" className="pl-8" />
        </div>
        <Select value={tier} onValueChange={setTier}>
          <SelectTrigger className="w-28">
            <SelectValue />
          </SelectTrigger>
          <SelectContent>
            <SelectItem value="all">all tiers</SelectItem>
            <SelectItem value="paid">paid</SelectItem>
            <SelectItem value="lifetime">lifetime</SelectItem>
            <SelectItem value="free">free</SelectItem>
            <SelectItem value="reseller">reseller</SelectItem>
          </SelectContent>
        </Select>
        <Select value={status} onValueChange={setStatus}>
          <SelectTrigger className="w-30">
            <SelectValue />
          </SelectTrigger>
          <SelectContent>
            <SelectItem value="all">all status</SelectItem>
            <SelectItem value="active">active</SelectItem>
            <SelectItem value="revoked">revoked</SelectItem>
          </SelectContent>
        </Select>
        <Button variant="outline" size="icon" onClick={() => refresh()} aria-label="refresh">
          <RefreshCw className="h-4 w-4" />
        </Button>
        <Button variant="outline" onClick={exportKeysCsv} disabled={!rows || rows.length === 0}>
          <Download className="mr-1 h-4 w-4" /> CSV
        </Button>
        <Dialog open={createOpen} onOpenChange={setCreateOpen}>
          <DialogTrigger asChild>
            <Button>
              <Plus className="mr-1 h-4 w-4" /> Create keys
            </Button>
          </DialogTrigger>
          <DialogContent>
            <DialogHeader>
              <DialogTitle className="flex items-center gap-2">
                <KeyRound className="h-4 w-4 text-emerald-600" /> Create keys
              </DialogTitle>
              <DialogDescription>POST /admin/keys — every creation is audit-logged.</DialogDescription>
            </DialogHeader>
            <div className="grid gap-4">
              <div className="grid grid-cols-2 gap-3">
                <div className="space-y-1">
                  <Label htmlFor="tier">Tier</Label>
                  <Select value={newTier} onValueChange={setNewTier}>
                    <SelectTrigger id="tier">
                      <SelectValue />
                    </SelectTrigger>
                    <SelectContent>
                      <SelectItem value="paid">paid</SelectItem>
                      <SelectItem value="lifetime">lifetime</SelectItem>
                      <SelectItem value="free">free</SelectItem>
                    </SelectContent>
                  </Select>
                </div>
                <div className="space-y-1">
                  <Label htmlFor="days">Days</Label>
                  <Input id="days" type="number" min={1} value={newDays} onChange={(e) => setNewDays(e.target.value)} disabled={newTier === "lifetime"} />
                </div>
              </div>
              <div className="space-y-1">
                <Label htmlFor="count">Count (1-50)</Label>
                <Input id="count" type="number" min={1} max={50} value={newCount} onChange={(e) => setNewCount(e.target.value)} />
              </div>
              <div className="space-y-1">
                <Label htmlFor="note">Note</Label>
                <Input id="note" value={newNote} onChange={(e) => setNewNote(e.target.value)} placeholder="buyer / batch reference" />
              </div>
            </div>
            <DialogFooter>
              <Button onClick={() => void createKeys()} disabled={busy}>
                {busy ? "creating…" : "Create"}
              </Button>
            </DialogFooter>
          </DialogContent>
        </Dialog>
      </div>

      <Card>
        <CardHeader className="pb-2">
          <CardTitle className="text-sm text-muted-foreground">
            {rows === null
              ? "loading…"
              : `${total} key${total === 1 ? "" : "s"} · hash-only storage, plaintext never returned after creation`}
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
            <div className="flex flex-col items-center justify-center gap-2 py-12 text-center">
              <div className="flex h-12 w-12 items-center justify-center rounded-full bg-muted">
                <KeyRound className="h-6 w-6 text-muted-foreground" />
              </div>
              <p className="text-sm font-medium">No keys match the filters</p>
              <p className="text-xs text-muted-foreground">Clear the search or create a new batch.</p>
            </div>
          ) : (
            <ScrollArea className="max-h-96">
              <Table>
                <TableHeader>
                  <TableRow className="hover:bg-transparent">
                    <TableHead>Key id</TableHead>
                    <TableHead>Tier</TableHead>
                    <TableHead>Status</TableHead>
                    <TableHead>Note</TableHead>
                    <TableHead className="text-right">Execs</TableHead>
                    <TableHead>HWID</TableHead>
                    <TableHead>Expires</TableHead>
                    <TableHead className="text-right">Actions</TableHead>
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {rows.map((r) => (
                    <TableRow
                      key={r.id}
                      className="cursor-pointer"
                      onClick={() => setDetail(r)}
                      title="click for key details"
                    >
                      <TableCell className="font-mono text-xs">
                        <button
                          type="button"
                          className="transition-colors hover:text-emerald-600 hover:underline dark:hover:text-emerald-400"
                          onClick={(e) => {
                            e.stopPropagation();
                            copyText(r.id, "Key id copied");
                          }}
                          title="copy id"
                        >
                          {r.id.slice(0, 12)}…
                        </button>
                      </TableCell>
                      <TableCell>
                        <TierBadge tier={r.tier} />
                      </TableCell>
                      <TableCell>
                        <StatusBadge status={r.status} />
                      </TableCell>
                      <TableCell className="max-w-40 truncate text-xs text-muted-foreground">{r.note ?? "—"}</TableCell>
                      <TableCell className="text-right tabular-nums">{r.total_executions}</TableCell>
                      <TableCell className="text-xs">{r.hwid_bound ? `bound (${r.hwid_resets} resets)` : "unbound"}</TableCell>
                      <TableCell className="text-xs">
                        <span className="flex items-center gap-1">
                          <CalendarClock className="h-3 w-3 text-muted-foreground" aria-hidden />
                          {formatTime(r.expires_at)}
                        </span>
                      </TableCell>
                      <TableCell className="text-right">
                        <div className="flex justify-end gap-1">
                          <Button variant="ghost" size="icon" onClick={(e) => { e.stopPropagation(); void revokeKey(r.id); }} disabled={busy || r.status !== "active"} title="revoke" aria-label="revoke key">
                            <ShieldOff className="h-4 w-4 text-destructive" />
                          </Button>
                          <Button variant="ghost" size="icon" onClick={(e) => { e.stopPropagation(); void resetHwid(r.id); }} disabled={busy || !r.hwid_bound} title="reset hwid" aria-label="reset hwid">
                            <Undo2 className="h-4 w-4" />
                          </Button>
                        </div>
                      </TableCell>
                    </TableRow>
                  ))}
                </TableBody>
              </Table>
            </ScrollArea>
          )}
        </CardContent>
      </Card>

      {/* key detail dialog */}
      <Dialog open={detail !== null} onOpenChange={(o) => !o && setDetail(null)}>
        <DialogContent className="sm:max-w-md">
          <DialogHeader>
            <DialogTitle className="flex items-center gap-2">
              <KeyRound className="h-4 w-4 text-emerald-600" /> Key details
            </DialogTitle>
            <DialogDescription>
              {detail && (
                <button
                  type="button"
                  className="font-mono text-xs transition-colors hover:text-emerald-600 dark:hover:text-emerald-400"
                  onClick={() => copyText(detail.id, "Key id copied")}
                >
                  {detail.id}
                </button>
              )}
            </DialogDescription>
          </DialogHeader>
          {detail && (
            <div className="space-y-1">
              <div className="mb-2 flex items-center gap-2">
                <TierBadge tier={detail.tier} />
                <StatusBadge status={detail.status} />
              </div>
              <Separator />
              <DetailRow label="project">{detail.project_id.slice(0, 12)}…</DetailRow>
              <DetailRow label="note">{detail.note ?? "—"}</DetailRow>
              <DetailRow label="executions">{detail.total_executions}</DetailRow>
              <DetailRow label="hwid">{detail.hwid_bound ? `bound · ${detail.hwid_resets} resets` : "unbound"}</DetailRow>
              <DetailRow label="discord">{detail.discord_id ?? "—"}</DetailRow>
              <DetailRow label="roblox">{detail.roblox_user_id ?? "—"}</DetailRow>
              <DetailRow label="created">{formatTime(detail.created_at)}</DetailRow>
              <DetailRow label="expires">{formatTime(detail.expires_at)}</DetailRow>
              <DetailRow label="first use">{formatTime(detail.first_used_at)}</DetailRow>
              <DetailRow label="last use">{formatTime(detail.last_used_at)}</DetailRow>
              <DetailRow label="created by">{detail.created_by}</DetailRow>
              <Separator />
              <div className="flex justify-end gap-2 pt-1">
                {detail.status === "active" && (
                  <Button variant="outline" size="sm" onClick={() => void revokeKey(detail.id)} disabled={busy}>
                    <ShieldOff className="mr-1 h-3.5 w-3.5 text-destructive" /> Revoke
                  </Button>
                )}
                {detail.hwid_bound && (
                  <Button variant="outline" size="sm" onClick={() => void resetHwid(detail.id)} disabled={busy}>
                    <Undo2 className="mr-1 h-3.5 w-3.5" /> Reset HWID
                  </Button>
                )}
              </div>
            </div>
          )}
        </DialogContent>
      </Dialog>

      <Card>
        <CardHeader>
          <CardTitle className="text-sm">Validate a key (real /check_key round trip)</CardTitle>
        </CardHeader>
        <CardContent className="space-y-3">
          <p className="text-xs text-muted-foreground">
            The browser cannot sign SDK requests (x-proof key is a server secret), so this runs the signed request through the real handler and returns its envelope — exactly what an executor SDK sees.
          </p>
          <div className="flex gap-2">
            <Input value={validateKey} onChange={(e) => setValidateKey(e.target.value)} placeholder="YURI-XXXXX-XXXXX-XXXXX-XXXXX-XXXXXX" className="font-mono" />
            <Button onClick={() => void runValidate()} disabled={validating}>
              {validating ? "checking…" : "Check key"}
            </Button>
          </div>
          {validateResult && (
            <div className="rounded-md border p-3 text-sm">
              <div className="flex items-center gap-2">
                <Badge variant={validateResult.code === "KEY_VALID" ? "default" : "destructive"} className={validateResult.code === "KEY_VALID" ? "bg-emerald-600 hover:bg-emerald-600" : ""}>
                  {validateResult.code}
                </Badge>
                <span className="text-muted-foreground">{validateResult.message}</span>
              </div>
              {validateResult.data && <pre className="mt-2 max-h-52 overflow-x-auto rounded bg-muted p-2 text-xs">{JSON.stringify(validateResult.data, null, 2)}</pre>}
            </div>
          )}
        </CardContent>
      </Card>
    </div>
  );
}
