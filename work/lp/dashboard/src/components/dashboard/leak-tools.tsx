"use client";

// Module M7 — Leak tools (doc §12): paste a leaked dump (or a clean sealed
// ref / session token / watermark id), the tolerant extractor recovers the
// watermark server-side, and the revoke chain (revoke key + blacklist hwid/ip
// + kill sessions + audit + leak event) runs behind an explicit confirmation.

import { useState } from "react";
import { Alert, AlertDescription, AlertTitle } from "@/components/ui/alert";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Checkbox } from "@/components/ui/checkbox";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { Separator } from "@/components/ui/separator";
import { Skeleton } from "@/components/ui/skeleton";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { TierBadge, StatusBadge } from "@/components/dashboard/badges";
import { copyText } from "@/lib/export-utils";
import {
  AbuseScore,
  AbuseScoresResponse,
  LeakKey,
  LeakLookupResponse,
  LeakRevokeResponse,
  LeakSession,
  formatTime,
  gw,
  shortHash,
} from "@/lib/api";
import { useApiData } from "@/lib/use-api-data";
import { toast } from "sonner";
import {
  Activity,
  CalendarClock,
  Fingerprint,
  Gamepad2,
  Gavel,
  Hash,
  Loader2,
  Search,
  ShieldAlert,
  Users,
} from "lucide-react";

const SOURCE_LABEL: Record<string, string> = {
  sealed_ref: "sealed payload ref",
  session_token: "session token",
  watermark_id: "watermark id",
};

// §11 check names pinned in D-M7-13 (loader/checks/env_checks.lua v1).
const TAMPER_CHECKS = ["identity.changed", "env.changed", "headers.injected", "headers.modified", "timing.inflated"] as const;

const CHECK_HINTS: Record<(typeof TAMPER_CHECKS)[number], string> = {
  "identity.changed": "a critical function's object identity differed from baseline (post-baseline hooking / newcclosure re-wrap)",
  "env.changed": "executor identity, version or syn presence changed since baseline",
  "headers.injected": "a completed request carried a post-call header-table addition outside the taught executor set (§1.2.9)",
  "headers.modified": "an SDK-set header was removed or rewritten mid-call (HTTP spy)",
  "timing.inflated": "median work-unit time ≥ 20× the per-machine baseline (debug-hook single-stepping)",
};

function ScoreBadge({ score }: { score: AbuseScore }): React.JSX.Element {
  const tone =
    score.band === "high"
      ? "border-rose-500/30 bg-rose-500/10 text-rose-600 dark:text-rose-400"
      : score.band === "watch"
        ? "border-amber-500/30 bg-amber-500/10 text-amber-600 dark:text-amber-400"
        : "border-emerald-500/30 bg-emerald-500/10 text-emerald-600 dark:text-emerald-400";
  return (
    <span className={`inline-flex items-center gap-1 rounded-full border px-2 py-0.5 text-[10px] font-medium uppercase tracking-wide ${tone}`}>
      <ShieldAlert className="h-3 w-3" aria-hidden />
      {score.band} · {score.score}
    </span>
  );
}

function SessionTable({ sessions, nowMs }: { sessions: LeakSession[]; nowMs: number }): React.JSX.Element {
  return (
    <div className="max-h-56 overflow-auto">
      <Table>
        <TableHeader>
          <TableRow className="hover:bg-transparent">
            <TableHead>Session</TableHead>
            <TableHead>Script</TableHead>
            <TableHead>HWID hash</TableHead>
            <TableHead>IP hash</TableHead>
            <TableHead>Created</TableHead>
            <TableHead>Expires</TableHead>
          </TableRow>
        </TableHeader>
        <TableBody>
          {sessions.map((s) => (
            <TableRow key={s.id}>
              <TableCell className="font-mono text-xs">
                <button
                  type="button"
                  className="transition-colors hover:text-emerald-600 hover:underline dark:hover:text-emerald-400"
                  onClick={() => copyText(s.id, "Session id copied")}
                  title="click to copy"
                >
                  {s.id.slice(0, 12)}…
                </button>
              </TableCell>
              <TableCell className="font-mono text-xs text-muted-foreground">{s.script_id.slice(0, 8)}…</TableCell>
              <TableCell className="font-mono text-xs text-muted-foreground">{shortHash(s.hwid_hash, 12)}</TableCell>
              <TableCell className="font-mono text-xs text-muted-foreground">{shortHash(s.ip_hash, 12)}</TableCell>
              <TableCell className="text-xs">{formatTime(s.created_at)}</TableCell>
              <TableCell className="text-xs">
                <span className={`flex items-center gap-1 ${s.expires_at * 1000 < nowMs ? "text-muted-foreground" : "text-emerald-600 dark:text-emerald-400"}`}>
                  <CalendarClock className="h-3 w-3" aria-hidden />
                  {formatTime(s.expires_at)}
                </span>
              </TableCell>
            </TableRow>
          ))}
        </TableBody>
      </Table>
    </div>
  );
}

