"use client";

// LiveAlerts (M11 s9) — the dashboard's security nerve center.
//
// An independent light poller (25s) watches TWO real signals:
//   1. GET /admin/audit?limit=50      — the admin/mutation feed
//   2. GET /admin/analytics/overview  — the tamper_24h counter. Heartbeat
//      tamper events (§11) land in the leak-events store, NOT audit_log,
//      so the rolling counter is the only signal that catches them.
//
// The FIRST poll is a silent baseline (no toast spam for history). After
// that, security-relevant audit entries ring a toast with an "Investigate"
// action and land in the bell feed; routine admin actions never toast.
// When tamper_24h increases between polls, a critical toast fires even
// though no audit row exists for it.
//
// Mute is session-only and lifted to page.tsx so the command palette can
// toggle it too. All toasts fire inside the settle callback (event time,
// never render). relTime is client-only — the feed renders after the first
// settle, so Date.now() there is hydration-safe.

import { useEffect, useRef, useState } from "react";
import { toast } from "sonner";
import { Button } from "@/components/ui/button";
import { Popover, PopoverContent, PopoverTrigger } from "@/components/ui/popover";
import { Switch } from "@/components/ui/switch";
import { AnalyticsOverview, AuditEntry, gw } from "@/lib/api";
import { relTime } from "@/components/dashboard/audit";
import { Bell, BellOff, BellRing, CheckCheck, Fingerprint, RefreshCw, ShieldAlert } from "lucide-react";

export type AlertDrilldown = "leak" | "blacklist" | "keys" | "audit";

export interface SecurityAlert {
  id: string;
  severity: "critical" | "warning" | "info";
  title: string;
  detail: string;
  at: number;
  view: AlertDrilldown;
}

// Audit actions worth ringing a bell for. Everything else is skipped —
// the Overview timeline already covers routine activity.
function classify(action: string): { severity: SecurityAlert["severity"]; title: string; view: AlertDrilldown } | null {
  if (action === "admin.leak.revoke") return { severity: "critical", title: "Leak response — key revoked", view: "leak" };
  if (action.startsWith("blacklist")) return { severity: "warning", title: "Blacklist entry added", view: "blacklist" };
  if (action === "admin.key.revoke" || action === "key.revoke") return { severity: "info", title: "Key revoked", view: "keys" };
  if (action.includes("reset_hwid") || action === "hwid.reset") return { severity: "info", title: "HWID reset", view: "keys" };
  if (action.startsWith("admin.leak") || action.includes("tamper")) return { severity: "critical", title: action, view: "leak" };
  return null;
}

const SEVERITY_DOT: Record<SecurityAlert["severity"], string> = {
  critical: "bg-rose-500",
  warning: "bg-amber-500",
  info: "bg-sky-500",
};

const SEVERITY_ROW: Record<SecurityAlert["severity"], string> = {
  critical: "border-l-rose-500/70 bg-rose-500/[0.06]",
  warning: "border-l-amber-500/70 bg-amber-500/[0.06]",
  info: "border-l-sky-500/60 bg-sky-500/[0.04]",
};

