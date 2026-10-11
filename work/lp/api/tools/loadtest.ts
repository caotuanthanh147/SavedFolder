// M12 load test (doc §19 "load test before launch", D-M12-10).
//
// In-process dispatch storm against the REAL router + handlers + SQLite:
// measures ROUTER+HANDLER+SQL cost only — no network, no CF edge, no
// D1-over-RPC. Honest about what that means: it catches algorithmic
// regressions (accidental cross joins, unbounded scans, per-request
// blowups) before launch; deployed-edge latency is an owner action
// (RUNBOOK-M12 §load).
//
// Usage: bun run tools/loadtest.ts [requests-per-op] [concurrency]
// Output: per-op p50/p95/p99 µs + req/s, plus a mixed concurrent phase.

import { ADMIN_TOKEN, SCRIPT_ID, TestEnv, buildEnv, makeSignedInput } from "../test/helpers";
import { buildRoutes, dispatch } from "../src/router";
import { RequestInput } from "../src/flow";

const N = parseInt(process.argv[2] ?? "500", 10);
const CONC = parseInt(process.argv[3] ?? "10", 10);

function percentile(sorted: number[], p: number): number {
  if (sorted.length === 0) return 0;
  const idx = Math.min(sorted.length - 1, Math.floor((p / 100) * sorted.length));
  return sorted[idx];
}

function fmt(n: number): string {
  return n >= 10000 ? Math.round(n).toLocaleString() : n.toFixed(1);
}

interface OpResult {
  op: string;
  n: number;
  p50us: number;
  p95us: number;
  p99us: number;
  rps: number;
  errors: number;
}

async function runOp(label: string, env: TestEnv, inputs: RequestInput[]): Promise<OpResult> {
  // Warmup (statement prep, JIT) — excluded from measurements.
  for (let i = 0; i < Math.min(25, inputs.length); i++) {
    await dispatch(buildRoutes(), env.ctx, env.config, inputs[i]);
  }
  const durations: number[] = [];
  let errors = 0;
  const t0 = performance.now();
  for (const input of inputs) {
    const s = performance.now();
    const res = await dispatch(buildRoutes(), env.ctx, env.config, input);
    durations.push(performance.now() - s);
    if (res.status >= 500) errors++;
  }
  const wall = (performance.now() - t0) / 1000;
  const sorted = [...durations].sort((a, b) => a - b);
  return {
    op: label,
    n: inputs.length,
    p50us: percentile(sorted, 50) * 1000,
    p95us: percentile(sorted, 95) * 1000,
    p99us: percentile(sorted, 99) * 1000,
    rps: inputs.length / wall,
    errors,
  };
}

async function main(): Promise<void> {
  const env: TestEnv = await buildEnv();
  const key = await env.createKey({ tier: "paid", days: 30 });

  // Pre-generate signed inputs so measurement covers dispatch only.
  // IPs rotate (a real storm comes from many clients; a single IP would
  // trip the 60/min general limiter, which is the CORRECT behavior).
  const syncInputs: RequestInput[] = [];
  const statusInputs: RequestInput[] = [];
  const checkInputs: RequestInput[] = [];
  const metricsInputs: RequestInput[] = [];
  for (let i = 0; i < N; i++) {
    const ip = `203.0.113.${(i % 254) + 1}`;
    syncInputs.push(await makeSignedInput("GET", "/sync", null, { ip }));
    statusInputs.push(await makeSignedInput("GET", "/status", null, { ip }));
    checkInputs.push(await makeSignedInput("POST", "/check_key", { key: key.plaintext, script_id: SCRIPT_ID, lv: "1.0.0" }, { ip }));
    metricsInputs.push(await makeSignedInput("GET", "/admin/metrics?window=1h", null, { ip, headers: { authorization: `Bearer ${ADMIN_TOKEN}` } }));
  }

  console.log(`M12 load test — in-process dispatch, N=${N}/op sequential (warmup excluded), bun ${Bun.version}`);
  console.log("op                n     p50µs    p95µs    p99µs     req/s   err");
  console.log("--------------- ----- -------- -------- -------- -------- -----");

  const results: OpResult[] = [];
  results.push(await runOp("GET /sync", env, syncInputs));
  results.push(await runOp("GET /status", env, statusInputs));
  results.push(await runOp("POST /check_key", env, checkInputs));
  results.push(await runOp("GET /admin/metrics", env, metricsInputs));
  for (const r of results) {
    console.log(`${r.op.padEnd(15)} ${String(r.n).padStart(5)} ${fmt(r.p50us).padStart(8)} ${fmt(r.p95us).padStart(8)} ${fmt(r.p99us).padStart(8)} ${fmt(r.rps).padStart(8)} ${String(r.errors).padStart(5)}`);
  }

  // Mixed concurrent phase: CONC requests in flight, mixed ops, one wall clock.
  const mixed: RequestInput[] = [];
  for (let i = 0; i < N; i++) {
    const ip = `198.51.100.${(i % 254) + 1}`;
    const k = i % 4;
    if (k === 0) mixed.push(await makeSignedInput("GET", "/sync", null, { ip }));
    else if (k === 1) mixed.push(await makeSignedInput("GET", "/status", null, { ip }));
    else if (k === 2) mixed.push(await makeSignedInput("POST", "/check_key", { key: key.plaintext, script_id: SCRIPT_ID, lv: "1.0.0" }, { ip }));
    else mixed.push(await makeSignedInput("GET", "/admin/metrics?window=1h", null, { ip, headers: { authorization: `Bearer ${ADMIN_TOKEN}` } }));
  }
  const routes = buildRoutes();
  let done = 0;
  let errs = 0;
  const c0 = performance.now();
  const workers: Promise<void>[] = [];
  const shard = Math.ceil(mixed.length / CONC);
  for (let w = 0; w < CONC; w++) {
    workers.push(
      (async () => {
        for (let i = w * shard; i < Math.min((w + 1) * shard, mixed.length); i++) {
          const res = await dispatch(routes, env.ctx, env.config, mixed[i]);
          if (res.status >= 500) errs++;
          done++;
        }
      })(),
    );
  }
  await Promise.all(workers);
  const cWall = (performance.now() - c0) / 1000;
  console.log(`${`mixed ×${CONC} conc`.padEnd(15)} ${String(done).padStart(5)} ${"-".padStart(8)} ${"-".padStart(8)} ${"-".padStart(8)} ${fmt(done / cWall).padStart(8)} ${String(errs).padStart(5)}`);

  // Machine-readable summary for VERIFICATION-M12.
  console.log("\nJSON:");
  console.log(JSON.stringify({ n: N, concurrency: CONC, ops: results, mixed: { n: done, rps: done / cWall, errors: errs } }));
}

await main();
