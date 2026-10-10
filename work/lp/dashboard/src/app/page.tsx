"use client";

import { useEffect, useState } from "react";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Separator } from "@/components/ui/separator";
import { OverviewView } from "@/components/dashboard/overview";
import { KeysView } from "@/components/dashboard/keys";
import { ScriptsView } from "@/components/dashboard/scripts";
import { SessionsView } from "@/components/dashboard/sessions";
import { BlacklistView } from "@/components/dashboard/blacklist";
import { AuditView } from "@/components/dashboard/audit";
import { NodesView } from "@/components/dashboard/nodes";
import { FreeKeyView } from "@/components/dashboard/freekey";
import { SettingsView } from "@/components/dashboard/settings";
import { ShieldCheck, BarChart3, KeyRound, FileCode2, Stamp, Ban, ScrollText, ServerCog, Gift, Settings, Menu } from "lucide-react";

type ViewId = "overview" | "keys" | "scripts" | "sessions" | "blacklist" | "audit" | "nodes" | "freekey" | "settings";

const NAV: { id: ViewId; label: string; icon: React.ReactNode; group: string }[] = [
  { id: "overview", label: "Overview", icon: <BarChart3 className="h-4 w-4" />, group: "Admin" },
  { id: "keys", label: "Keys", icon: <KeyRound className="h-4 w-4" />, group: "Admin" },
  { id: "scripts", label: "Scripts", icon: <FileCode2 className="h-4 w-4" />, group: "Admin" },
  { id: "sessions", label: "Sessions", icon: <Stamp className="h-4 w-4" />, group: "Admin" },
  { id: "blacklist", label: "Blacklist", icon: <Ban className="h-4 w-4" />, group: "Admin" },
  { id: "audit", label: "Audit log", icon: <ScrollText className="h-4 w-4" />, group: "Admin" },
  { id: "nodes", label: "Nodes & protocol", icon: <ServerCog className="h-4 w-4" />, group: "Admin" },
  { id: "freekey", label: "Free-key flow", icon: <Gift className="h-4 w-4" />, group: "Public" },
  { id: "settings", label: "Settings", icon: <Settings className="h-4 w-4" />, group: "System" },
];

const TITLES: Record<ViewId, { title: string; sub: string }> = {
  overview: { title: "Overview", sub: "Live analytics from the real /admin/analytics/overview endpoint" },
  keys: { title: "Keys", sub: "Lifecycle: create, bind, extend, reset HWID, revoke — every mutation audited" },
  scripts: { title: "Scripts", sub: "Versions, activation/rollback, and game routing" },
  sessions: { title: "Sessions", sub: "Per-execution session rows with unique watermark ids" },
  blacklist: { title: "Blacklist", sub: "Hashed hwid / ip / roblox_user / discord entries" },
  audit: { title: "Audit log", sub: "Complete mutation history" },
  nodes: { title: "Nodes & protocol versions", sub: "Auth hostnames and handler gating" },
  freekey: { title: "Free-key flow", sub: "The public checkpoint flow (module M9) — drive it end to end" },
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
          <div className="flex items-center gap-2">
            <ShieldCheck className="h-6 w-6" aria-hidden />
            <div className="leading-tight">
              <p className="text-sm font-semibold">Yuri Licensing Platform</p>
              <p className="text-xs text-muted-foreground">admin dashboard</p>
            </div>
          </div>
          <div className="ml-auto flex items-center gap-2">
            {devMode === true && <Badge variant="secondary">dev mode</Badge>}
            {devMode !== null && <Badge variant={devMode ? "outline" : "default"} className={devMode ? "" : "bg-emerald-600 hover:bg-emerald-600"}>{devMode ? "token injected" : "login required"}</Badge>}
            <Badge variant="outline">module M11</Badge>
          </div>
        </div>
      </header>

      <div className="mx-auto flex w-full max-w-7xl flex-1 gap-6 px-4 py-6">
        <nav aria-label="dashboard sections" className={`${menuOpen ? "block" : "hidden"} w-full shrink-0 lg:block lg:w-56`}>
          <div className="space-y-4 lg:sticky lg:top-20">
            {groups.map((g) => (
              <div key={g}>
                <p className="mb-1 px-2 text-xs font-medium uppercase tracking-wide text-muted-foreground">{g}</p>
                <div className="space-y-1">
                  {NAV.filter((n) => n.group === g).map((n) => (
                    <button
                      key={n.id}
                      onClick={() => {
                        setView(n.id);
                        setMenuOpen(false);
                      }}
                      aria-current={view === n.id ? "page" : undefined}
                      className={`flex w-full items-center gap-2 rounded-md px-2 py-2 text-sm transition-colors ${
                        view === n.id ? "bg-secondary font-medium text-secondary-foreground" : "text-muted-foreground hover:bg-secondary/60 hover:text-foreground"
                      }`}
                    >
                      {n.icon}
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
          <div className="mb-4">
            <h1 className="text-2xl font-semibold tracking-tight">{current.title}</h1>
            <p className="text-sm text-muted-foreground">{current.sub}</p>
          </div>
          {view === "overview" && <OverviewView />}
          {view === "keys" && <KeysView />}
          {view === "scripts" && <ScriptsView />}
          {view === "sessions" && <SessionsView />}
          {view === "blacklist" && <BlacklistView />}
          {view === "audit" && <AuditView />}
          {view === "nodes" && <NodesView />}
          {view === "freekey" && <FreeKeyView />}
          {view === "settings" && <SettingsView />}
        </main>
      </div>

      <footer className="mt-auto border-t">
        <div className="mx-auto flex max-w-7xl flex-wrap items-center justify-between gap-2 px-4 py-4 text-xs text-muted-foreground">
          <p>
            Self-hosted Lua script licensing &amp; protection platform — dashboard (M11) driving the real API core (M1) and free-key flow (M9) in-process.
          </p>
          <p>signed envelopes · x-sig verified · audit-logged mutations</p>
        </div>
      </footer>
    </div>
  );
}
