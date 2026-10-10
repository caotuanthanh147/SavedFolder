"use client";

import { useCallback, useEffect, useState } from "react";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Kbd } from "@/components/ui/kbd";
import { Separator } from "@/components/ui/separator";
import { Tooltip, TooltipContent, TooltipTrigger } from "@/components/ui/tooltip";
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
import { ThemeToggle } from "@/components/dashboard/theme-toggle";
import { CommandPalette, type Command } from "@/components/dashboard/command-palette";
import { ApiInspectorButton, ApiInspectorPanel, ApiProgressBar } from "@/components/dashboard/api-inspector";
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
  Search,
  Command as CommandIcon,
  Activity,
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

const NAV: { id: ViewId; label: string; icon: React.ReactNode; group: string; hint: string }[] = [
  { id: "overview", label: "Overview", icon: <BarChart3 className="h-4 w-4" />, group: "Insights", hint: "analytics" },
  { id: "keys", label: "Keys", icon: <KeyRound className="h-4 w-4" />, group: "Management", hint: "licenses" },
  { id: "scripts", label: "Scripts", icon: <FileCode2 className="h-4 w-4" />, group: "Management", hint: "versions" },
  { id: "users", label: "Users", icon: <Users className="h-4 w-4" />, group: "Management", hint: "identities" },
  { id: "resellers", label: "Resellers", icon: <Store className="h-4 w-4" />, group: "Management", hint: "quota" },
  { id: "sessions", label: "Sessions", icon: <Stamp className="h-4 w-4" />, group: "Security", hint: "watermarks" },
  { id: "blacklist", label: "Blacklist", icon: <Ban className="h-4 w-4" />, group: "Security", hint: "bans" },
  { id: "audit", label: "Audit log", icon: <ScrollText className="h-4 w-4" />, group: "Security", hint: "history" },
  { id: "payments", label: "Payments", icon: <Banknote className="h-4 w-4" />, group: "Revenue", hint: "orders" },
  { id: "freekey", label: "Free-key flow", icon: <Gift className="h-4 w-4" />, group: "Revenue", hint: "checkpoints" },
  { id: "nodes", label: "Nodes & protocol", icon: <ServerCog className="h-4 w-4" />, group: "System", hint: "hosts" },
  { id: "settings", label: "Settings", icon: <Settings className="h-4 w-4" />, group: "System", hint: "totp" },
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
  const [paletteOpen, setPaletteOpen] = useState(false);
  const [inspectorOpen, setInspectorOpen] = useState(false);

  useEffect(() => {
    fetch("/api/dash/info", { cache: "no-store" })
      .then((r) => r.json() as Promise<{ dev_mode: boolean }>)
      .then((j) => setDevMode(j.dev_mode))
      .catch(() => setDevMode(false));
  }, []);

  // ⌘K / Ctrl+K opens the palette; ⌘I / Ctrl+I opens the API inspector
  useEffect(() => {
    function onKey(e: KeyboardEvent): void {
      if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === "k") {
        e.preventDefault();
        setPaletteOpen((o) => !o);
      } else if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === "i") {
        e.preventDefault();
        setInspectorOpen((o) => !o);
      }
    }
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, []);

  const go = useCallback((v: ViewId) => {
    setView(v);
    setMenuOpen(false);
  }, []);

  const commands: Command[] = [
    ...NAV.map((n) => ({
      id: `view-${n.id}`,
      label: n.label,
      hint: n.hint,
      group: n.group,
      icon: n.icon,
      run: () => go(n.id),
    })),
    {
      id: "open-inspector",
      label: "Open API request inspector",
      hint: "live log",
      group: "System",
      icon: <Activity className="h-4 w-4" />,
      run: () => setInspectorOpen(true),
    },
  ];

  const groups = Array.from(new Set(NAV.map((n) => n.group)));
  const current = TITLES[view];

  return (
    <div className="flex min-h-screen flex-col bg-background text-foreground">
      <ApiProgressBar />
      <header className="sticky top-0 z-40 border-b bg-background/80 backdrop-blur supports-[backdrop-filter]:bg-background/60">
        <div className="mx-auto flex h-14 max-w-7xl items-center gap-3 px-4">
          <Button variant="ghost" size="icon" className="lg:hidden" onClick={() => setMenuOpen((o) => !o)} aria-label="toggle navigation">
            <Menu className="h-5 w-5" />
          </Button>
          <div className="flex items-center gap-2.5">
            <div className="flex h-8 w-8 items-center justify-center rounded-lg bg-gradient-to-br from-emerald-500 to-teal-600 text-white shadow-sm ring-1 ring-emerald-600/20">
              <ShieldCheck className="h-5 w-5" aria-hidden />
            </div>
            <div className="leading-tight">
              <p className="text-sm font-semibold tracking-tight">Yuri Licensing Platform</p>
              <p className="flex items-center gap-1.5 text-xs text-muted-foreground">
                <span className="pulse-dot relative inline-flex h-1.5 w-1.5 rounded-full bg-emerald-500 text-emerald-500" aria-hidden />
                admin dashboard
              </p>
            </div>
          </div>

          <div className="ml-auto flex items-center gap-1.5">
            <button
              type="button"
              onClick={() => setPaletteOpen(true)}
              className="hidden items-center gap-2 rounded-md border bg-muted/40 px-2.5 py-1.5 text-xs text-muted-foreground transition-colors hover:bg-muted hover:text-foreground md:flex"
              aria-label="open command palette"
            >
              <Search className="h-3.5 w-3.5" />
              <span>Search…</span>
              <span className="flex items-center gap-0.5">
                <Kbd className="border bg-background">⌘</Kbd>
                <Kbd className="border bg-background">K</Kbd>
              </span>
            </button>
            <Button variant="ghost" size="icon" className="h-8 w-8 md:hidden" onClick={() => setPaletteOpen(true)} aria-label="open command palette">
              <CommandIcon className="h-4 w-4" />
            </Button>
            {devMode === true && (
              <Badge variant="secondary" className="gap-1 border border-amber-500/30 bg-amber-500/10 text-amber-700 dark:text-amber-400">
                <span className="inline-block h-1.5 w-1.5 rounded-full bg-amber-500" aria-hidden /> dev
              </Badge>
            )}
            {devMode !== null && (
              <Tooltip>
                <TooltipTrigger asChild>
                  <Badge
                    variant={devMode ? "outline" : "default"}
                    className={
                      devMode
                        ? "gap-1"
                        : "gap-1 bg-emerald-600 hover:bg-emerald-600"
                    }
                  >
                    <Lock className="h-3 w-3" aria-hidden /> {devMode ? "token injected" : "login required"}
                  </Badge>
                </TooltipTrigger>
                <TooltipContent side="bottom" className="text-xs">
                  {devMode
                    ? "DASH_DEV_MODE=true — an admin token is injected server-side (demo only)"
                    : "DASH_DEV_MODE=false — token login + TOTP required"}
                </TooltipContent>
              </Tooltip>
            )}
            <ApiInspectorButton onClick={() => setInspectorOpen(true)} />
            <ThemeToggle />
          </div>
        </div>
      </header>

      <div className="mx-auto flex w-full max-w-7xl flex-1 gap-6 px-4 py-6">
        <nav
          aria-label="dashboard sections"
          className={`${menuOpen ? "block" : "hidden"} w-full shrink-0 lg:block lg:w-56`}
        >
          <div className="space-y-5 lg:sticky lg:top-20">
            {groups.map((g) => (
              <div key={g}>
                <p className="mb-1.5 flex items-center gap-2 px-2 text-[11px] font-semibold uppercase tracking-wider text-muted-foreground/80">
                  {g}
                  <span className="h-px flex-1 bg-border/70" aria-hidden />
                </p>
                <div className="space-y-0.5">
                  {NAV.filter((n) => n.group === g).map((n) => (
                    <button
                      key={n.id}
                      onClick={() => go(n.id)}
                      aria-current={view === n.id ? "page" : undefined}
                      className={`group relative flex w-full items-center gap-2.5 rounded-md px-2.5 py-2 text-sm transition-all ${
                        view === n.id
                          ? "bg-secondary font-medium text-secondary-foreground shadow-sm"
                          : "text-muted-foreground hover:bg-secondary/60 hover:text-foreground"
                      }`}
                    >
                      {view === n.id && (
                        <span
                          className="absolute inset-y-1.5 left-0 w-[3px] rounded-full bg-gradient-to-b from-emerald-500 to-teal-600"
                          aria-hidden
                        />
                      )}
                      <span
                        className={`transition-colors ${
                          view === n.id
                            ? "text-emerald-600 dark:text-emerald-400"
                            : "text-muted-foreground/70 group-hover:text-foreground"
                        }`}
                      >
                        {n.icon}
                      </span>
                      {n.label}
                      {view === n.id && <span className="ml-auto h-1 w-1 rounded-full bg-emerald-500" aria-hidden />}
                    </button>
                  ))}
                </div>
                {g !== groups[groups.length - 1] && <Separator className="mt-4 lg:hidden" />}
              </div>
            ))}

            <div className="hidden rounded-lg border border-dashed p-3 lg:block">
              <p className="text-[11px] leading-relaxed text-muted-foreground">
                <Kbd className="border bg-background px-1 font-mono">⌘K</Kbd> palette · <Kbd className="border bg-background px-1 font-mono">⌘I</Kbd> API inspector
              </p>
            </div>
          </div>
        </nav>

        <main className="min-w-0 flex-1">
          <div className="mb-5">
            <h1 className="text-2xl font-semibold tracking-tight">{current.title}</h1>
            <p className="text-sm text-muted-foreground">{current.sub}</p>
          </div>
          <div key={view} className="view-enter">
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
          </div>
        </main>
      </div>

      <footer className="mt-auto border-t bg-muted/30">
        <div className="mx-auto flex max-w-7xl flex-wrap items-center justify-between gap-3 px-4 py-4 text-xs text-muted-foreground">
          <div className="flex flex-wrap items-center gap-2">
            <p>
              Self-hosted Lua script licensing &amp; protection platform — dashboard (M11) driving the real API core (M1), free-key
              flow (M9) and payments (M10) in-process.
            </p>
          </div>
          <div className="flex items-center gap-2">
            <Badge variant="outline" className="gap-1 text-[10px]">
              <span className="pulse-dot relative inline-flex h-1.5 w-1.5 rounded-full bg-emerald-500 text-emerald-500" aria-hidden />
              live router
            </Badge>
            <Badge variant="outline" className="text-[10px] font-mono">v1 · x-sig</Badge>
            <span className="hidden font-mono sm:inline">audit-logged mutations</span>
          </div>
        </div>
      </footer>

      <CommandPalette open={paletteOpen} onOpenChange={setPaletteOpen} commands={commands} />
      <ApiInspectorPanel open={inspectorOpen} onClose={() => setInspectorOpen(false)} />
    </div>
  );
}
