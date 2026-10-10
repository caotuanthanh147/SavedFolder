"use client";

import { useMemo, useState } from "react";
import { toast } from "sonner";
import { Alert, AlertDescription, AlertTitle } from "@/components/ui/alert";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Checkbox } from "@/components/ui/checkbox";
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle, DialogTrigger } from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Separator } from "@/components/ui/separator";
import { Skeleton } from "@/components/ui/skeleton";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { copyText, csvTimestamp, exportCsv } from "@/lib/export-utils";
import { loggedFetch } from "@/lib/api-log";
import { TierBadge, StatusBadge } from "@/components/dashboard/badges";
import { formatTime, gw, KeyRow } from "@/lib/api";
import { useApiData } from "@/lib/use-api-data";
import { ArrowDown, ArrowUp, ArrowUpDown, CalendarClock, CalendarPlus, Copy, Download, FileKey2, KeyRound, Pencil, Plus, RefreshCw, Search, ShieldOff, Undo2, X } from "lucide-react";

const DEMO_PROJECT_ID = "11111111111111111111111111111111";
const DEMO_SCRIPT_ID = "22222222222222222222222222222222";

type SortKey = "created" | "expires" | "execs" | "resets";

function DetailRow({ label, children }: { label: string; children: React.ReactNode }): React.JSX.Element {
  return (
    <div className="flex items-start justify-between gap-4 py-1.5">
      <span className="text-xs text-muted-foreground">{label}</span>
      <span className="text-right font-mono text-xs">{children}</span>
    </div>
  );
}

// Sortable column header: button + aria-sort + direction arrow.
function SortHead({
  label,
  sortKey,
  sort,
  onSort,
  className,
}: {
  label: string;
  sortKey: SortKey;
  sort: { key: SortKey; dir: "asc" | "desc" };
  onSort: (k: SortKey) => void;
  className?: string;
}): React.JSX.Element {
  const active = sort.key === sortKey;
  const ariaSort = active ? (sort.dir === "asc" ? "ascending" : "descending") : "none";
  return (
    <TableHead aria-sort={ariaSort} className={className}>
      <button
        type="button"
        onClick={() => onSort(sortKey)}
        className="inline-flex items-center gap-1 rounded-sm text-[11px] font-medium uppercase tracking-wider text-muted-foreground transition-colors hover:text-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring/50"
        title={`sort by ${label.toLowerCase()}`}
      >
        {label}
        {active ? (
          sort.dir === "asc" ? (
            <ArrowUp className="h-3 w-3 text-emerald-600 dark:text-emerald-400" aria-hidden />
          ) : (
            <ArrowDown className="h-3 w-3 text-emerald-600 dark:text-emerald-400" aria-hidden />
          )
        ) : (
          <ArrowUpDown className="h-3 w-3 opacity-40" aria-hidden />
        )}
      </button>
    </TableHead>
  );
}

