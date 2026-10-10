"use client";

// Shared badge atoms (M11 s4) — used by Keys, Users detail, and future views.

import { Badge } from "@/components/ui/badge";

const TIER_STYLES: Record<string, string> = {
  paid: "border-emerald-600/30 bg-emerald-600/10 text-emerald-700 dark:text-emerald-400",
  lifetime: "border-teal-600/30 bg-teal-600/10 text-teal-700 dark:text-teal-400",
  free: "border-amber-600/30 bg-amber-600/10 text-amber-700 dark:text-amber-400",
  reseller: "border-rose-600/30 bg-rose-600/10 text-rose-700 dark:text-rose-400",
};

export function TierBadge({ tier }: { tier: string }): React.JSX.Element {
  return (
    <Badge variant="outline" className={`gap-1 ${TIER_STYLES[tier] ?? ""}`}>
      <span className="inline-block h-1.5 w-1.5 rounded-full bg-current opacity-70" aria-hidden />
      {tier}
    </Badge>
  );
}

export function StatusBadge({ status }: { status: string }): React.JSX.Element {
  if (status === "active")
    return (
      <Badge className="gap-1 bg-emerald-600 hover:bg-emerald-600">
        <span className="pulse-dot relative inline-flex h-1.5 w-1.5 rounded-full bg-white" aria-hidden />
        {status}
      </Badge>
    );
  if (status === "revoked") return <Badge variant="destructive">{status}</Badge>;
  return <Badge variant="secondary">{status}</Badge>;
}
