"use client";

// Typed client for the dashboard's gateway to the REAL admin API
// (modules M1 + M9). All calls are relative (sandbox rule) and hit the
// in-process router via /api/gw/*.

export interface Envelope {
  code: string;
  message: string;
  data: Record<string, unknown> | null;
}

export async function gw<T>(method: string, path: string, body?: unknown): Promise<T> {
  const res = await fetch(`/api/gw${path}`, {
    method,
    headers: body !== undefined ? { "content-type": "application/json" } : undefined,
    body: body !== undefined ? JSON.stringify(body) : undefined,
    cache: "no-store",
  });
  const text = await res.text();
  let parsed: unknown;
  try {
    parsed = JSON.parse(text);
  } catch {
    throw new Error(`gateway error ${res.status}`);
  }
  if (!res.ok) {
    const err = parsed as { error?: string; field?: string };
    throw new Error(err.error ?? `error_${res.status}`);
  }
  return parsed as T;
}

export async function envelopeCall(method: string, path: string, body?: unknown): Promise<Envelope> {
  return gw<Envelope>(method, path, body);
}

export interface KeyRow {
  id: string;
  project_id: string;
  tier: string;
  status: string;
  hwid_bound: boolean;
  hwid_resets: number;
  discord_id: string | null;
  roblox_user_id: number | null;
  note: string | null;
  total_executions: number;
  created_by: string;
  created_at: number;
  expires_at: number | null;
  first_used_at: number | null;
  last_used_at: number | null;
}

export interface ScriptRow {
  id: string;
  project_id: string;
  name: string;
  keyless: boolean;
  active_version: number;
  created_at: number;
  versions: { script_id: string; version: number; build_hash: string; init_build: string; notes: string | null; created_at: number; blob_ref: string }[];
  game_ids: number[];
}

export interface SessionRow {
  id: string;
  key_id: string | null;
  script_id: string;
  version: number;
  hwid_hash: string;
  ip_hash: string;
  roblox_user_id: number | null;
  place_id: number | null;
  watermark_id: string;
  created_at: number;
  expires_at: number;
}

export interface AuditEntry {
  id: string;
  actor_id: string;
  action: string;
  target: string | null;
  detail: string | null;
  created_at: number;
}

export interface NodeRow {
  id: string;
  hostname: string;
  region: string | null;
  active: boolean;
}

export interface ProtocolVersionRow {
  version: string;
  handler: string;
  min_loader: string | null;
  active: boolean;
}

export interface BlacklistRow {
  id: string;
  kind: string;
  value_hash: string;
  reason: string | null;
  created_by: string;
  created_at: number;
}

export interface AnalyticsOverview {
  window: string;
  keys_active: number;
  keys_revoked: number;
  sessions_24h: number;
  sessions_live: number;
  validate_ok_24h: number;
  validate_fail_24h: number;
  tamper_24h: number;
}

export interface SyncData {
  st: number;
  nodes: string[];
  colo: string;
}

export function formatTime(unix: number | null | undefined): string {
  if (unix === null || unix === undefined) return "—";
  return new Date(unix * 1000).toLocaleString();
}

export function shortHash(hash: string | null | undefined, n = 10): string {
  if (!hash) return "—";
  return hash.slice(0, n) + "…";
}
