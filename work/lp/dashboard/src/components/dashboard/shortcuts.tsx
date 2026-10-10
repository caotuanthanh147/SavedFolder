"use client";

// ShortcutsDialog — "?" overlay listing every keyboard affordance + the
// copy/CSV/print interactions. Press ? (shift+/) anywhere no field is
// focused; Esc closes (Radix). Opened from page.tsx state.

import { Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { Kbd } from "@/components/ui/kbd";
import { Bell, CornerDownLeft, Keyboard, MousePointerClick, Printer, Search } from "lucide-react";

interface Row {
  keys: React.ReactNode;
  label: string;
  icon: React.ReactNode;
}

const NAV_ROWS: Row[] = [
  { keys: <><Kbd className="border bg-background">⌘</Kbd><Kbd className="border bg-background">K</Kbd></>, label: "Command palette — jump to any view or run actions", icon: <Search className="h-4 w-4" aria-hidden /> },
  { keys: <><Kbd className="border bg-background">⌘</Kbd><Kbd className="border bg-background">I</Kbd></>, label: "API request inspector — live traffic log with error badge", icon: <Keyboard className="h-4 w-4" aria-hidden /> },
  { keys: <Kbd className="border bg-background">?</Kbd>, label: "This shortcuts overlay", icon: <Keyboard className="h-4 w-4" aria-hidden /> },
  { keys: <><Kbd className="border bg-background">↑</Kbd><Kbd className="border bg-background">↓</Kbd></>, label: "Move the palette selection", icon: <CornerDownLeft className="h-4 w-4" aria-hidden /> },
  { keys: <Kbd className="border bg-background">↵</Kbd>, label: "Run the selected palette command", icon: <CornerDownLeft className="h-4 w-4" aria-hidden /> },
  { keys: <Kbd className="border bg-background">Esc</Kbd>, label: "Close dialogs, palette, inspector", icon: <CornerDownLeft className="h-4 w-4" aria-hidden /> },
];

const INTERACTION_ROWS: Row[] = [
  { keys: <Kbd className="border bg-background">click</Kbd>, label: "Overview stat cards drill down (keys / sessions / tamper)", icon: <MousePointerClick className="h-4 w-4" aria-hidden /> },
  { keys: <Kbd className="border bg-background">click</Kbd>, label: "Hashes and ids copy to clipboard (toast confirms)", icon: <MousePointerClick className="h-4 w-4" aria-hidden /> },
  { keys: <Kbd className="border bg-background">click</Kbd>, label: "Freshness pill refreshes the view's data now", icon: <MousePointerClick className="h-4 w-4" aria-hidden /> },
  { keys: <Kbd className="border bg-background">bell</Kbd>, label: "Header bell rings on tamper/leak/blacklist events — palette toggles mute", icon: <Bell className="h-4 w-4" aria-hidden /> },
  { keys: <Kbd className="border bg-background">print</Kbd>, label: "Palette → “Print / save as PDF” renders a clean report (chrome hidden, tables expanded)", icon: <Printer className="h-4 w-4" aria-hidden /> },
];

export function ShortcutsDialog({ open, onOpenChange }: { open: boolean; onOpenChange: (o: boolean) => void }): React.JSX.Element {
  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="sm:max-w-lg">
        <DialogHeader>
          <DialogTitle className="flex items-center gap-2">
            <Keyboard className="h-4 w-4 text-emerald-600 dark:text-emerald-400" />
            Keyboard shortcuts
          </DialogTitle>
          <DialogDescription>The dashboard is fully operable without a mouse.</DialogDescription>
        </DialogHeader>
        <div className="space-y-4">
          <section aria-label="navigation shortcuts">
            <p className="mb-1.5 text-[10px] font-medium uppercase tracking-wider text-muted-foreground">Navigation</p>
            <ul className="space-y-1.5">
              {NAV_ROWS.map((r) => (
                <li key={r.label} className="flex items-center gap-3 rounded-md px-2 py-1.5 text-sm transition-colors hover:bg-muted/50">
                  <span className="flex w-24 shrink-0 items-center justify-start gap-1 text-muted-foreground">{r.keys}</span>
                  <span className="flex-1">{r.label}</span>
                  <span className="text-muted-foreground/60">{r.icon}</span>
                </li>
              ))}
            </ul>
          </section>
          <section aria-label="interaction shortcuts">
            <p className="mb-1.5 text-[10px] font-medium uppercase tracking-wider text-muted-foreground">Interactions</p>
            <ul className="space-y-1.5">
              {INTERACTION_ROWS.map((r) => (
                <li key={r.label} className="flex items-center gap-3 rounded-md px-2 py-1.5 text-sm transition-colors hover:bg-muted/50">
                  <span className="flex w-24 shrink-0 items-center justify-start gap-1 text-muted-foreground">{r.keys}</span>
                  <span className="flex-1">{r.label}</span>
                  <span className="text-muted-foreground/60">{r.icon}</span>
                </li>
              ))}
            </ul>
          </section>
        </div>
      </DialogContent>
    </Dialog>
  );
}
