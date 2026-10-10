"use client";

import { useState } from "react";
import { Alert, AlertDescription, AlertTitle } from "@/components/ui/alert";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Separator } from "@/components/ui/separator";
import { loggedFetch } from "@/lib/api-log";
import { KeyRound, ShieldCheck, Copy } from "lucide-react";
import { useApiData } from "@/lib/use-api-data";

interface DashInfo {
  dev_mode: boolean;
  dev_admin_token: string | null;
  discord_oauth: boolean;
  project: { name: string; slug: string; script: string };
  free: { keyDays: number; attemptTtlSec: number; claimWindowSec: number; startsPerIpPerMin: number; requestsPerIpPerMin: number; attemptsPerIpPerHour: number; cooldown_seconds: number };
}

interface TotpState {
  enrolled: boolean;
  enabled: boolean;
  created_at: number | null;
}

export function SettingsView(): React.JSX.Element {
  const { data: fetched, error, refresh } = useApiData(async () => {
    const [i, t] = await Promise.all([
      loggedFetch("/api/dash/info", { cache: "no-store" }).then((r) => r.json() as Promise<DashInfo>),
      loggedFetch("/api/dash/totp", { cache: "no-store" }).then((r) => r.json() as Promise<TotpState>),
    ]);
    return { info: i, totp: t };
  }, []);
  const info = fetched?.info ?? null;
  const totp = fetched?.totp ?? null;
  const [secret, setSecret] = useState<string | null>(null);
  const [otpauth, setOtpauth] = useState<string | null>(null);
  const [code, setCode] = useState("");
  const [notice, setNotice] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [copied, setCopied] = useState<string | null>(null);



  async function totpAction(action: "enroll" | "verify" | "disable"): Promise<void> {
    setBusy(true);
    try {
      const res = await loggedFetch("/api/dash/totp", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ action, code }),
      });
      const json = (await res.json()) as { secret?: string; otpauth_uri?: string; enabled?: boolean; error?: string };
      if (!res.ok) {
        setNotice(json.error ?? "totp action failed");
        return;
      }
      setError(null);
      if (action === "enroll") {
        setSecret(json.secret ?? null);
        setOtpauth(json.otpauth_uri ?? null);
        setNotice("Enrollment started — verify a code from your authenticator app to enable.");
      } else {
        setNotice(json.enabled ? "TOTP enabled — logins now require the second factor." : "TOTP disabled.");
        setSecret(null);
        setCode("");
      }
      refresh();
    } finally {
      setBusy(false);
    }
  }

  function copy(text: string, what: string): void {
    void navigator.clipboard.writeText(text).then(() => {
      setCopied(what);
      setTimeout(() => setCopied(null), 1500);
    });
  }

  return (
    <div className="space-y-4">
      {notice && (
        <Alert>
          <ShieldCheck className="h-4 w-4" />
          <AlertDescription>{notice}</AlertDescription>
        </Alert>
      )}
      {error && (
        <Alert variant="destructive">
          <AlertTitle>Error</AlertTitle>
          <AlertDescription>{error}</AlertDescription>
        </Alert>
      )}

      {info && (
        <Card>
          <CardHeader>
            <CardTitle className="flex items-center gap-2 text-base">
              <KeyRound className="h-4 w-4" /> Runtime
            </CardTitle>
            <CardDescription>project {info.project.name} · slug <code>{info.project.slug}</code> · script {info.project.script}</CardDescription>
          </CardHeader>
          <CardContent className="space-y-2 text-sm">
            <div className="flex flex-wrap items-center gap-2">
              <Badge variant={info.dev_mode ? "secondary" : "outline"}>{info.dev_mode ? "dev mode ON (DASH_DEV_MODE)" : "production mode"}</Badge>
              <Badge variant={info.discord_oauth ? "default" : "outline"} className={info.discord_oauth ? "bg-emerald-600 hover:bg-emerald-600" : ""}>
                Discord OAuth {info.discord_oauth ? "configured" : "not configured"}
              </Badge>
            </div>
            <Separator />
            {info.dev_mode && info.dev_admin_token && (
              <div className="rounded-md border border-amber-500/40 bg-amber-500/5 p-3">
                <p className="text-xs font-medium text-amber-600 dark:text-amber-400">Dev admin token (injected by the gateway in dev mode only)</p>
                <div className="mt-1 flex items-center gap-2">
                  <code className="break-all text-xs">{info.dev_admin_token}</code>
                  <Button variant="ghost" size="sm" onClick={() => copy(info.dev_admin_token!, "token")}>
                    <Copy className="mr-1 h-3 w-3" /> {copied === "token" ? "copied" : "copy"}
                  </Button>
                </div>
                <p className="mt-1 text-xs text-muted-foreground">Production sets DASH_DEV_MODE=false — logins then use this token manually, Discord OAuth, and TOTP.</p>
              </div>
            )}
            <div className="grid gap-2 sm:grid-cols-2">
              <div className="rounded-md border p-2">
                <p className="text-xs text-muted-foreground">Free key lifetime</p>
                <p className="font-medium">{info.free.keyDays} days</p>
              </div>
              <div className="rounded-md border p-2">
                <p className="text-xs text-muted-foreground">Attempt TTL / claim window</p>
                <p className="font-medium">{Math.floor(info.free.attemptTtlSec / 60)} min / {Math.floor(info.free.claimWindowSec / 60)} min</p>
              </div>
              <div className="rounded-md border p-2">
                <p className="text-xs text-muted-foreground">Starts per IP</p>
                <p className="font-medium">{info.free.startsPerIpPerMin}/min · {info.free.attemptsPerIpPerHour}/hour (burst watch)</p>
              </div>
              <div className="rounded-md border p-2">
                <p className="text-xs text-muted-foreground">Fingerprint cooldown (demo)</p>
                <p className="font-medium">{Math.floor(info.free.cooldown_seconds / 60)} min (prod default 6 h)</p>
              </div>
            </div>
          </CardContent>
        </Card>
      )}

      <Card>
        <CardHeader>
          <CardTitle className="text-base">TOTP second factor (RFC 6238)</CardTitle>
          <CardDescription>
            Optional per doc §16. Enrolled secrets live in the dashboard&apos;s own store (CCP-3 proposes admins.totp_secret). Zero-dependency implementation, tested against RFC 6238 Appendix B vectors.
          </CardDescription>
        </CardHeader>
        <CardContent className="space-y-3">
          {totp === null ? (
            <p className="text-sm text-muted-foreground">loading…</p>
          ) : totp.enabled ? (
            <div className="flex flex-wrap items-center gap-3">
              <Badge className="bg-emerald-600 hover:bg-emerald-600">enabled</Badge>
              <Button variant="outline" size="sm" onClick={() => void totpAction("disable")} disabled={busy || code.length !== 6}>
                disable (requires code)
              </Button>
              <div className="flex items-center gap-2">
                <Input value={code} onChange={(e) => setCode(e.target.value)} placeholder="123456" className="w-28 font-mono" maxLength={6} inputMode="numeric" />
              </div>
            </div>
          ) : secret ? (
            <div className="space-y-2">
              <p className="text-sm">Scan this secret in your authenticator, then verify:</p>
              <div className="flex items-center gap-2 rounded-md border p-2">
                <code className="break-all text-xs">{secret}</code>
                <Button variant="ghost" size="sm" onClick={() => copy(secret, "secret")}>
                  <Copy className="mr-1 h-3 w-3" /> {copied === "secret" ? "copied" : "copy"}
                </Button>
              </div>
              <p className="break-all font-mono text-xs text-muted-foreground">{otpauth}</p>
              <div className="flex items-end gap-2">
                <div className="space-y-1">
                  <Label htmlFor="totp-code">Code</Label>
                  <Input id="totp-code" value={code} onChange={(e) => setCode(e.target.value)} placeholder="123456" className="w-28 font-mono" maxLength={6} inputMode="numeric" />
                </div>
                <Button onClick={() => void totpAction("verify")} disabled={busy || code.length !== 6}>
                  Verify &amp; enable
                </Button>
              </div>
            </div>
          ) : (
            <Button size="sm" onClick={() => void totpAction("enroll")} disabled={busy}>
              {busy ? "generating…" : "Enroll authenticator"}
            </Button>
          )}
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle className="text-base">Discord OAuth (production auth)</CardTitle>
          <CardDescription>Authorization-code flow with state-parameter CSRF binding per Discord&apos;s OAuth2 docs. Set DASH_DISCORD_CLIENT_ID / DASH_DISCORD_CLIENT_SECRET to activate.</CardDescription>
        </CardHeader>
        <CardContent>
          {info?.discord_oauth ? (
            <a href="/api/dash/oauth/start" className="text-sm font-medium underline underline-offset-4">
              Sign in with Discord
            </a>
          ) : (
            <p className="text-sm text-muted-foreground">Not configured in this environment — the flow is wired and state-checked, disabled without credentials.</p>
          )}
        </CardContent>
      </Card>
    </div>
  );
}
