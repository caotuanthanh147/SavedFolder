"use client";

// Live API request log (M11 s4): every gw() call through the dashboard's
// gateway to the REAL api/ router is recorded here — method, path, status,
// latency. A tiny external store read via useSyncExternalStore (pure during
// render; updates only from fetch callbacks). Ring buffer, cap 80.

export interface ApiLogEntry {
  id: number;
  method: string;
  path: string;
  status: number | null; // null = in flight
  ms: number | null;
  at: number; // epoch ms
}

const CAP = 80;

let nextId = 1;
let entries: ApiLogEntry[] = [];
let inFlight = 0;
const listeners = new Set<() => void>();

function emit(): void {
  for (const l of listeners) l();
}

function subscribe(listener: () => void): () => void {
  listeners.add(listener);
  return () => listeners.delete(listener);
}

function snapshot(): ApiLogEntry[] {
  return entries;
}

function inflightSnapshot(): number {
  return inFlight;
}

export function subscribeApiLog(listener: () => void): () => void {
  return subscribe(listener);
}

export function getApiLogSnapshot(): ApiLogEntry[] {
  return snapshot();
}

export function getInflightSnapshot(): number {
  return inflightSnapshot();
}

export function beginApiRequest(method: string, path: string): number {
  const id = nextId++;
  const entry: ApiLogEntry = { id, method, path, status: null, ms: null, at: Date.now() };
  entries = [entry, ...entries].slice(0, CAP);
  inFlight += 1;
  emit();
  return id;
}

export function endApiRequest(id: number, status: number, ms: number): void {
  entries = entries.map((e) => (e.id === id ? { ...e, status, ms } : e));
  inFlight = Math.max(0, inFlight - 1);
  emit();
}

export function failApiRequest(id: number, ms: number): void {
  entries = entries.map((e) => (e.id === id ? { ...e, status: 0, ms } : e));
  inFlight = Math.max(0, inFlight - 1);
  emit();
}

export function clearApiLog(): void {
  entries = [];
  emit();
}

/** Instrument a fetch round trip through the log. */
export async function loggedFetch(input: string, init?: RequestInit): Promise<Response> {
  const url = new URL(input, "http://localhost");
  const path = url.pathname + (url.search || "");
  const id = beginApiRequest(init?.method ?? "GET", path);
  const t0 = Date.now();
  try {
    const res = await fetch(input, init);
    endApiRequest(id, res.status, Date.now() - t0);
    return res;
  } catch (e) {
    failApiRequest(id, Date.now() - t0);
    throw e;
  }
}