export function LiveAlertsBell({
  muted,
  onMutedChange,
  onNavigate,
}: {
  muted: boolean;
  onMutedChange: (m: boolean) => void;
  onNavigate: (v: AlertDrilldown) => void;
}): React.JSX.Element {
  const [alerts, setAlerts] = useState<SecurityAlert[]>([]);
  const [unread, setUnread] = useState(0);
  const [open, setOpen] = useState(false);
  const [tick, setTick] = useState(0);

  // Baseline bookkeeping — first poll marks everything seen; afterwards
  // only unseen entry ids (and tamper_24h increases) produce alerts.
  const seen = useRef<Set<string> | null>(null);
  const prevTamper = useRef<number | null>(null);
  const mutedRef = useRef(muted);
  useEffect(() => {
    mutedRef.current = muted;
  }, [muted]);
  const navRef = useRef(onNavigate);
  useEffect(() => {
    navRef.current = onNavigate;
  });

  // 25s heartbeat (setState inside the interval callback — lint-safe).
  useEffect(() => {
    const t = setInterval(() => setTick((x) => x + 1), 25000);
    return () => clearInterval(t);
  }, []);

  // The poll itself. Runs on mount (baseline) and on every tick/refresh.
  useEffect(() => {
    let active = true;
    (async () => {
      try {
        const [auditRes, analytics] = await Promise.all([
          gw<{ entries: AuditEntry[] }>("GET", "/admin/audit?limit=50"),
          gw<AnalyticsOverview>("GET", "/admin/analytics/overview"),
        ]);
        if (!active) return;

        const fresh: SecurityAlert[] = [];
        const entries = auditRes.entries;
        const seenSet = seen.current;
        if (seenSet === null) {
          // Baseline: swallow history silently.
          seen.current = new Set(entries.map((e) => e.id));
        } else {
          const newOnes = entries.filter((e) => !seenSet.has(e.id));
          for (const e of newOnes) seenSet.add(e.id);
          for (const e of newOnes) {
            const c = classify(e.action);
            if (c === null) continue;
            fresh.push({
              id: e.id,
              severity: c.severity,
              title: c.title,
              detail: `${e.action}${e.target !== null ? ` · ${e.target.slice(0, 18)}` : ""} · ${e.actor_id.slice(0, 12)}`,
              at: e.created_at,
              view: c.view,
            });
          }
        }

        // Tamper counter: catches §11 heartbeat tamper reports that never
        // touch audit_log. Only INCREASES ring (the 24h window also sheds).
        let tamperAlert: SecurityAlert | null = null;
        if (prevTamper.current !== null && analytics.tamper_24h > prevTamper.current) {
          tamperAlert = {
            id: `tamper-${analytics.tamper_24h}-${tick}`,
            severity: "critical",
            title: "Tamper event detected",
            detail: `§11 silent tamper report · ${analytics.tamper_24h} in the 24h window`,
            at: Math.floor(Date.now() / 1000),
            view: "leak",
          };
        }
        prevTamper.current = analytics.tamper_24h;

        const incoming = [tamperAlert, ...fresh].filter((a): a is SecurityAlert => a !== null);
        if (incoming.length > 0) {
          setAlerts((prev) => [...incoming, ...prev].slice(0, 30));
          setUnread((u) => Math.min(u + incoming.length, 99));
          if (!mutedRef.current) {
            for (const a of incoming) {
              if (a.severity === "critical") {
                toast.error(a.title, {
                  description: a.detail,
                  action: { label: "Investigate", onClick: () => navRef.current(a.view) },
                });
              } else if (a.severity === "warning") {
                toast.warning(a.title, {
                  description: a.detail,
                  action: { label: "Review", onClick: () => navRef.current(a.view) },
                });
              }
            }
          }
        }
      } catch {
        // Silent — views surface API errors; the bell must never nag.
      }
    })();
    return () => {
      active = false;
    };
  }, [tick]);

  function markAllRead(): void {
    setUnread(0);
  }

  const BellIcon = muted ? BellOff : unread > 0 ? BellRing : Bell;

  return (
    <Popover open={open} onOpenChange={setOpen}>
      <PopoverTrigger asChild>
        <Button
          variant="ghost"
          size="icon"
          className="relative h-8 w-8"
          aria-label={unread > 0 ? `security alerts — ${unread} unread` : muted ? "security alerts (muted)" : "security alerts — no unread"}
        >
          <BellIcon className={`h-4 w-4 ${unread > 0 ? "text-rose-600 dark:text-rose-400" : ""}`} />
          {unread > 0 && (
            <span
              className="absolute -right-0.5 -top-0.5 flex h-4 min-w-4 items-center justify-center rounded-full bg-rose-600 px-1 text-[10px] font-bold tabular-nums text-white shadow-sm"
              aria-hidden
            >
              {unread > 9 ? "9+" : unread}
            </span>
          )}
        </Button>
      </PopoverTrigger>
      <PopoverContent align="end" className="w-96 p-0">
        <div className="flex items-center justify-between border-b px-3 py-2.5">
          <p className="flex items-center gap-1.5 text-sm font-semibold">
            <ShieldAlert className="h-4 w-4 text-rose-600 dark:text-rose-400" aria-hidden />
            Security alerts
            {unread > 0 && (
              <span className="rounded-full bg-rose-600/15 px-1.5 py-0.5 text-[10px] font-bold tabular-nums text-rose-700 dark:text-rose-300">
                {unread} unread
              </span>
            )}
          </p>
          <div className="flex items-center gap-2">
            <Button
              variant="ghost"
              size="icon"
              className="h-6 w-6"
              onClick={() => setTick((x) => x + 1)}
              aria-label="check for alerts now"
              title="check for alerts now (otherwise every 25s)"
            >
              <RefreshCw className="h-3.5 w-3.5" />
            </Button>
            {unread > 0 && (
              <Button variant="ghost" size="icon" className="h-6 w-6" onClick={markAllRead} aria-label="mark all read" title="mark all read">
                <CheckCheck className="h-3.5 w-3.5" />
              </Button>
            )}
          </div>
        </div>
        <div className="flex items-center justify-between gap-2 border-b bg-muted/40 px-3 py-2">
          <label htmlFor="alerts-mute" className="flex items-center gap-2 text-xs text-muted-foreground">
            <BellOff className="h-3.5 w-3.5" aria-hidden />
            Mute toasts for this session
          </label>
          <Switch id="alerts-mute" checked={muted} onCheckedChange={onMutedChange} aria-label="mute alert toasts" />
        </div>
        <div className="max-h-80 overflow-auto p-2">
          {alerts.length === 0 ? (
            <div className="flex flex-col items-center justify-center gap-2 px-6 py-10 text-center">
              <div className="flex h-11 w-11 items-center justify-center rounded-full bg-emerald-500/10">
                <ShieldAlert className="h-5 w-5 text-emerald-600 dark:text-emerald-400" aria-hidden />
              </div>
              <p className="text-sm font-medium">All quiet</p>
              <p className="text-xs text-muted-foreground">
                Baseline established — new tamper, leak, blacklist and revoke activity will ring the bell here.
              </p>
            </div>
          ) : (
            <ul className="space-y-1.5">
              {alerts.map((a) => (
                <li key={a.id}>
                  <button
                    type="button"
                    onClick={() => {
                      markAllRead();
                      setOpen(false);
                      navRef.current(a.view);
                    }}
                    className={`alert-row w-full rounded-md border-l-2 px-2.5 py-2 text-left transition-colors hover:bg-muted ${SEVERITY_ROW[a.severity]}`}
                    aria-label={`${a.title} — open the ${a.view} view`}
                  >
                    <span className="flex items-center gap-2">
                      <span className={`inline-block h-1.5 w-1.5 shrink-0 rounded-full ${SEVERITY_DOT[a.severity]}`} aria-hidden />
                      <span className="min-w-0 flex-1 truncate text-xs font-medium">{a.title}</span>
                      <span className="shrink-0 text-[10px] tabular-nums text-muted-foreground">{relTime(a.at)}</span>
                    </span>
                    <span className="mt-1 flex items-center gap-1.5 pl-3.5">
                      {a.severity === "critical" ? (
                        <Fingerprint className="h-3 w-3 shrink-0 text-rose-600 dark:text-rose-400" aria-hidden />
                      ) : null}
                      <span className="truncate font-mono text-[10px] text-muted-foreground">{a.detail}</span>
                    </span>
                  </button>
                </li>
              ))}
            </ul>
          )}
        </div>
        <p className="border-t px-3 py-2 text-[10px] text-muted-foreground">
          Watches <code className="rounded bg-muted px-1 font-mono">/admin/audit</code> +{" "}
          <code className="rounded bg-muted px-1 font-mono">tamper_24h</code> every 25s — toasts only for tamper, leak and blacklist signals.
        </p>
      </PopoverContent>
    </Popover>
  );
}
