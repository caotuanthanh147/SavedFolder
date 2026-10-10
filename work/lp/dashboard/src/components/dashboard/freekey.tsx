"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import { Alert, AlertDescription, AlertTitle } from "@/components/ui/alert";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Progress } from "@/components/ui/progress";
import { envelopeCall } from "@/lib/api";
import { BadgeCheck, Clock, ExternalLink, Gift, Loader2, Lock, ShieldAlert, Timer } from "lucide-react";

interface FreeState {
  token: string;
  step: number;
  total_steps: number;
  url: string;
  min_seconds: number;
  done?: boolean;
  claim_window_sec?: number;
}

function secretOf(url: string): string {
  const m = /[?&]s=([^&]+)/.exec(url);
  return m ? m[1] : "";
}

export function FreeKeyView(): React.JSX.Element {
  const [slug, setSlug] = useState("yuri");
  const [state, setState] = useState<FreeState | null>(null);
  const [phase, setPhase] = useState<"idle" | "running" | "claimed">("idle");
  const [claimedKey, setClaimedKey] = useState<{ key: string; expires_at: number } | null>(null);
  const [message, setMessage] = useState<{ kind: "info" | "error"; text: string } | null>(null);
  const [busy, setBusy] = useState(false);
  const [countdown, setCountdown] = useState(0);
  const [clock, setClock] = useState(0);
  const logRef = useRef<HTMLDivElement>(null);
  const [log, setLog] = useState<string[]>([]);

  const appendLog = useCallback((line: string) => {
    setLog((prev) => [...prev, `${new Date().toLocaleTimeString()}  ${line}`]);
    requestAnimationFrame(() => {
      if (logRef.current) logRef.current.scrollTop = logRef.current.scrollHeight;
    });
  }, []);

  useEffect(() => {
    if (countdown <= 0) return;
    const timer = setInterval(() => setCountdown((c) => Math.max(0, c - 1)), 1000);
    return () => clearInterval(timer);
  }, [countdown]);

  useEffect(() => {
    const timer = setInterval(() => setClock((c) => c + 1), 1000);
    return () => clearInterval(timer);
  }, []);
  void clock;

  async function start(): Promise<void> {
    setBusy(true);
    setMessage(null);
    setClaimedKey(null);
    try {
      const env = await envelopeCall("POST", "/free/start", { slug: slug.trim() });
      if (env.code === "KEY_VALID" && env.data) {
        const st = env.data as unknown as FreeState;
        setState(st);
        setPhase("running");
        setCountdown(st.min_seconds);
        appendLog(`attempt started — step ${st.step}/${st.total_steps}, server min time ${st.min_seconds}s (§14.3)`);
        appendLog(`checkpoint url: ${st.url}`);
      } else {
        setMessage({ kind: "error", text: `${env.code}: ${env.message}${env.code === "RATE_LIMITED" ? " — cooldown or per-IP start limit (anti-farm, §14.3/§14.5). Try again later." : ""}` });
        appendLog(`start rejected: ${env.code}`);
      }
    } catch (e) {
      setMessage({ kind: "error", text: e instanceof Error ? e.message : "request failed" });
    } finally {
      setBusy(false);
    }
  }

  async function completeStep(): Promise<void> {
    if (!state) return;
    setBusy(true);
    try {
      const secret = secretOf(state.url);
      const env = await envelopeCall("POST", "/free/step", { token: state.token, completion_token: secret });
      if (env.code === "KEY_VALID" && env.data) {
        const st = env.data as unknown as FreeState;
        setState(st);
        if (st.done) {
          appendLog(`all ${st.total_steps} checkpoints complete — claim window ${st.claim_window_sec}s (§14.5 short-lived)`);
        } else {
          setCountdown(st.min_seconds);
          appendLog(`step advanced to ${st.step}/${st.total_steps}; token rotated (single-use, §14.5); next checkpoint: ${st.url}`);
        }
      } else {
        setMessage({ kind: "error", text: `${env.code}: ${env.message}${env.code === "BAD_REQUEST" ? " — the server rejected the completion evidence (too fast / wrong token / wrong secret). Every rejection is logged as a free_bypass event." : ""}` });
        appendLog(`step rejected: ${env.code} — anti-bypass event recorded`);
      }
    } finally {
      setBusy(false);
    }
  }

  async function claim(): Promise<void> {
    if (!state) return;
    setBusy(true);
    try {
      const env = await envelopeCall("POST", "/free/claim", { token: state.token });
      if (env.code === "KEY_VALID" && env.data) {
        const d = env.data as unknown as { key: string; expires_at: number; tier: string };
        setClaimedKey({ key: d.key, expires_at: d.expires_at });
        setPhase("claimed");
        appendLog(`claimed tier-${d.tier} key (audited, expires ${new Date(d.expires_at * 1000).toLocaleString()})`);
      } else {
        setMessage({ kind: "error", text: `${env.code}: ${env.message}` });
        appendLog(`claim rejected: ${env.code}`);
      }
    } finally {
      setBusy(false);
    }
  }


  return (
    <div className="space-y-4">
      <Card>
        <CardHeader>
          <CardTitle className="flex items-center gap-2">
            <Gift className="h-5 w-5" /> Free-key flow
            <Badge variant="secondary" className="ml-1">module M9</Badge>
          </CardTitle>
          <CardDescription>
            The public page per project slug (doc §14): server-verified checkpoints, rotating single-use tokens, per-fingerprint cooldowns, minimum time per step, and bypass monitoring. This demo drives the REAL <code>/free/start → /free/step → /free/claim</code> endpoints.
          </CardDescription>
        </CardHeader>
        <CardContent className="space-y-4">
          {phase === "idle" && (
            <div className="flex flex-wrap items-end gap-3">
              <div className="space-y-1">
                <Label htmlFor="slug">Project slug</Label>
                <Input id="slug" value={slug} onChange={(e) => setSlug(e.target.value)} className="w-44 font-mono" />
              </div>
              <Button onClick={() => void start()} disabled={busy || slug.trim().length === 0}>
                {busy ? <Loader2 className="mr-1 h-4 w-4 animate-spin" /> : <Gift className="mr-1 h-4 w-4" />}
                Start free attempt
              </Button>
            </div>
          )}

          {phase === "running" && state && (
            <div className="space-y-4">
              <div className="flex flex-wrap gap-2">
                {Array.from({ length: state.total_steps }).map((_, i) => (
                  <Badge key={i} variant={i + 1 < state.step ? "default" : i + 1 === state.step ? "secondary" : "outline"} className={i + 1 < state.step ? "bg-emerald-600 hover:bg-emerald-600" : ""}>
                    {i + 1 < state.step ? "✓" : i + 1 === state.step ? <Timer className="mr-1 h-3 w-3" /> : <Lock className="mr-1 h-3 w-3" />}
                    checkpoint {i + 1}
                  </Badge>
                ))}
                {state.done && <Badge className="bg-emerald-600 hover:bg-emerald-600">claim window open</Badge>}
              </div>

              {!state.done && (
                <div className="rounded-lg border p-4">
                  <p className="text-sm font-medium">Checkpoint {state.step} — custom provider (demo)</p>
                  <p className="mt-1 break-all font-mono text-xs text-muted-foreground">{state.url}</p>
                  <p className="mt-2 text-xs text-muted-foreground">
                    A real provider (Linkvertise/Lootlabs) sends the user through its ad chain and redirects back with the completion token embedded in this URL. Resolver-bypass tools can leak the destination — so the server independently enforces the minimum time and monitors speed (§14.5).
                  </p>
                  <div className="mt-3 flex items-center gap-3">
                    <Progress value={state.min_seconds > 0 ? ((state.min_seconds - countdown) / state.min_seconds) * 100 : 100} className="flex-1" />
                    <span className="flex items-center gap-1 text-sm tabular-nums text-muted-foreground">
                      <Clock className="h-4 w-4" />
                      {countdown}s
                    </span>
                  </div>
                  <div className="mt-3 flex flex-wrap gap-2">
                    <Button variant="outline" size="sm" onClick={() => window.open(state.url, "_blank", "noopener")}>
                      <ExternalLink className="mr-1 h-4 w-4" /> Open checkpoint
                    </Button>
                    <Button size="sm" onClick={() => void completeStep()} disabled={busy}>
                      {busy ? <Loader2 className="mr-1 h-4 w-4 animate-spin" /> : <BadgeCheck className="mr-1 h-4 w-4" />}
                      Complete checkpoint (returns with token)
                    </Button>
                  </div>
                  <p className="mt-2 text-xs text-muted-foreground">
                    Clicking before the server&apos;s minimum time is a live bypass attempt — it will be rejected and logged.
                  </p>
                </div>
              )}

              {state.done && (
                <div className="flex flex-wrap items-center gap-3">
                  <Button onClick={() => void claim()} disabled={busy}>
                    {busy ? <Loader2 className="mr-1 h-4 w-4 animate-spin" /> : <Gift className="mr-1 h-4 w-4" />}
                    Claim free key
                  </Button>
                  <span className="text-xs text-muted-foreground">tier: free · 3-day expiry · all project scripts entitled</span>
                </div>
              )}
            </div>
          )}

          {phase === "claimed" && claimedKey && (
            <div className="space-y-3">
              <div className="flex items-center justify-between gap-2 rounded-lg border border-emerald-600/40 bg-emerald-600/5 p-4">
                <div>
                  <p className="text-xs uppercase tracking-wide text-muted-foreground">your free key</p>
                  <code className="text-lg font-semibold">{claimedKey.key}</code>
                  <p className="text-xs text-muted-foreground">expires {new Date(claimedKey.expires_at * 1000).toLocaleString()} · validate it in the Keys view</p>
                </div>
                <Button variant="outline" onClick={() => void navigator.clipboard.writeText(claimedKey.key)}>
                  copy
                </Button>
              </div>
              <Button variant="outline" onClick={() => { setPhase("idle"); setState(null); setLog([]); }}>
                Start another attempt
              </Button>
              <p className="text-xs text-muted-foreground">
                The same fingerprint is now inside the 90-second cooldown — a second immediate start returns RATE_LIMITED (demo value; production default 6h per §14.3).
              </p>
            </div>
          )}

          {message && (
            <Alert variant={message.kind === "error" ? "destructive" : "default"}>
              <ShieldAlert className="h-4 w-4" />
              <AlertTitle>{message.kind === "error" ? "Flow rejected" : "Info"}</AlertTitle>
              <AlertDescription>{message.text}</AlertDescription>
            </Alert>
          )}
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle className="text-sm">Flow log (server-side events mirror in the events table)</CardTitle>
        </CardHeader>
        <CardContent>
          <div ref={logRef} className="max-h-64 overflow-y-auto rounded-md bg-muted p-3 font-mono text-xs leading-relaxed">
            {log.length === 0 ? (
              <p className="text-muted-foreground">waiting for the first attempt…</p>
            ) : (
              log.map((l, i) => (
                <p key={i}>{l}</p>
              ))
            )}
          </div>
        </CardContent>
      </Card>
    </div>
  );
}
