"use client";

import { useState } from "react";
import { Alert, AlertDescription, AlertTitle } from "@/components/ui/alert";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle, DialogTrigger } from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { ScrollArea } from "@/components/ui/scroll-area";
import { Skeleton } from "@/components/ui/skeleton";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { formatTime, gw, ScriptRow, shortHash } from "@/lib/api";
import { useApiData } from "@/lib/use-api-data";
import { FileCode2, Package, RefreshCw, Rocket, Upload } from "lucide-react";

function randomBuildHash(): string {
  const bytes = new Uint8Array(32);
  crypto.getRandomValues(bytes);
  return Array.from(bytes, (b) => b.toString(16).padStart(2, "0")).join("");
}

export function ScriptsView(): React.JSX.Element {
  const [actionError, setActionError] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const { data, error, refresh } = useApiData(() => gw<{ rows: ScriptRow[] }>("GET", "/admin/scripts"), []);
  const rows: ScriptRow[] | null = data?.rows ?? null;
  const [uploadFor, setUploadFor] = useState<ScriptRow | null>(null);
  const [notes, setNotes] = useState("");
  const [activate, setActivate] = useState(true);



  async function uploadVersion(script: ScriptRow): Promise<void> {
    setBusy(true);
    try {
      const nextVersion = (script.versions[0]?.version ?? 0) + 1;
      const res = await gw<{ version: number }>("POST", `/admin/scripts/${script.id}/versions`, {
        build_hash: randomBuildHash(),
        blob_ref: `bundle/v${nextVersion}/demo`,
        init_build: "init-b1",
        notes: notes.trim().length > 0 ? notes.trim() : null,
        activate,
      });
      setNotice(`Version ${res.version} uploaded${activate ? " and activated" : ""} for ${script.name} (audited).`);
      setUploadFor(null);
      setNotes("");
      refresh();
    } catch (e) {
      setActionError(e instanceof Error ? e.message : "upload failed");
    } finally {
      setBusy(false);
    }
  }

  async function activateVersion(script: ScriptRow, version: number): Promise<void> {
    setBusy(true);
    try {
      await gw("POST", `/admin/scripts/${script.id}/activate`, { version });
      setNotice(`${script.name} active version → ${version} (rollback is the same call, audited).`);
      refresh();
    } catch (e) {
      setActionError(e instanceof Error ? e.message : "activate failed");
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="space-y-4">
      {notice && (
        <Alert>
          <Package className="h-4 w-4" />
          <AlertDescription>{notice}</AlertDescription>
        </Alert>
      )}
      {(error ?? actionError) && (
        <Alert variant="destructive">
          <AlertTitle>API error</AlertTitle>
          <AlertDescription>{error ?? actionError}</AlertDescription>
        </Alert>
      )}
      <div className="flex items-center justify-between">
        <p className="text-sm text-muted-foreground">Game routing, version history, and activation/rollback — all via the real admin endpoints.</p>
        <Button variant="outline" size="icon" onClick={() => refresh()} aria-label="refresh">
          <RefreshCw className="h-4 w-4" />
        </Button>
      </div>

      {rows === null ? (
        <div className="space-y-2">
          {Array.from({ length: 2 }).map((_, i) => (
            <Skeleton key={i} className="h-40" />
          ))}
        </div>
      ) : (
        rows.map((s) => (
          <Card key={s.id}>
            <CardHeader>
              <div className="flex flex-wrap items-center justify-between gap-2">
                <CardTitle className="flex items-center gap-2 text-base">
                  <FileCode2 className="h-4 w-4" /> {s.name}
                  {s.keyless && <Badge variant="secondary">keyless</Badge>}
                  <Badge variant="outline">active v{s.active_version}</Badge>
                </CardTitle>
                <Dialog open={uploadFor?.id === s.id} onOpenChange={(open) => setUploadFor(open ? s : null)}>
                  <DialogTrigger asChild>
                    <Button size="sm">
                      <Upload className="mr-1 h-4 w-4" /> New version
                    </Button>
                  </DialogTrigger>
                  <DialogContent>
                    <DialogHeader>
                      <DialogTitle>Upload version — {s.name}</DialogTitle>
                      <DialogDescription>POST /admin/scripts/:id/versions — a fresh build hash is generated; bundle bytes live in the blob store (R2 in production).</DialogDescription>
                    </DialogHeader>
                    <div className="space-y-3">
                      <div className="space-y-1">
                        <Label htmlFor="notes">Notes</Label>
                        <Input id="notes" value={notes} onChange={(e) => setNotes(e.target.value)} placeholder="changelog line" />
                      </div>
                      <label className="flex items-center gap-2 text-sm">
                        <input type="checkbox" checked={activate} onChange={(e) => setActivate(e.target.checked)} className="h-4 w-4 accent-primary" />
                        activate immediately after upload
                      </label>
                    </div>
                    <DialogFooter>
                      <Button onClick={() => void uploadVersion(s)} disabled={busy}>
                        {busy ? "uploading…" : "Upload"}
                      </Button>
                    </DialogFooter>
                  </DialogContent>
                </Dialog>
              </div>
              <CardDescription>
                game routing: {s.game_ids.length > 0 ? s.game_ids.join(", ") : "none"} · script id <code>{s.id}</code>
              </CardDescription>
            </CardHeader>
            <CardContent>
              <ScrollArea className="max-h-56">
                <Table>
                  <TableHeader>
                    <TableRow>
                      <TableHead>Version</TableHead>
                      <TableHead>Build hash</TableHead>
                      <TableHead>Init build</TableHead>
                      <TableHead>Notes</TableHead>
                      <TableHead>Uploaded</TableHead>
                      <TableHead className="text-right">State</TableHead>
                    </TableRow>
                  </TableHeader>
                  <TableBody>
                    {s.versions.map((v) => (
                      <TableRow key={v.version}>
                        <TableCell className="font-mono">v{v.version}</TableCell>
                        <TableCell className="font-mono text-xs">{shortHash(v.build_hash, 16)}</TableCell>
                        <TableCell className="text-xs">{v.init_build}</TableCell>
                        <TableCell className="max-w-40 truncate text-xs text-muted-foreground">{v.notes ?? "—"}</TableCell>
                        <TableCell className="text-xs">{formatTime(v.created_at)}</TableCell>
                        <TableCell className="text-right">
                          {s.active_version === v.version ? (
                            <Badge className="bg-emerald-600 hover:bg-emerald-600">active</Badge>
                          ) : (
                            <Button variant="ghost" size="sm" onClick={() => void activateVersion(s, v.version)} disabled={busy}>
                              <Rocket className="mr-1 h-3 w-3" /> activate
                            </Button>
                          )}
                        </TableCell>
                      </TableRow>
                    ))}
                  </TableBody>
                </Table>
              </ScrollArea>
            </CardContent>
          </Card>
        ))
      )}
    </div>
  );
}