export function LeakToolsView({ prefill }: { prefill?: string }): React.JSX.Element {
  const [artifact, setArtifact] = useState(prefill ?? "");
  const [lookup, setLookup] = useState<LeakLookupResponse | null>(null);
  const [lookupError, setLookupError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [revoked, setRevoked] = useState<LeakRevokeResponse | null>(null);
  const [confirmOpen, setConfirmOpen] = useState(false);
  const [blHwid, setBlHwid] = useState(true);
  const [blIp, setBlIp] = useState(true);
  // Captured in the lookup handler (event-time, not render-time) for the
  // expiry tint in the session table.
  const [lookedAtMs, setLookedAtMs] = useState(0);

  // §11 tamper pipeline demo (M7 s2): pick a check, fire the REAL wire.
  const [checkName, setCheckName] = useState<(typeof TAMPER_CHECKS)[number]>("headers.injected");
  const [checkDetail, setCheckDetail] = useState("");
  const [tamperBusy, setTamperBusy] = useState(false);
  const [tamperResult, setTamperResult] = useState<{
    key_id: string;
    session_token: string;
    watermark_id: string;
    check: string;
    detail: string;
    heartbeat_code: string | null;
    tamper_event_recorded: boolean;
  } | null>(null);

  // Abuse scores for context on the leaked key (D-M7-7): fetched once per
  // lookup result, joined client-side.
  const { data: scoresData } = useApiData<AbuseScoresResponse>(
    () => (lookup === null ? Promise.resolve({ now: 0, weights: {}, scores: [] }) : gw<AbuseScoresResponse>("GET", "/admin/abuse-scores")),
    [lookup?.watermark_id],
  );
  const keyScore = lookup?.key != null ? (scoresData?.scores ?? []).find((s) => s.key_id === lookup.key?.id) ?? null : null;

  async function craftArtifact(): Promise<void> {
    setBusy(true);
    setLookupError(null);
    setLookup(null);
    setRevoked(null);
    try {
      const res = await fetch("/api/dash/craft-leak-artifact", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: "{}",
      });
      if (!res.ok) throw new Error(`craft failed (${res.status})`);
      const data = (await res.json()) as { artifact: string; key_id: string };
      setArtifact(data.artifact);
      toast.success(`Minted key ${data.key_id.slice(0, 10)}… + a real handshake — paste-ready dump below`);
    } catch (e) {
      toast.error(e instanceof Error ? e.message : "craft failed");
    } finally {
      setBusy(false);
    }
  }

  async function runLookup(override?: string): Promise<void> {
    const text = override ?? artifact;
    if (text.trim().length === 0) {
      toast.error("Paste a leaked artifact first");
      return;
    }
    setBusy(true);
    setLookupError(null);
    setLookup(null);
    setRevoked(null);
    try {
      const res = await gw<LeakLookupResponse>("POST", "/admin/leak/lookup", { artifact: text });
      setLookup(res);
      setLookedAtMs(Date.now());
      toast.success(`Watermark recovered — ${SOURCE_LABEL[res.extraction.source] ?? res.extraction.source}`);
    } catch (e) {
      const msg = e instanceof Error ? e.message : "lookup failed";
      setLookupError(msg === "no_watermark" ? "No watermark-bearing artifact found in the input (D-M7-8 carriers: sealed ref, session token, watermark id)." : msg);
      toast.error("Extraction failed");
    } finally {
      setBusy(false);
    }
  }

  async function runRevoke(): Promise<void> {
    if (lookup === null) return;
    setBusy(true);
    try {
      const res = await gw<LeakRevokeResponse>("POST", "/admin/leak/revoke", {
        watermark_id: lookup.watermark_id,
        blacklist_hwid: blHwid,
        blacklist_ip: blIp,
      });
      setRevoked(res);
      setConfirmOpen(false);
      toast.success(res.already_revoked ? "Key was already revoked — no duplicate actions" : `Revoked ${res.key_id.slice(0, 10)}… · blacklisted ${res.blacklisted.join(", ")}`);
    } catch (e) {
      toast.error(e instanceof Error ? e.message : "revoke failed");
    } finally {
      setBusy(false);
    }
  }

  // §11 pipeline: mint → real handshake → heartbeat tamper report → the
  // event lands server-side (silent to the client — the heartbeat answered
  // a normal envelope).
  async function fireTamper(): Promise<void> {
    setTamperBusy(true);
    setTamperResult(null);
    try {
      const res = await fetch("/api/dash/simulate-tamper", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ check: checkName, detail: checkDetail || undefined }),
      });
      if (!res.ok) throw new Error(`tamper sim failed (${res.status})`);
      const data = (await res.json()) as NonNullable<typeof tamperResult>;
      setTamperResult(data);
      toast.success(
        data.tamper_event_recorded
          ? `Tamper event recorded — heartbeat answered ${data.heartbeat_code ?? "…"} (silent, §11)`
          : `Heartbeat answered ${data.heartbeat_code ?? "…"} but no tamper event found — investigate`,
      );
    } catch (e) {
      toast.error(e instanceof Error ? e.message : "tamper sim failed");
    } finally {
      setTamperBusy(false);
    }
  }

  const key: LeakKey | null = lookup?.key ?? null;

  return (
    <div className="space-y-4">
      <Card>
        <CardHeader className="pb-3">
          <CardTitle className="flex items-center gap-2 text-sm text-muted-foreground">
            <Fingerprint className="h-4 w-4" />
            Watermark extractor (D-M7-8)
          </CardTitle>
        </CardHeader>
        <CardContent className="space-y-3">
          <textarea
            value={artifact}
            onChange={(e) => setArtifact(e.target.value)}
            placeholder={"Paste the leaked dump — a sealed payload ref, a session token, a raw watermark id, or arbitrary text (logs, JSON, chat messages) containing one…"}
            aria-label="leaked artifact"
            rows={4}
            className="w-full resize-y rounded-md border bg-transparent px-3 py-2 font-mono text-xs outline-none placeholder:text-muted-foreground focus-visible:ring-2 focus-visible:ring-ring/50"
          />
          <div className="flex flex-wrap items-center gap-2">
            <Button onClick={() => void runLookup()} disabled={busy} size="sm">
              {busy ? <Loader2 className="h-4 w-4 animate-spin" aria-hidden /> : <Search className="h-4 w-4" aria-hidden />}
              Extract &amp; correlate
            </Button>
            <Button variant="outline" size="sm" onClick={() => void craftArtifact()} disabled={busy} className="gap-1.5">
              <Fingerprint className="h-4 w-4" aria-hidden />
              Craft demo leak (real handshake)
            </Button>
            <Button
              variant="ghost"
              size="sm"
              onClick={() => {
                setArtifact("");
                setLookup(null);
                setLookupError(null);
                setRevoked(null);
              }}
            >
              Clear
            </Button>
            <p className="text-xs text-muted-foreground">
              Tolerant scan: candidates are grepped out of messy text and classified (sealed ref → session token → watermark id).
            </p>
          </div>
        </CardContent>
      </Card>

      {lookupError !== null && (
        <Alert variant="destructive">
          <AlertTitle>No watermark recovered</AlertTitle>
          <AlertDescription>{lookupError}</AlertDescription>
        </Alert>
      )}

      <Card>
        <CardHeader className="pb-3">
          <CardTitle className="flex items-center gap-2 text-sm text-muted-foreground">
            <Activity className="h-4 w-4" />
            §11 tamper pipeline (D-M7-6 wire · env_checks.lua v1)
          </CardTitle>
        </CardHeader>
        <CardContent className="space-y-3">
          <p className="text-xs text-muted-foreground">
            Fires the exact wire <span className="font-mono">loader/checks/env_checks.lua</span> produces in production: mint → real X25519 handshake → heartbeat carrying the silent{" "}
            <span className="font-mono">tamper</span> field. The server records a <span className="font-mono">client:&lt;check&gt;</span> event and answers a normal envelope — the client never learns it was acted on.
          </p>
          <div className="flex flex-wrap items-center gap-2">
            <Select value={checkName} onValueChange={(v) => setCheckName(v as (typeof TAMPER_CHECKS)[number])}>
              <SelectTrigger className="h-8 w-52 font-mono text-xs" aria-label="§11 check">
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                {TAMPER_CHECKS.map((c) => (
                  <SelectItem key={c} value={c} className="font-mono text-xs">
                    {c}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
            <input
              value={checkDetail}
              onChange={(e) => setCheckDetail(e.target.value)}
              placeholder="detail (optional, ≤128 chars)"
              aria-label="tamper check detail"
              className="h-8 w-56 rounded-md border bg-transparent px-2.5 font-mono text-xs outline-none placeholder:text-muted-foreground focus-visible:ring-2 focus-visible:ring-ring/50"
            />
            <Button size="sm" onClick={fireTamper} disabled={tamperBusy} className="gap-1.5">
              {tamperBusy ? <Loader2 className="h-4 w-4 animate-spin" aria-hidden /> : <Activity className="h-4 w-4" aria-hidden />}
              Fire tamper report (real heartbeat)
            </Button>
          </div>
          <p className="rounded-md border bg-muted/30 px-2.5 py-1.5 text-[11px] leading-relaxed text-muted-foreground">
            <span className="font-mono">{checkName}</span> — {CHECK_HINTS[checkName]}
          </p>
          {tamperResult !== null && (
            <div className="space-y-2 rounded-md border p-3">
              <div className="flex flex-wrap items-center gap-2">
                <Badge variant={tamperResult.tamper_event_recorded ? "destructive" : "secondary"} className="gap-1">
                  <ShieldAlert className="h-3 w-3" aria-hidden />
                  {tamperResult.tamper_event_recorded ? "tamper event recorded" : "no event found"}
                </Badge>
                <Badge variant="secondary" className="font-mono text-[10px]">
                  heartbeat → {tamperResult.heartbeat_code ?? "?"}
                </Badge>
                <span className="font-mono text-xs text-muted-foreground">
                  key {tamperResult.key_id.slice(0, 10)}… · check {tamperResult.check}
                </span>
                <Button
                  variant="outline"
                  size="sm"
                  className="ml-auto h-7 gap-1.5"
                  onClick={() => {
                    setArtifact(tamperResult.session_token);
                    setTamperResult(null);
                    void runLookup(tamperResult.session_token);
                  }}
                >
                  <Search className="h-3.5 w-3.5" aria-hidden />
                  Correlate in extractor
                </Button>
              </div>
              <p className="font-mono text-[11px] text-muted-foreground">
                session {tamperResult.session_token} → event detail{" "}
                <span className="text-rose-600 dark:text-rose-400">client:{tamperResult.check}:{tamperResult.detail}</span> (feeds the abuse score, D-M7-7)
              </p>
            </div>
          )}
        </CardContent>
      </Card>

      {busy && lookup === null && lookupError === null && (
        <div className="space-y-2">
          <Skeleton className="skeleton-shimmer h-24" />
          <Skeleton className="skeleton-shimmer h-40" />
        </div>
      )}

      {lookup !== null && (
        <>
          <Card>
            <CardHeader className="pb-3">
              <CardTitle className="flex flex-wrap items-center gap-2 text-sm">
                <Fingerprint className="h-4 w-4 text-emerald-600 dark:text-emerald-400" />
                <span className="font-mono">{lookup.watermark_id}</span>
                <Badge variant="secondary" className="gap-1">
                  <Hash className="h-3 w-3" aria-hidden />
                  {SOURCE_LABEL[lookup.extraction.source] ?? lookup.extraction.source}
                </Badge>
                {keyScore !== null && <ScoreBadge score={keyScore} />}
                <button
                  type="button"
                  className="ml-auto text-xs text-muted-foreground transition-colors hover:text-emerald-600 dark:hover:text-emerald-400"
                  onClick={() => copyText(lookup.watermark_id, "Watermark copied")}
                >
                  copy
                </button>
              </CardTitle>
            </CardHeader>
            <CardContent className="space-y-3">
              {key !== null ? (
                <div className="grid gap-2 sm:grid-cols-2 lg:grid-cols-4">
                  <div className="rounded-md border bg-muted/30 p-2.5">
                    <p className="text-[10px] uppercase tracking-wide text-muted-foreground">key</p>
                    <button
                      type="button"
                      className="font-mono text-xs transition-colors hover:text-emerald-600 hover:underline dark:hover:text-emerald-400"
                      onClick={() => copyText(key.id, "Key id copied")}
                    >
                      {key.id.slice(0, 14)}…
                    </button>
                    <div className="mt-1 flex gap-1">
                      <TierBadge tier={key.tier} />
                      <StatusBadge status={key.status} />
                    </div>
                  </div>
                  <div className="rounded-md border bg-muted/30 p-2.5">
                    <p className="text-[10px] uppercase tracking-wide text-muted-foreground">discord</p>
                    <p className="flex items-center gap-1 font-mono text-xs">
                      <Users className="h-3 w-3 text-muted-foreground" aria-hidden />
                      {key.discord_id ?? "—"}
                    </p>
                    <p className="mt-1.5 text-[10px] uppercase tracking-wide text-muted-foreground">roblox</p>
                    <p className="flex items-center gap-1 font-mono text-xs">
                      <Gamepad2 className="h-3 w-3 text-muted-foreground" aria-hidden />
                      {key.roblox_user_id ?? "—"}
                    </p>
                  </div>
                  <div className="rounded-md border bg-muted/30 p-2.5">
                    <p className="text-[10px] uppercase tracking-wide text-muted-foreground">note</p>
                    <p className="truncate text-xs" title={key.note ?? undefined}>{key.note ?? "—"}</p>
                    <p className="mt-1.5 text-[10px] uppercase tracking-wide text-muted-foreground">expires</p>
                    <p className="text-xs">{formatTime(key.expires_at)}</p>
                  </div>
                  <div className="rounded-md border bg-muted/30 p-2.5">
                    <p className="text-[10px] uppercase tracking-wide text-muted-foreground">hwid hash</p>
                    <p className="font-mono text-xs">{shortHash(key.hwid_hash, 16)}</p>
                    <p className="mt-1.5 text-[10px] uppercase tracking-wide text-muted-foreground">revoke state</p>
                    {revoked !== null ? (
                      <p className="text-xs font-medium text-rose-600 dark:text-rose-400">
                        revoked{revoked.already_revoked ? " (previous)" : ""} · {revoked.blacklisted.length > 0 ? revoked.blacklisted.join(" + ") : "no blacklist"}
                      </p>
                    ) : key.status === "revoked" ? (
                      <p className="text-xs font-medium text-rose-600 dark:text-rose-400">revoked (before this lookup)</p>
                    ) : (
                      <p className="text-xs text-muted-foreground">active</p>
                    )}
                  </div>
                </div>
              ) : (
                <p className="rounded-md border border-dashed p-3 text-xs text-muted-foreground">
                  Session carried no bound key (free/keyless session) — blacklist manually from the session hashes below.
                </p>
              )}

              <Separator />

              <div>
                <p className="mb-1.5 text-xs font-medium text-muted-foreground">
                  Sessions carrying this watermark ({lookup.sessions.length})
                </p>
                {lookup.sessions.length > 0 ? (
                  <SessionTable sessions={lookup.sessions} nowMs={lookedAtMs} />
                ) : (
                  <p className="rounded-md border border-dashed p-3 text-xs text-muted-foreground">No session rows (pruned) — the watermark stands alone.</p>
                )}
              </div>

              <Separator />

              <div>
                <p className="mb-1.5 text-xs font-medium text-muted-foreground">Recent events on the key</p>
                <div className="max-h-40 space-y-1 overflow-auto">
                  {lookup.events.length === 0 ? (
                    <p className="rounded-md border border-dashed p-3 text-xs text-muted-foreground">No events.</p>
                  ) : (
                    lookup.events.map((e, i) => (
                      <div key={i} className="flex items-center gap-2 rounded-md border bg-muted/20 px-2 py-1 text-xs">
                        <Badge variant={e.type === "tamper" || e.type === "leak" ? "destructive" : "secondary"} className="text-[10px]">
                          {e.type}
                        </Badge>
                        <span className="font-mono text-[11px] text-muted-foreground">{e.detail ?? "—"}</span>
                        <span className="ml-auto text-[10px] text-muted-foreground">{formatTime(e.created_at)}</span>
                      </div>
                    ))
                  )}
                </div>
              </div>

              {key !== null && key.status !== "revoked" && revoked === null && (
                <Button variant="destructive" size="sm" onClick={() => setConfirmOpen(true)} className="gap-1.5">
                  <Gavel className="h-4 w-4" aria-hidden />
                  Run revoke chain
                </Button>
              )}
              {revoked !== null && (
                <Alert>
                  <AlertTitle>Revoke chain executed</AlertTitle>
                  <AlertDescription>
                    Key {revoked.key_id.slice(0, 12)}… revoked · blacklisted: {revoked.blacklisted.length > 0 ? revoked.blacklisted.join(", ") : "none"} · live sessions killed · audit + leak event written (M8 notify lane).
                  </AlertDescription>
                </Alert>
              )}
            </CardContent>
          </Card>
        </>
      )}

      <Dialog open={confirmOpen} onOpenChange={setConfirmOpen}>
        <DialogContent className="sm:max-w-md">
          <DialogHeader>
            <DialogTitle className="flex items-center gap-2">
              <Gavel className="h-4 w-4 text-rose-600 dark:text-rose-400" />
              Confirm the revoke chain
            </DialogTitle>
            <DialogDescription>
              This is the doc §12 leak workflow: revoke the key, blacklist the session&apos;s hashes, kill live sessions, write audit + leak events. False positives revoke paying users — verify the source first.
            </DialogDescription>
          </DialogHeader>
          <div className="space-y-2.5">
            <label className="flex cursor-pointer items-center gap-2 text-sm">
              <Checkbox checked={blHwid} onCheckedChange={(v) => setBlHwid(v === true)} aria-label="blacklist hwid" />
              Blacklist the session&apos;s HWID hash
            </label>
            <label className="flex cursor-pointer items-center gap-2 text-sm">
              <Checkbox checked={blIp} onCheckedChange={(v) => setBlIp(v === true)} aria-label="blacklist ip" />
              Blacklist the session&apos;s IP hash
            </label>
            <p className="rounded-md border border-amber-500/30 bg-amber-500/10 p-2 text-xs text-amber-700 dark:text-amber-400">
              Idempotent: re-running reports the current state without duplicate blacklist rows.
            </p>
          </div>
          <DialogFooter>
            <Button variant="outline" size="sm" onClick={() => setConfirmOpen(false)}>
              Cancel
            </Button>
            <Button variant="destructive" size="sm" onClick={runRevoke} disabled={busy}>
              {busy ? <Loader2 className="h-4 w-4 animate-spin" aria-hidden /> : <Gavel className="h-4 w-4" aria-hidden />}
              Revoke now
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </div>
  );
}
