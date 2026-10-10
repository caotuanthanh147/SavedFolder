"use client";

import { useMemo, useRef, useState } from "react";
import { useTheme } from "next-themes";
import { Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { Badge } from "@/components/ui/badge";
import { ArrowRight, CornerDownLeft, Moon, Search, Sun } from "lucide-react";

export interface Command {
  id: string;
  label: string;
  hint?: string;
  group: string;
  icon: React.ReactNode;
  run: () => void;
}

function matches(query: string, cmd: Command): boolean {
  if (query.length === 0) return true;
  const q = query.toLowerCase();
  return (
    cmd.label.toLowerCase().includes(q) ||
    cmd.group.toLowerCase().includes(q) ||
    (cmd.hint?.toLowerCase().includes(q) ?? false)
  );
}

export function CommandPalette({
  open,
  onOpenChange,
  commands,
}: {
  open: boolean;
  onOpenChange: (o: boolean) => void;
  commands: Command[];
}): React.JSX.Element {
  const [query, setQuery] = useState("");
  const [active, setActive] = useState(0);
  const inputRef = useRef<HTMLInputElement>(null);
  const listRef = useRef<HTMLDivElement>(null);
  const { resolvedTheme, setTheme } = useTheme();

  const themeCommand: Command = useMemo(
    () => ({
      id: "theme-toggle",
      label: resolvedTheme === "dark" ? "Switch to light theme" : "Switch to dark theme",
      hint: "appearance",
      group: "Settings",
      icon: resolvedTheme === "dark" ? <Sun className="h-4 w-4" /> : <Moon className="h-4 w-4" />,
      run: () => setTheme(resolvedTheme === "dark" ? "light" : "dark"),
    }),
    [resolvedTheme, setTheme],
  );

  const filtered = useMemo(() => commands.filter((c) => matches(query, c)), [commands, query]);
  const all = useMemo(
    () => (matches(query, themeCommand) ? [...filtered, themeCommand] : filtered),
    [filtered, themeCommand, query],
  );

  // Open/close transitions happen in the dialog's own onOpenChange wrapper so
  // no state is set from an effect body.
  function handleOpenChange(o: boolean): void {
    if (o) {
      setQuery("");
      setActive(0);
    }
    onOpenChange(o);
  }

  function execute(cmd: Command): void {
    handleOpenChange(false);
    cmd.run();
  }

  function onKeyDown(e: React.KeyboardEvent): void {
    if (e.key === "ArrowDown") {
      e.preventDefault();
      setActive((a) => (a + 1) % Math.max(1, all.length));
    } else if (e.key === "ArrowUp") {
      e.preventDefault();
      setActive((a) => (a - 1 + all.length) % Math.max(1, all.length));
    } else if (e.key === "Enter" && all[active]) {
      e.preventDefault();
      execute(all[active]);
    }
  }

  return (
    <Dialog open={open} onOpenChange={handleOpenChange}>
      <DialogContent className="top-[18%] translate-y-0 gap-0 overflow-hidden p-0 sm:max-w-lg">
        <DialogHeader className="border-b px-4 py-3 text-left">
          <DialogTitle className="flex items-center gap-2 text-sm font-medium">
            <Search className="h-4 w-4 text-muted-foreground" /> Command palette
          </DialogTitle>
          <DialogDescription className="sr-only">Search views and actions — arrow keys to navigate, Enter to run</DialogDescription>
        </DialogHeader>
        <div className="px-4 pt-3">
          <input
            ref={inputRef}
            autoFocus
            value={query}
            onChange={(e) => {
              setQuery(e.target.value);
              setActive(0);
            }}
            onKeyDown={onKeyDown}
            placeholder="Jump to a view or run an action…"
            aria-label="search commands"
            className="w-full rounded-md border bg-transparent px-3 py-2 text-sm outline-none placeholder:text-muted-foreground focus-visible:ring-2 focus-visible:ring-ring/50"
          />
        </div>
        <div ref={listRef} className="max-h-72 overflow-y-auto p-2">
          {all.length === 0 ? (
            <p className="px-3 py-8 text-center text-sm text-muted-foreground">No matches for “{query}”.</p>
          ) : (
            all.map((cmd, i) => (
              <button
                key={cmd.id}
                data-idx={i}
                type="button"
                onClick={() => execute(cmd)}
                onMouseEnter={() => setActive(i)}
                className={`flex w-full items-center gap-3 rounded-md px-3 py-2 text-left text-sm transition-colors ${
                  i === active ? "bg-secondary" : "hover:bg-secondary/60"
                }`}
              >
                <span className="text-muted-foreground">{cmd.icon}</span>
                <span className="flex-1 truncate">{cmd.label}</span>
                {cmd.hint && <Badge variant="outline" className="hidden text-[10px] sm:inline-flex">{cmd.hint}</Badge>}
                <span className="flex items-center gap-1 text-[10px] uppercase tracking-wide text-muted-foreground/70">{cmd.group}</span>
                {i === active && <CornerDownLeft className="h-3.5 w-3.5 text-muted-foreground" />}
              </button>
            ))
          )}
        </div>
        <div className="flex items-center justify-between border-t bg-muted/40 px-4 py-2 text-[11px] text-muted-foreground">
          <span className="flex items-center gap-1">
            <kbd className="rounded border bg-background px-1.5 font-mono">↑↓</kbd> navigate
            <kbd className="ml-1 rounded border bg-background px-1.5 font-mono">↵</kbd> run
          </span>
          <span className="flex items-center gap-1">
            <ArrowRight className="h-3 w-3" /> {all.length} command{all.length === 1 ? "" : "s"}
          </span>
        </div>
      </DialogContent>
    </Dialog>
  );
}
