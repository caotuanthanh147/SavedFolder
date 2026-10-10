"use client";

import { useEffect, useState } from "react";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Separator } from "@/components/ui/separator";
import { OverviewView } from "@/components/dashboard/overview";
import { KeysView } from "@/components/dashboard/keys";
import { ScriptsView } from "@/components/dashboard/scripts";
import { UsersView } from "@/components/dashboard/users";
import { SessionsView } from "@/components/dashboard/sessions";
import { BlacklistView } from "@/components/dashboard/blacklist";
import { AuditView } from "@/components/dashboard/audit";
import { ResellersView } from "@/components/dashboard/resellers";
import { NodesView } from "@/components/dashboard/nodes";
import { PaymentsView } from "@/components/dashboard/payments";
import { FreeKeyView } from "@/components/dashboard/freekey";
import { SettingsView } from "@/components/dashboard/settings";
import {
  ShieldCheck,
  BarChart3,
  KeyRound,
  FileCode2,
  Users,
  Stamp,
  Ban,
  ScrollText,
  Store,
  ServerCog,
  Banknote,
  Gift,
  Settings,
  Menu,
  Lock,
} from "lucide-react";

type ViewId =
  | "overview"
  | "keys"
  | "scripts"
  | "users"
  | "resellers"
  | "sessions"
  | "blacklist"
  | "audit"
  | "nodes"
  | "payments"
  | "freekey"
  | "settings";

const NAV: { id: ViewId; label: string; icon: React.ReactNode; group: string }[] = [
  { id: "overview", label: "Overview", icon: <BarChart3 className="h-4 w-4" />, group: "Insights" },
  { id: "keys", label: "Keys", icon: <KeyRound className="h-4 w-4" />, group: "Management" },
  { id: "scripts", label: "Scripts", icon: <FileCode2 className="h-4 w-4" />, group: "Management" },
  { id: "users", label: "Users", icon: <Users className="h-4 w-4" />, group: "Management" },
  { id: "resellers", label: "Resellers", icon: <Store className="h-4 w-4" />, group: "Management" },
  { id: "sessions", label: "Sessions", icon: <Stamp className="h-4 w-4" />, group: "Security" },
  { id: "blacklist", label: "Blacklist", icon: <Ban className="h-4 w-4" />, group: "Security" },
  { id: "audit", label: "Audit log", icon: <ScrollText className="h-4 w-4" />, group: "Security" },
  { id: "payments", label: "Payments", icon: <Banknote className="h-4 w-4" />, group: "Revenue" },
  { id: "freekey", label: "Free-key flow", icon: <Gift className="h-4 w-4" />, group: "Revenue" },
  { id: "nodes", label: "Nodes & protocol", icon: <ServerCog className="h-4 w-4" />, group: "System" },
  { id: "settings", label: "Settings", icon: <Settings className="h-4 w-4" />, group: "System" },
];

const TITLES: Record<ViewId, { title: string; sub: string }> = {
  overview: { title: "Overview", sub: "Live analytics from the real /admin/analytics/overview endpoint" },
  keys: { title: "Keys", sub: "Lifecycle: create, bind, extend, reset HWID, revoke — every mutation audited" },
  scripts: { title: "Scripts", sub: "Versions, activation/rollback, and game routing" },
  users: { title: "Users", sub: "Discord-linked identities across keys: HWID bindings, sessions, usage" },
  resellers: { title: "Resellers", sub: "Quota-capped key sellers with own-keys-only views and audited minting" },
  sessions: { title: "Sessions", sub: "Per-execution session rows with unique watermark ids" },
  blacklist: { title: "Blacklist", sub: "Hashed hwid / ip / roblox_user / discord entries" },
  audit: { title: "Audit log", sub: "Complete mutation history" },
  payments: { title: "Payments", sub: "Module M10 — webhook-verified orders, product mappings, refunds, reconciliation" },
  freekey: { title: "Free-key flow", sub: "The public checkpoint flow (module M9) — drive it end to end" },
  nodes: { title: "Nodes & protocol versions", sub: "Auth hostnames and handler gating" },
  settings: { title: "Settings", sub: "Runtime, TOTP second factor, Discord OAuth" },
};

