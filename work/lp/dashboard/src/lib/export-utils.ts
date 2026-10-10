"use client";

import { toast } from "sonner";
export { csvEscape, csvTimestamp, exportCsv } from "@/lib/csv";

/** Clipboard copy with toast feedback (sonner). */
export function copyText(text: string, message = "Copied to clipboard"): void {
  void navigator.clipboard
    .writeText(text)
    .then(() => toast.success(message))
    .catch(() => toast.error("Clipboard unavailable"));
}