export function KeysView({ prefill }: { prefill?: string }): React.JSX.Element {
  const [actionError, setActionError] = useState<string | null>(null);
  const [query, setQuery] = useState(prefill ?? "");
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

  // Column sorting (client-side over the fetched page).
  const [sort, setSort] = useState<{ key: SortKey; dir: "asc" | "desc" }>({ key: "created", dir: "desc" });
  const sortedRows = useMemo(() => {
    if (!rows) return null;
    const out = [...rows];
    const dir = sort.dir === "asc" ? 1 : -1;
    out.sort((a, b) => {
      switch (sort.key) {
        case "execs":
          return (a.total_executions - b.total_executions) * dir;
        case "resets":
          return (a.hwid_resets - b.hwid_resets) * dir;
        case "expires": {
          const av = a.expires_at ?? Number.MAX_SAFE_INTEGER;
          const bv = b.expires_at ?? Number.MAX_SAFE_INTEGER;
          return (av - bv) * dir;
        }
        default:
          return (a.created_at - b.created_at) * dir;
      }
    });
    return out;
  }, [rows, sort]);
  function onSort(k: SortKey): void {
    setSort((s) => (s.key === k ? { key: k, dir: s.dir === "asc" ? "desc" : "asc" } : { key: k, dir: k === "created" || k === "resets" ? "desc" : "asc" }));
  }

  // Multi-select + bulk operations. Requests run sequentially (SQLite writes,
  // one in-flight request) with a single summary toast per batch.
  const [selected, setSelected] = useState<Set<string>>(new Set());
  const [bulkConfirm, setBulkConfirm] = useState(false);
  const [bulkExtendOpen, setBulkExtendOpen] = useState(false);
  const [bulkExtendDays, setBulkExtendDays] = useState("30");
  const [bulkProgress, setBulkProgress] = useState<string | null>(null);
  const selectedRows = useMemo(() => (rows ?? []).filter((r) => selected.has(r.id)), [rows, selected]);

  function toggleRow(id: string): void {
    setSelected((s) => {
      const next = new Set(s);
      if (next.has(id)) next.delete(id);
      else next.add(id);
      return next;
    });
  }
  function toggleAll(): void {
    setSelected((s) => {
      if (sortedRows === null) return s;
      const allSelected = sortedRows.every((r) => s.has(r.id));
      const next = new Set(s);
      for (const r of sortedRows) {
        if (allSelected) next.delete(r.id);
        else next.add(r.id);
      }
      return next;
    });
  }
  const allSelected = (sortedRows?.length ?? 0) > 0 && sortedRows!.every((r) => selected.has(r.id));
  const someSelected = !allSelected && selected.size > 0;

  async function bulkRevoke(): Promise<void> {
    if (selected.size === 0) return;
    setBusy(true);
    setBulkProgress(`0/${selected.size}`);
    let ok = 0;
    const failures: string[] = [];
    const ids = [...selected];
    for (let i = 0; i < ids.length; i++) {
      try {
        await gw("POST", `/admin/keys/${ids[i]}/revoke`, {});
        ok++;
      } catch {
        failures.push(ids[i].slice(0, 8));
      }
      setBulkProgress(`${i + 1}/${ids.length}`);
    }
    setBulkProgress(null);
    setBulkConfirm(false);
    setSelected(new Set());
    if (failures.length === 0) {
      toast.success(`Revoked ${ok} key${ok === 1 ? "" : "s"}`, { description: "Each revoke is a separate audit-logged mutation." });
    } else {
      toast.warning(`Revoked ${ok}, ${failures.length} failed`, { description: `Failed: ${failures.slice(0, 4).join(", ")}${failures.length > 4 ? "…" : ""}` });
    }
    refresh();
    setBusy(false);
  }

  async function bulkExtend(): Promise<void> {
    if (selected.size === 0) return;
    const days = Math.max(1, Math.min(3650, parseInt(bulkExtendDays, 10) || 30));
    setBusy(true);
    setBulkProgress(`0/${selected.size}`);
    let ok = 0;
    const failures: string[] = [];
    const ids = [...selected];
    for (let i = 0; i < ids.length; i++) {
      try {
        await gw("PATCH", `/admin/keys/${ids[i]}`, { extend_days: days });
        ok++;
      } catch {
        failures.push(ids[i].slice(0, 8));
      }
      setBulkProgress(`${i + 1}/${ids.length}`);
    }
    setBulkProgress(null);
    setBulkExtendOpen(false);
    setSelected(new Set());
    if (failures.length === 0) {
      toast.success(`Extended ${ok} key${ok === 1 ? "" : "s"} by ${days}d`, { description: "Server extends from max(expires_at, now) — expired actives renew." });
    } else {
      toast.warning(`Extended ${ok}, ${failures.length} failed`, { description: `Failed: ${failures.slice(0, 4).join(", ")}${failures.length > 4 ? "…" : ""}` });
    }
    refresh();
    setBusy(false);
  }

  const [createOpen, setCreateOpen] = useState(false);
  const [newTier, setNewTier] = useState("paid");
  const [newDays, setNewDays] = useState("30");
  const [newCount, setNewCount] = useState("1");
  const [newNote, setNewNote] = useState("");
  const [createdKeys, setCreatedKeys] = useState<string[] | null>(null);

  const [validateKey, setValidateKey] = useState("");
  const [validateResult, setValidateResult] = useState<{ code: string; message: string; data: unknown } | null>(null);
  const [validating, setValidating] = useState(false);

  // Single-key extend (detail dialog): PATCH extend_days, 1-3650.
  // `daysLeft` is captured at dialog-open time (event handler — Date in
  // handlers is fine; Date in render trips react-hooks/purity + Next 16
  // prerender).
  const [extendOpen, setExtendOpen] = useState(false);
  const [extendDays, setExtendDays] = useState("30");
  const [daysLeft, setDaysLeft] = useState<number | null>(null);
  const [noteDraft, setNoteDraft] = useState<string | null>(null);

  function openExtend(k: KeyRow): void {
    setExtendDays("30");
    setDaysLeft(
      k.expires_at === null
        ? null
        : Math.ceil((k.expires_at - Math.floor(Date.now() / 1000)) / 86400),
    );
    setExtendOpen(true);
  }

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

  async function extendKey(id: string): Promise<void> {
    const days = Math.max(1, Math.min(3650, parseInt(extendDays, 10) || 30));
    setBusy(true);
    try {
      await gw("PATCH", `/admin/keys/${id}`, { extend_days: days });
      toast.success(`Extended ${id.slice(0, 8)}… by ${days}d`, {
        description: "Base is max(expires_at, now) — expired active keys renew from today.",
      });
      setExtendOpen(false);
      refresh();
    } catch (e) {
      const msg = e instanceof Error ? e.message : "extend failed";
      setActionError(msg);
      toast.error("Extend failed", { description: msg });
    } finally {
      setBusy(false);
    }
  }

  async function saveNote(id: string, current: string | null): Promise<void> {
    const next = noteDraft === null ? current : noteDraft.trim().slice(0, 256);
    if (next === (current ?? null)) {
      setNoteDraft(null);
      return;
    }
    setBusy(true);
    try {
      await gw("PATCH", `/admin/keys/${id}`, { note: next === "" ? null : next });
      toast.success("Note updated", { description: `Key ${id.slice(0, 8)}… — PATCH /admin/keys/:id audit-logged.` });
      setNoteDraft(null);
      refresh();
    } catch (e) {
      const msg = e instanceof Error ? e.message : "note update failed";
      setActionError(msg);
      toast.error("Note update failed", { description: msg });
    } finally {
      setBusy(false);
    }
  }

  async function runValidate(): Promise<void> {
    if (validateKey.trim().length === 0) return;
    setValidating(true);
    try {
      const res = await loggedFetch("/api/dash/validate-key", {
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
    if (!sortedRows) return;
    exportCsv(`yuri-keys-${csvTimestamp()}`, ["id", "tier", "status", "note", "executions", "hwid_bound", "hwid_resets", "discord_id", "roblox_user_id", "created_at", "expires_at", "last_used_at", "created_by"], sortedRows.map((r) => [r.id, r.tier, r.status, r.note ?? "", r.total_executions, r.hwid_bound ? "bound" : "unbound", r.hwid_resets, r.discord_id ?? "", r.roblox_user_id ?? "", formatTime(r.created_at), formatTime(r.expires_at), formatTime(r.last_used_at), r.created_by]));
    toast.info("CSV exported", { description: `${sortedRows.length} key rows (current filters + sort).` });
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
        <Button variant="outline" onClick={exportKeysCsv} disabled={!sortedRows || sortedRows.length === 0}>
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

      {/* bulk selection toolbar */}
      {selected.size > 0 && (
        <div className="delta-pop flex flex-wrap items-center gap-2 rounded-lg border border-emerald-600/30 bg-emerald-500/[0.06] px-3 py-2 shadow-sm dark:bg-emerald-500/[0.08]">
          <Badge className="gap-1 bg-emerald-600 hover:bg-emerald-600">
            <KeyRound className="h-3 w-3" aria-hidden /> {selected.size} selected
          </Badge>
          <span className="text-xs text-muted-foreground">{bulkProgress ? `working ${bulkProgress}…` : "sequential requests, one summary toast"}</span>
          <div className="ml-auto flex flex-wrap items-center gap-2">
            <Dialog open={bulkExtendOpen} onOpenChange={setBulkExtendOpen}>
              <Button variant="outline" size="sm" onClick={() => setBulkExtendOpen(true)} disabled={busy}>
                <CalendarPlus className="mr-1 h-3.5 w-3.5" /> Extend…
              </Button>
              <DialogContent className="sm:max-w-sm">
                <DialogHeader>
                  <DialogTitle className="flex items-center gap-2">
                    <CalendarPlus className="h-4 w-4 text-emerald-600" /> Extend {selected.size} key{selected.size === 1 ? "" : "s"}
                  </DialogTitle>
                  <DialogDescription>
                    PATCH /admin/keys/:id with extend_days — the server extends from max(expires_at, now), so expired active keys renew from today. Requests run sequentially.
                  </DialogDescription>
                </DialogHeader>
                <div className="space-y-1">
                  <Label htmlFor="bulk-days">Days (1-3650)</Label>
                  <Input id="bulk-days" type="number" min={1} max={3650} value={bulkExtendDays} onChange={(e) => setBulkExtendDays(e.target.value)} />
                </div>
                <DialogFooter>
                  <Button variant="outline" size="sm" onClick={() => setBulkExtendOpen(false)} disabled={busy}>
                    Cancel
                  </Button>
                  <Button onClick={() => void bulkExtend()} disabled={busy}>
                    {busy ? "extending…" : `Extend ${selected.size} key${selected.size === 1 ? "" : "s"}`}
                  </Button>
                </DialogFooter>
              </DialogContent>
            </Dialog>
            <Dialog open={bulkConfirm} onOpenChange={setBulkConfirm}>
              <Button variant="outline" size="sm" className="border-rose-600/40 text-rose-700 hover:bg-rose-600/10 dark:text-rose-300" onClick={() => setBulkConfirm(true)} disabled={busy}>
                <ShieldOff className="mr-1 h-3.5 w-3.5" /> Revoke…
              </Button>
              <DialogContent className="sm:max-w-sm">
                <DialogHeader>
                  <DialogTitle className="flex items-center gap-2 text-rose-700 dark:text-rose-300">
                    <ShieldOff className="h-4 w-4" /> Revoke {selected.size} key{selected.size === 1 ? "" : "s"}?
                  </DialogTitle>
                  <DialogDescription>
                    Irreversible per key (no un-revoke path — a new key is the remedy). Bound HWIDs stay bound; sessions die on next heartbeat. Every revoke is audit-logged.
                  </DialogDescription>
                </DialogHeader>
                <div className="max-h-40 overflow-auto rounded-md border bg-muted/30 p-2">
                  {selectedRows.map((r) => (
                    <div key={r.id} className="flex items-center justify-between gap-2 py-0.5 font-mono text-xs">
                      <span className="truncate">{r.id.slice(0, 20)}…</span>
                      <TierBadge tier={r.tier} />
                    </div>
                  ))}
                </div>
                <DialogFooter>
                  <Button variant="outline" size="sm" onClick={() => setBulkConfirm(false)} disabled={busy}>
                    Cancel
                  </Button>
                  <Button variant="destructive" onClick={() => void bulkRevoke()} disabled={busy}>
                    {busy ? `revoking ${bulkProgress ?? ""}` : `Revoke ${selected.size}`}
                  </Button>
                </DialogFooter>
              </DialogContent>
            </Dialog>
            <Button variant="ghost" size="sm" onClick={() => setSelected(new Set())} disabled={busy} aria-label="clear selection">
              <X className="mr-1 h-3.5 w-3.5" /> Clear
            </Button>
          </div>
        </div>
      )}

      <Card>
        <CardHeader className="pb-2">
          <CardTitle className="text-sm text-muted-foreground">
            {rows === null
              ? "loading…"
              : `${total} key${total === 1 ? "" : "s"} · hash-only storage, plaintext never returned after creation`}
          </CardTitle>
        </CardHeader>
        <CardContent>
          {sortedRows === null ? (
            <div className="space-y-2">
              {Array.from({ length: 5 }).map((_, i) => (
                <Skeleton key={i} className="skeleton-shimmer h-10" />
              ))}
            </div>
          ) : sortedRows.length === 0 ? (
            <div className="flex flex-col items-center justify-center gap-2 py-12 text-center">
              <div className="flex h-12 w-12 items-center justify-center rounded-full bg-muted">
                <KeyRound className="h-6 w-6 text-muted-foreground" />
              </div>
              <p className="text-sm font-medium">No keys match the filters</p>
              <p className="text-xs text-muted-foreground">Clear the search or create a new batch.</p>
            </div>
          ) : (
            <div className="max-h-96 overflow-auto">
              <Table>
                <TableHeader>
                  <TableRow className="hover:bg-transparent">
                    <TableHead className="w-9 pr-0">
                      <Checkbox
                        checked={allSelected ? true : someSelected ? "indeterminate" : false}
                        onCheckedChange={toggleAll}
                        aria-label={allSelected ? "deselect all rows" : "select all rows"}
                        disabled={busy}
                      />
                    </TableHead>
                    <TableHead>Key id</TableHead>
                    <TableHead>Tier</TableHead>
                    <TableHead>Status</TableHead>
                    <TableHead>Note</TableHead>
                    <SortHead label="Execs" sortKey="execs" sort={sort} onSort={onSort} className="text-right" />
                    <SortHead label="HWID resets" sortKey="resets" sort={sort} onSort={onSort} />
                    <SortHead label="Expires" sortKey="expires" sort={sort} onSort={onSort} />
                    <TableHead className="text-right">Actions</TableHead>
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {sortedRows.map((r) => {
                    const isSel = selected.has(r.id);
                    return (
                    <TableRow
                      key={r.id}
                      className={`cursor-pointer ${isSel ? "row-selected" : ""}`}
                      onClick={() => setDetail(r)}
                      title="click for key details"
                      data-state={isSel ? "selected" : undefined}
                    >
                      <TableCell className="pr-0" onClick={(e) => e.stopPropagation()}>
                        <Checkbox
                          checked={isSel}
                          onCheckedChange={() => toggleRow(r.id)}
                          aria-label={`select key ${r.id.slice(0, 8)}`}
                          disabled={busy}
                        />
                      </TableCell>
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
                      <TableCell className="text-right">{r.total_executions}</TableCell>
                      <TableCell className="text-xs">{r.hwid_resets}</TableCell>
                      <TableCell className="text-xs">
                        <span className="flex items-center gap-1">
                          <CalendarClock className="h-3 w-3 text-muted-foreground" aria-hidden />
                          {formatTime(r.expires_at)}
                        </span>
                      </TableCell>
                      <TableCell className="text-right">
                        <div className="flex justify-end gap-1">
                          <Button variant="ghost" size="icon" onClick={(e) => { e.stopPropagation(); setDetail(r); }} title="details" aria-label="key details">
                            <KeyRound className="h-4 w-4" />
                          </Button>
                          <Button variant="ghost" size="icon" onClick={(e) => { e.stopPropagation(); void revokeKey(r.id); }} disabled={busy || r.status !== "active"} title="revoke" aria-label="revoke key">
                            <ShieldOff className="h-4 w-4 text-destructive" />
                          </Button>
                          <Button variant="ghost" size="icon" onClick={(e) => { e.stopPropagation(); void resetHwid(r.id); }} disabled={busy || !r.hwid_bound} title="reset hwid" aria-label="reset hwid">
                            <Undo2 className="h-4 w-4" />
                          </Button>
                        </div>
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
              <DetailRow label="note">
                {noteDraft !== null ? (
                  <span className="flex items-center gap-1">
                    <Input
                      value={noteDraft}
                      onChange={(e) => setNoteDraft(e.target.value)}
                      maxLength={256}
                      className="h-6 w-40 text-xs"
                      aria-label="edit note"
                    />
                    <Button variant="ghost" size="icon" className="h-6 w-6" onClick={() => void saveNote(detail.id, detail.note)} disabled={busy} title="save note" aria-label="save note">
                      <Pencil className="h-3 w-3 text-emerald-600" />
                    </Button>
                    <Button variant="ghost" size="icon" className="h-6 w-6" onClick={() => setNoteDraft(null)} disabled={busy} title="cancel note edit" aria-label="cancel note edit">
                      <X className="h-3 w-3" />
                    </Button>
                  </span>
                ) : (
                  <span className="flex items-center gap-1">
                    {detail.note ?? "—"}
                    <button
                      type="button"
                      className="text-muted-foreground/60 transition-colors hover:text-foreground"
                      onClick={() => setNoteDraft(detail.note ?? "")}
                      title="edit note (PATCH /admin/keys/:id)"
                      aria-label="edit note"
                    >
                      <Pencil className="h-3 w-3" />
                    </button>
                  </span>
                )}
              </DetailRow>
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
              <div className="flex flex-wrap justify-end gap-2 pt-1">
                {detail.status === "active" && (
                  <Dialog open={extendOpen} onOpenChange={setExtendOpen}>
                    <Button variant="outline" size="sm" onClick={() => openExtend(detail)} disabled={busy}>
                      <CalendarPlus className="mr-1 h-3.5 w-3.5" /> Extend…
                    </Button>
                    <DialogContent className="sm:max-w-sm">
                      <DialogHeader>
                        <DialogTitle className="flex items-center gap-2">
                          <CalendarPlus className="h-4 w-4 text-emerald-600" /> Extend key
                        </DialogTitle>
                        <DialogDescription>
                          PATCH /admin/keys/:id — extend_days adds to max(expires_at, now): expired active keys renew from today, future expiries stack.
                        </DialogDescription>
                      </DialogHeader>
                      <div className="space-y-2">
                        <div className="space-y-1">
                          <Label htmlFor="extend-days">Days (1-3650)</Label>
                          <Input id="extend-days" type="number" min={1} max={3650} value={extendDays} onChange={(e) => setExtendDays(e.target.value)} />
                        </div>
                        <div className="flex flex-wrap gap-1.5">
                          {[7, 30, 90, 365].map((d) => (
                            <Button key={d} type="button" variant="secondary" size="sm" className="h-7" onClick={() => setExtendDays(String(d))}>
                              +{d}d
                            </Button>
                          ))}
                        </div>
                        <p className="text-xs text-muted-foreground">
                          Current expiry: {formatTime(detail.expires_at)}
                          {daysLeft !== null && daysLeft > 0 && <span> · in {daysLeft}d</span>}
                          {daysLeft !== null && daysLeft <= 0 && <span className="font-medium text-amber-600 dark:text-amber-400"> · expired (renews from today)</span>}
                        </p>
                      </div>
                      <DialogFooter>
                        <Button variant="outline" size="sm" onClick={() => setExtendOpen(false)} disabled={busy}>
                          Cancel
                        </Button>
                        <Button onClick={() => void extendKey(detail.id)} disabled={busy}>
                          {busy ? "extending…" : "Extend"}
                        </Button>
                      </DialogFooter>
                    </DialogContent>
                  </Dialog>
                )}
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
              {validateResult.data ? <pre className="mt-2 max-h-52 overflow-x-auto rounded bg-muted p-2 text-xs">{JSON.stringify(validateResult.data, null, 2)}</pre> : null}
            </div>
          )}
        </CardContent>
      </Card>
    </div>
  );
}
