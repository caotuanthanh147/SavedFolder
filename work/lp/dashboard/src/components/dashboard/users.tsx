"use client";

import { useState } from "react";
import { Alert, AlertDescription, AlertTitle } from "@/components/ui/alert";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { Separator } from "@/components/ui/separator";
import { Skeleton } from "@/components/ui/skeleton";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { copyText } from "@/lib/export-utils";
import { TierBadge, StatusBadge } from "@/components/dashboard/badges";
import { AbuseScore, AbuseScoresResponse, formatTime, gw, KeyRow } from "@/lib/api";
import { useApiData } from "@/lib/use-api-data";
import { CalendarClock, Gamepad2, KeyRound, RefreshCw, Search, ShieldAlert, Users } from "lucide-react";

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

function RiskBadge({ score }: { score: AbuseScore }): React.JSX.Element {
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

/** Detail dialog: fetches the key list once and joins client-side so both
 *  discord ids and roblox ids resolve (server-side q only matches discord). */
function UserDetailDialog({ user, onClose }: { user: UserRow | null; onClose: () => void }): React.JSX.Element {
  // Lazy fetcher: resolves empty while no user is selected (no wasted calls),
  // fetches the key list on open — then joins client-side so both discord ids
  // and roblox ids resolve (server-side q only matches discord).
  const { data } = useApiData<{ rows: KeyRow[] }>(
    () => (user === null ? Promise.resolve({ rows: [] as KeyRow[] }) : gw<{ rows: KeyRow[] }>("GET", "/admin/keys?limit=200")),
    [user?.identity],
  );
  // Abuse scores (M7 D-M7-7) joined per key for risk context.
  const { data: scoresData } = useApiData<AbuseScoresResponse>(
    () => (user === null ? Promise.resolve({ now: 0, weights: {}, scores: [] }) : gw<AbuseScoresResponse>("GET", "/admin/abuse-scores")),
    [user?.identity],
  );
  const keys = user === null ? [] : data === null ? null : data.rows.filter((k) =>
    user.kind === "discord" ? k.discord_id === user.identity : String(k.roblox_user_id ?? "") === user.identity,
  );
  const scoreOf = (keyId: string): AbuseScore | null => (scoresData?.scores ?? []).find((s) => s.key_id === keyId) ?? null;

  return (
    <Dialog open={user !== null} onOpenChange={(o) => !o && onClose()}>
      <DialogContent className="sm:max-w-lg">
        <DialogHeader>
          <DialogTitle className="flex items-center gap-2">
            {user?.kind === "discord" ? (
              <Users className="h-4 w-4 text-emerald-600" />
            ) : (
              <Gamepad2 className="h-4 w-4 text-muted-foreground" />
            )}
            User details
          </DialogTitle>
          <DialogDescription>
            {user && (
              <button
                type="button"
                className="font-mono text-xs transition-colors hover:text-emerald-600 dark:hover:text-emerald-400"
                onClick={() => copyText(user.identity, "Identity copied")}
              >
                {user.identity}
              </button>
            )}
          </DialogDescription>
        </DialogHeader>
        {user && (
          <div className="space-y-3">
            <div className="grid grid-cols-4 gap-2 text-center">
              <div className="rounded-md border bg-muted/30 p-2">
                <p className="text-lg font-semibold tabular-nums leading-none">{user.key_count}</p>
                <p className="text-[10px] uppercase tracking-wide text-muted-foreground">keys</p>
              </div>
              <div className="rounded-md border bg-muted/30 p-2">
                <p className="text-lg font-semibold tabular-nums leading-none text-emerald-600 dark:text-emerald-400">{user.active_keys}</p>
                <p className="text-[10px] uppercase tracking-wide text-muted-foreground">active</p>
              </div>
              <div className="rounded-md border bg-muted/30 p-2">
                <p className="text-lg font-semibold tabular-nums leading-none">{user.total_executions}</p>
                <p className="text-[10px] uppercase tracking-wide text-muted-foreground">execs</p>
              </div>
              <div className="rounded-md border bg-muted/30 p-2">
                <p className="text-lg font-semibold tabular-nums leading-none">{user.hwids}</p>
                <p className="text-[10px] uppercase tracking-wide text-muted-foreground">hwids</p>
              </div>
            </div>
            <div className="flex items-center justify-between text-xs text-muted-foreground">
              <span>
                {user.kind} identity · first seen {formatTime(user.first_seen)}
              </span>
              <span>last used {formatTime(user.last_used)}</span>
            </div>
            <Separator />
            <div>
              <p className="mb-1.5 flex items-center gap-1.5 text-xs font-medium text-muted-foreground">
                <KeyRound className="h-3.5 w-3.5" /> Their keys
              </p>
              {keys === null ? (
                <div className="space-y-1.5">
                  <Skeleton className="skeleton-shimmer h-9" />
                  <Skeleton className="skeleton-shimmer h-9" />
                </div>
              ) : keys.length === 0 ? (
                <p className="rounded-md border border-dashed p-3 text-xs text-muted-foreground">
                  No keys matched in the first 200 rows — identities can outlive key deletions (audit history).
                </p>
              ) : (
                <div className="max-h-56 overflow-auto">
                  <Table>
                    <TableHeader>
                      <TableRow className="hover:bg-transparent">
                        <TableHead>Key id</TableHead>
                        <TableHead>Tier</TableHead>
                        <TableHead>Status</TableHead>
                        <TableHead className="text-right">Execs</TableHead>
                        <TableHead>Expires</TableHead>
                        <TableHead>Risk</TableHead>
                      </TableRow>
                    </TableHeader>
                    <TableBody>
                      {keys.map((k) => (
                        <TableRow key={k.id}>
                          <TableCell className="font-mono text-xs">
                            <button
                              type="button"
                              className="transition-colors hover:text-emerald-600 hover:underline dark:hover:text-emerald-400"
                              onClick={() => copyText(k.id, "Key id copied")}
                            >
                              {k.id.slice(0, 12)}…
                            </button>
                          </TableCell>
                          <TableCell>
                            <TierBadge tier={k.tier} />
                          </TableCell>
                          <TableCell>
                            <StatusBadge status={k.status} />
                          </TableCell>
                          <TableCell className="text-right tabular-nums">{k.total_executions}</TableCell>
                          <TableCell className="text-xs">
                            <span className="flex items-center gap-1">
                              <CalendarClock className="h-3 w-3 text-muted-foreground" aria-hidden />
                              {formatTime(k.expires_at)}
                            </span>
                          </TableCell>
                          <TableCell>
                            {(() => {
                              const s = scoreOf(k.id);
                              return s !== null && s.score > 0 ? <RiskBadge score={s} /> : <span className="text-xs text-muted-foreground">clean</span>;
                            })()}
                          </TableCell>
                        </TableRow>
                      ))}
                    </TableBody>
                  </Table>
                </div>
              )}
            </div>
          </div>
        )}
      </DialogContent>
    </Dialog>
  );
}

export function UsersView(): React.JSX.Element {
  const [query, setQuery] = useState("");
  const [detail, setDetail] = useState<UserRow | null>(null);
  const trimmed = query.trim();
  const { data, error, refresh } = useApiData<{ rows: UserRow[] }>(
    () => gw<{ rows: UserRow[] }>("GET", `/admin/users${trimmed.length > 0 ? `?q=${encodeURIComponent(trimmed)}` : ""}`),
    [trimmed],
  );
  // Risk column (M7 D-M7-7): abuse scores joined through the key list so each
  // identity shows its worst active key's band. Scores only list flagged
  // active keys, so most users render no badge (clean by default).
  const { data: riskData } = useApiData<{ keys: KeyRow[]; scores: AbuseScoresResponse }>(async () => {
    const [keys, scores] = await Promise.all([
      gw<{ rows: KeyRow[] }>("GET", "/admin/keys?limit=200"),
      gw<AbuseScoresResponse>("GET", "/admin/abuse-scores"),
    ]);
    return { keys: keys.rows, scores };
  }, []);
  const worstRiskOf = (u: UserRow): AbuseScore | null => {
    if (riskData === null) return null;
    const myKeys = new Set(
      riskData.keys
        .filter((k) => (u.kind === "discord" ? k.discord_id === u.identity : String(k.roblox_user_id ?? "") === u.identity))
        .map((k) => k.id),
    );
    const mine = riskData.scores.scores.filter((s) => myKeys.has(s.key_id));
    if (mine.length === 0) return null;
    return mine.reduce((a, b) => (b.score > a.score ? b : a));
  };
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
          End-user identities aggregated across keys: discord link first, roblox user fallback (doc §16 Users page). Click a row for
          their keys.
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
                <Skeleton key={i} className="skeleton-shimmer h-10" />
              ))}
            </div>
          ) : rows.length === 0 ? (
            <div className="flex flex-col items-center justify-center gap-2 py-12 text-center">
              <div className="flex h-12 w-12 items-center justify-center rounded-full bg-muted">
                <Users className="h-6 w-6 text-muted-foreground" />
              </div>
              <p className="text-sm font-medium">No users found</p>
              <p className="text-xs text-muted-foreground">Identities appear when keys carry a discord id or roblox user.</p>
            </div>
          ) : (
            <div className="max-h-96 overflow-auto">
              <Table>
                <TableHeader>
                  <TableRow className="hover:bg-transparent">
                    <TableHead>Identity</TableHead>
                    <TableHead>Kind</TableHead>
                    <TableHead className="text-right">Keys</TableHead>
                    <TableHead className="text-right">Active</TableHead>
                    <TableHead className="text-right">HWIDs</TableHead>
                    <TableHead className="text-right">Executions</TableHead>
                    <TableHead>First seen</TableHead>
                    <TableHead>Last used</TableHead>
                    <TableHead>Risk</TableHead>
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {rows.map((r) => (
                    <TableRow key={r.kind + ":" + r.identity} className="cursor-pointer" onClick={() => setDetail(r)} title="click for user details">
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
                      <TableCell className="text-right tabular-nums">{r.key_count}</TableCell>
                      <TableCell className="text-right tabular-nums">
                        <span className={r.active_keys > 0 ? "font-medium text-emerald-600 dark:text-emerald-400" : "text-muted-foreground"}>
                          {r.active_keys}
                        </span>
                      </TableCell>
                      <TableCell className="text-right tabular-nums text-muted-foreground">{r.hwids}</TableCell>
                      <TableCell className="text-right tabular-nums text-muted-foreground">{r.total_executions}</TableCell>
                      <TableCell className="text-xs">{formatTime(r.first_seen)}</TableCell>
                      <TableCell className="text-xs">{formatTime(r.last_used)}</TableCell>
                      <TableCell>
                        {(() => {
                          const worst = worstRiskOf(r);
                          return worst !== null && worst.score > 0 ? <RiskBadge score={worst} /> : <span className="text-xs text-muted-foreground">clean</span>;
                        })()}
                      </TableCell>
                    </TableRow>
                  ))}
                </TableBody>
              </Table>
            </div>
          )}
        </CardContent>
      </Card>
      <UserDetailDialog user={detail} onClose={() => setDetail(null)} />
    </div>
  );
}
