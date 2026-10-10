import { AppContext } from "./flow";

interface NodeRow {
  hostname: string;
}

interface VersionRow {
  version: string;
  handler: string;
}

export async function handleSync(ctx: AppContext, colo: string): Promise<Response> {
  const nodes = await ctx.db.all<NodeRow>("SELECT hostname FROM nodes WHERE active = 1 ORDER BY hostname", []);
  const body = {
    st: Math.floor(ctx.nowSec),
    nodes: nodes.map((n) => "https://" + n.hostname),
    colo,
  };
  return new Response(JSON.stringify(body), { status: 200, headers: { "content-type": "application/json" } });
}

export async function handleStatus(ctx: AppContext, active: boolean): Promise<Response> {
  const nodes = await ctx.db.all<NodeRow>("SELECT hostname FROM nodes WHERE active = 1 ORDER BY hostname", []);
  const versions = await ctx.db.all<VersionRow>("SELECT version, handler FROM protocol_versions WHERE active = 1", []);
  const versionMap: Record<string, string> = {};
  for (const v of versions) versionMap[v.version] = v.handler;
  const body = {
    active,
    versions: versionMap,
    nodes: nodes.map((n) => n.hostname),
  };
  return new Response(JSON.stringify(body), { status: 200, headers: { "content-type": "application/json" } });
}