export default function Home(): React.JSX.Element {
  const [view, setView] = useState<ViewId>("overview");
  const [menuOpen, setMenuOpen] = useState(false);
  const [devMode, setDevMode] = useState<boolean | null>(null);

  useEffect(() => {
    fetch("/api/dash/info", { cache: "no-store" })
      .then((r) => r.json() as Promise<{ dev_mode: boolean }>)
      .then((j) => setDevMode(j.dev_mode))
      .catch(() => setDevMode(false));
  }, []);

  const groups = Array.from(new Set(NAV.map((n) => n.group)));
  const current = TITLES[view];

  return (
    <div className="flex min-h-screen flex-col bg-background text-foreground">
      <header className="sticky top-0 z-40 border-b bg-background/95 backdrop-blur supports-[backdrop-filter]:bg-background/80">
        <div className="mx-auto flex h-14 max-w-7xl items-center gap-3 px-4">
          <Button variant="ghost" size="icon" className="lg:hidden" onClick={() => setMenuOpen((o) => !o)} aria-label="toggle navigation">
            <Menu className="h-5 w-5" />
          </Button>
          <div className="flex items-center gap-2.5">
            <div className="flex h-8 w-8 items-center justify-center rounded-lg bg-gradient-to-br from-emerald-500 to-teal-600 text-white shadow-sm">
              <ShieldCheck className="h-5 w-5" aria-hidden />
            </div>
            <div className="leading-tight">
              <p className="text-sm font-semibold tracking-tight">Yuri Licensing Platform</p>
              <p className="text-xs text-muted-foreground">admin dashboard</p>
            </div>
          </div>
          <div className="ml-auto flex items-center gap-2">
            {devMode === true && (
              <Badge variant="secondary" className="gap-1">
                <span className="inline-block h-1.5 w-1.5 rounded-full bg-amber-500" aria-hidden /> dev mode
              </Badge>
            )}
            {devMode !== null && (
              <Badge variant={devMode ? "outline" : "default"} className={devMode ? "" : "gap-1 bg-emerald-600 hover:bg-emerald-600"}>
                {devMode ? (
                  <>
                    <Lock className="h-3 w-3" aria-hidden /> token injected
                  </>
                ) : (
                  "login required"
                )}
              </Badge>
            )}
            <Badge variant="outline" className="hidden sm:inline-flex">M1 · M9 · M10 · M11</Badge>
          </div>
        </div>
      </header>

      <div className="mx-auto flex w-full max-w-7xl flex-1 gap-6 px-4 py-6">
        <nav aria-label="dashboard sections" className={`${menuOpen ? "block" : "hidden"} w-full shrink-0 lg:block lg:w-56`}>
          <div className="space-y-4 lg:sticky lg:top-20">
            {groups.map((g) => (
              <div key={g}>
                <p className="mb-1.5 px-2 text-[11px] font-semibold uppercase tracking-wider text-muted-foreground/80">{g}</p>
                <div className="space-y-0.5">
                  {NAV.filter((n) => n.group === g).map((n) => (
                    <button
                      key={n.id}
                      onClick={() => {
                        setView(n.id);
                        setMenuOpen(false);
                      }}
                      aria-current={view === n.id ? "page" : undefined}
                      className={`group flex w-full items-center gap-2.5 rounded-md border-l-2 px-2.5 py-2 text-sm transition-colors ${
                        view === n.id
                          ? "border-emerald-600 bg-secondary font-medium text-secondary-foreground"
                          : "border-transparent text-muted-foreground hover:border-emerald-600/40 hover:bg-secondary/60 hover:text-foreground"
                      }`}
                    >
                      <span className={`transition-colors ${view === n.id ? "text-emerald-600 dark:text-emerald-400" : "text-muted-foreground/70 group-hover:text-foreground"}`}>
                        {n.icon}
                      </span>
                      {n.label}
                    </button>
                  ))}
                </div>
                {g !== groups[groups.length - 1] && <Separator className="mt-4 lg:hidden" />}
              </div>
            ))}
          </div>
        </nav>

        <main className="min-w-0 flex-1">
          <div className="mb-5">
            <h1 className="text-2xl font-semibold tracking-tight">{current.title}</h1>
            <p className="text-sm text-muted-foreground">{current.sub}</p>
          </div>
          {view === "overview" && <OverviewView />}
          {view === "keys" && <KeysView />}
          {view === "scripts" && <ScriptsView />}
          {view === "users" && <UsersView />}
          {view === "resellers" && <ResellersView />}
          {view === "sessions" && <SessionsView />}
          {view === "blacklist" && <BlacklistView />}
          {view === "audit" && <AuditView />}
          {view === "payments" && <PaymentsView />}
          {view === "freekey" && <FreeKeyView />}
          {view === "nodes" && <NodesView />}
          {view === "settings" && <SettingsView />}
        </main>
      </div>

      <footer className="mt-auto border-t bg-muted/30">
        <div className="mx-auto flex max-w-7xl flex-wrap items-center justify-between gap-2 px-4 py-4 text-xs text-muted-foreground">
          <p>
            Self-hosted Lua script licensing &amp; protection platform — dashboard (M11) driving the real API core (M1), free-key flow
            (M9) and payments (M10) in-process.
          </p>
          <p className="font-mono">signed envelopes · x-sig verified · audit-logged mutations</p>
        </div>
      </footer>
    </div>
  );
}
