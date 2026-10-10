"use client";

import { useTheme } from "next-themes";
import { Button } from "@/components/ui/button";
import { Moon, Sun } from "lucide-react";

export function ThemeToggle(): React.JSX.Element {
  const { resolvedTheme, setTheme } = useTheme();

  return (
    <Button
      variant="ghost"
      size="icon"
      aria-label="toggle color theme"
      title="Toggle light/dark theme"
      onClick={() => setTheme(resolvedTheme === "dark" ? "light" : "dark")}
      className="h-8 w-8"
    >
      <Sun className="hidden h-4 w-4 dark:block" aria-hidden />
      <Moon className="block h-4 w-4 dark:hidden" aria-hidden />
    </Button>
  );
}
