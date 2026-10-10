"use client";

import { useState } from "react";
import { Alert, AlertDescription, AlertTitle } from "@/components/ui/alert";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { ScrollArea } from "@/components/ui/scroll-area";
import { Skeleton } from "@/components/ui/skeleton";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { NodeRow, ProtocolVersionRow, gw } from "@/lib/api";
import { useApiData } from "@/lib/use-api-data";
import { Globe, Plus, RefreshCw, ServerCog, Trash2 } from "lucide-react";

export function NodesView(): React.JSX.Element {
  const [actionError, setActionError] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const { data, error, refresh } = useApiData(async () => {
    const [n, p] = await Promise.all([
      gw<{ rows: NodeRow[] }>("GET", "/admin/nodes").then((r) => r.rows),
      gw<{ rows: ProtocolVersionRow[] }>("GET", "/admin/protocol-versions").then((r) => r.rows),
    ]);
    return { nodes: n, protocols: p };
  }, []);
  const nodes: NodeRow[] | null = data?.nodes ?? null;
  const protocols: ProtocolVersionRow[] | null = data?.protocols ?? null;
  const [hostname, setHostname] = useState("");
  const [region, setRegion] = useState("");
  const [pvVersion, setPvVersion] = useState("");
  const [pvHandler, setPvHandler] = useState("v1");
  const [pvMinLoader, setPvMinLoader] = useState("1.0.0");



  async function addNode(): Promise<void> {
    setBusy(true);
    try {
      await gw("POST", "/admin/nodes", { action: "add", hostname: hostname.trim(), region: region.trim().length > 0 ? region.trim() : null });
      setNotice(`Node ${hostname.trim()} added/reactivated (audited).`);
      setHostname("");
      setRegion("");
      refresh();
    } catch (e) {
      setActionError(e instanceof Error ? e.message : "add failed");
    } finally {
      setBusy(false);
    }
  }

  async function disableNode(h: string): Promise<void> {
    setBusy(true);
    try {
      await gw("POST", "/admin/nodes", { action: "disable", hostname: h });
      setNotice(`Node ${h} disabled (audited).`);
      refresh();
    } catch (e) {
      setActionError(e instanceof Error ? e.message : "disable failed");
    } finally {
      setBusy(false);
    }
  }

  async function registerVersion(): Promise<void> {
    setBusy(true);
    try {
      await gw("POST", "/admin/protocol-versions", {
        action: "register",
        version: pvVersion.trim(),
        handler: pvHandler.trim(),
        min_loader: pvMinLoader.trim().length > 0 ? pvMinLoader.trim() : null,
      });
      setNotice(`Protocol ${pvVersion.trim()} registered (audited).`);
      setPvVersion("");
      refresh();
    } catch (e) {
      setActionError(e instanceof Error ? e.message : "register failed");
    } finally {
      setBusy(false);
    }
  }

  async function retireVersion(v: string): Promise<void> {
    setBusy(true);
    try {
      await gw("POST", "/admin/protocol-versions", { action: "retire", version: v });
      setNotice(`Protocol ${v} retired (audited). Retiring ALL active rows is the kill switch (§19).`);
      refresh();
    } catch (e) {
      setActionError(e instanceof Error ? e.message : "retire failed");
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="space-y-4">
      {notice && (
        <Alert>
          <ServerCog className="h-4 w-4" />
          <AlertDescription>{notice}</AlertDescription>
        </Alert>
      )}
      {(error ?? actionError) && (
        <Alert variant="destructive">
          <AlertTitle>API error</AlertTitle>
          <AlertDescription>{error ?? actionError}</AlertDescription>
        </Alert>
      )}

      <div className="grid gap-4 lg:grid-cols-2">
        <Card>
          <CardHeader>
            <CardTitle className="flex items-center gap-2 text-base">
              <Globe className="h-4 w-4" /> Auth nodes
            </CardTitle>
            <CardDescription>Multi-hostname deployment surface (D11: one anycast hostname at launch, more later).</CardDescription>
          </CardHeader>
          <CardContent className="space-y-3">
            {nodes === null ? (
              <Skeleton className="h-24" />
            ) : (
              <ScrollArea className="max-h-56">
                <Table>
                  <TableHeader>
                    <TableRow>
                      <TableHead>Hostname</TableHead>
                      <TableHead>Region</TableHead>
                      <TableHead>State</TableHead>
                      <TableHead className="text-right">Action</TableHead>
                    </TableRow>
                  </TableHeader>
                  <TableBody>
                    {nodes.map((n) => (
                      <TableRow key={n.id}>
                        <TableCell className="font-mono text-xs">{n.hostname}</TableCell>
                        <TableCell className="text-xs">{n.region ?? "—"}</TableCell>
                        <TableCell>
                          <Badge variant={n.active ? "default" : "secondary"} className={n.active ? "bg-emerald-600 hover:bg-emerald-600" : ""}>
                            {n.active ? "active" : "disabled"}
                          </Badge>
                        </TableCell>
                        <TableCell className="text-right">
                          {n.active && (
                            <Button variant="ghost" size="icon" onClick={() => void disableNode(n.hostname)} disabled={busy} title="disable" aria-label="disable node">
                              <Trash2 className="h-4 w-4 text-destructive" />
                            </Button>
                          )}
                        </TableCell>
                      </TableRow>
                    ))}
                  </TableBody>
                </Table>
              </ScrollArea>
            )}
            <div className="flex flex-wrap items-end gap-2 border-t pt-3">
              <div className="space-y-1">
                <Label htmlFor="hostname">Hostname</Label>
                <Input id="hostname" value={hostname} onChange={(e) => setHostname(e.target.value)} placeholder="auth3.example.net" className="w-52 font-mono" />
              </div>
              <div className="space-y-1">
                <Label htmlFor="region">Region</Label>
                <Input id="region" value={region} onChange={(e) => setRegion(e.target.value)} placeholder="apac" className="w-24" />
              </div>
              <Button size="sm" onClick={() => void addNode()} disabled={busy || hostname.trim().length === 0}>
                <Plus className="mr-1 h-4 w-4" /> Add
              </Button>
            </div>
          </CardContent>
        </Card>

        <Card>
          <CardHeader>
            <CardTitle className="flex items-center gap-2 text-base">
              <ServerCog className="h-4 w-4" /> Protocol versions
            </CardTitle>
            <CardDescription>check_key gates on the least-strict active min_loader; auth gates on the version row (M1 Q1 gate).</CardDescription>
          </CardHeader>
          <CardContent className="space-y-3">
            {protocols === null ? (
              <Skeleton className="h-24" />
            ) : (
              <ScrollArea className="max-h-56">
                <Table>
                  <TableHeader>
                    <TableRow>
                      <TableHead>Version</TableHead>
                      <TableHead>Handler</TableHead>
                      <TableHead>Min loader</TableHead>
                      <TableHead>State</TableHead>
                      <TableHead className="text-right">Action</TableHead>
                    </TableRow>
                  </TableHeader>
                  <TableBody>
                    {protocols.map((p) => (
                      <TableRow key={p.version}>
                        <TableCell className="font-mono">v{p.version}</TableCell>
                        <TableCell className="font-mono text-xs">{p.handler}</TableCell>
                        <TableCell className="text-xs">{p.min_loader ?? "any"}</TableCell>
                        <TableCell>
                          <Badge variant={p.active ? "default" : "secondary"} className={p.active ? "bg-emerald-600 hover:bg-emerald-600" : ""}>
                            {p.active ? "active" : "retired"}
                          </Badge>
                        </TableCell>
                        <TableCell className="text-right">
                          {p.active && (
                            <Button variant="ghost" size="sm" onClick={() => void retireVersion(p.version)} disabled={busy}>
                              retire
                            </Button>
                          )}
                        </TableCell>
                      </TableRow>
                    ))}
                  </TableBody>
                </Table>
              </ScrollArea>
            )}
            <div className="flex flex-wrap items-end gap-2 border-t pt-3">
              <div className="space-y-1">
                <Label htmlFor="pv-version">Version</Label>
                <Input id="pv-version" value={pvVersion} onChange={(e) => setPvVersion(e.target.value)} placeholder="3" className="w-20 font-mono" />
              </div>
              <div className="space-y-1">
                <Label htmlFor="pv-handler">Handler</Label>
                <Input id="pv-handler" value={pvHandler} onChange={(e) => setPvHandler(e.target.value)} placeholder="v1" className="w-20 font-mono" />
              </div>
              <div className="space-y-1">
                <Label htmlFor="pv-min">Min loader</Label>
                <Input id="pv-min" value={pvMinLoader} onChange={(e) => setPvMinLoader(e.target.value)} placeholder="1.2.0" className="w-28 font-mono" />
              </div>
              <Button size="sm" onClick={() => void registerVersion()} disabled={busy || pvVersion.trim().length === 0}>
                <Plus className="mr-1 h-4 w-4" /> Register
              </Button>
            </div>
          </CardContent>
        </Card>
      </div>

      <div className="flex items-center justify-end">
        <Button variant="outline" size="sm" onClick={() => refresh()}>
          <RefreshCw className="mr-1 h-3 w-3" /> refresh
        </Button>
      </div>
    </div>
  );
}
