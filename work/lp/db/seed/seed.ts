// M2 seed: configuration-driven, idempotent bootstrap rows for doc.md section 6.
//
// Only the rows the boot flows require are seeded:
//   nodes             -> served by /sync
//   protocol_versions -> served by /status
//   admins (owner)    -> admin API bootstrap (doc.md 5.8)
// Everything else (projects, scripts, keys) is runtime data created through
// the admin API, never seeded.
//
// Usage (bun):
//   LP_SEED_NODES=auth.example.com,auth2.example.com \
//   LP_SEED_NODE_REGIONS=eu,us \
//   LP_SEED_PROTO_VERSION=1 LP_SEED_PROTO_HANDLER=default \
//   LP_SEED_PROTO_MIN_LOADER=1.0.0 LP_SEED_PROTO_ACTIVE=1 \
//   LP_SEED_ADMIN_DISCORD_ID=1234567890 \
//   bun db/seed/seed.ts --print          # emit SQL to stdout
//   bun db/seed/seed.ts --local dev.db   # apply to a local SQLite file
//   bun db/seed/seed.ts --print --test-fixtures   # deterministic values (tests only)
//
// Remote apply:
//   bun db/seed/seed.ts --print > /tmp/seed.sql
//   wrangler d1 execute <DATABASE_NAME> --file /tmp/seed.sql --remote
//
// The first owner's admin token is generated at seed time (32 random bytes,
// base64url), printed to stderr exactly once, and stored only as its SHA-256
// hex hash (doc.md 5.1). No secret is ever hardcoded or written to a file.

import { randomBytes, createHash } from "node:crypto";

const args = process.argv.slice(2);
const wantPrint = args.includes("--print");
const localIdx = args.indexOf("--local");
const localFile = localIdx >= 0 ? args[localIdx + 1] : null;
const testFixtures = args.includes("--test-fixtures");

if (!wantPrint && !localFile) {
  console.error("usage: bun db/seed/seed.ts --print | --local <dbfile> [--test-fixtures]");
  process.exit(1);
}

function hexId(fixed?: string): string {
  if (fixed) return fixed;
  return randomBytes(16).toString("hex");
}

function sqlStr(v: string | null | undefined): string {
  if (v === null || v === undefined || v === "") return "NULL";
  if (/[\u0000-\u001f]/.test(v)) throw new Error("control characters not allowed in seed values");
  return "'" + v.replace(/'/g, "''") + "'";
}

interface SeedConfig {
  nodes: { hostname: string; region: string | null }[];
  proto: { version: string; handler: string; minLoader: string | null; active: number };
  admin: { discordId: string | null };
  now: number;
  adminId: string;
  adminToken: string;
}

function loadConfig(): SeedConfig {
  if (testFixtures) {
    return {
      nodes: [{ hostname: "auth-node-1.test", region: "test" }],
      proto: { version: "1", handler: "default", minLoader: "1.0.0", active: 1 },
      admin: { discordId: "000000000000000001" },
      now: 1700000000,
      adminId: "000102030405060708090a0b0c0d0e0f",
      adminToken: "test-admin-token-0123456789abcdef",
    };
  }
  const hostnames = (process.env.LP_SEED_NODES ?? "").split(",").map(s => s.trim()).filter(Boolean);
  const regions = (process.env.LP_SEED_NODE_REGIONS ?? "").split(",").map(s => s.trim());
  const nodes = hostnames.map((hostname, i) => ({ hostname, region: regions[i] || null }));
  const protoVersion = process.env.LP_SEED_PROTO_VERSION ?? "";
  const protoHandler = process.env.LP_SEED_PROTO_HANDLER ?? "";
  if ((hostnames.length > 0 || protoVersion || protoHandler) && !(protoVersion && protoHandler)) {
    console.error("LP_SEED_PROTO_VERSION and LP_SEED_PROTO_HANDLER must be set together");
    process.exit(1);
  }
  const active = Number(process.env.LP_SEED_PROTO_ACTIVE ?? "1");
  return {
    nodes,
    proto: {
      version: protoVersion,
      handler: protoHandler,
      minLoader: process.env.LP_SEED_PROTO_MIN_LOADER || null,
      active: active === 0 ? 0 : 1,
    },
    admin: { discordId: process.env.LP_SEED_ADMIN_DISCORD_ID || null },
    now: Math.floor(Date.now() / 1000),
    adminId: hexId(),
    adminToken: randomBytes(32).toString("base64url"),
  };
}

function buildSql(cfg: SeedConfig): { sql: string; statements: string[] } {
  const statements: string[] = [];
  for (const n of cfg.nodes) {
    statements.push(
      `INSERT INTO nodes (id, hostname, region, active) VALUES (${sqlStr(hexId())}, ${sqlStr(n.hostname)}, ${sqlStr(n.region)}, 1) ` +
        `ON CONFLICT(hostname) DO UPDATE SET region = excluded.region, active = 1;`
    );
  }
  if (cfg.proto.version) {
    statements.push(
      `INSERT INTO protocol_versions (version, handler, min_loader, active) VALUES (${sqlStr(cfg.proto.version)}, ${sqlStr(cfg.proto.handler)}, ${sqlStr(cfg.proto.minLoader)}, ${cfg.proto.active}) ` +
        `ON CONFLICT(version) DO UPDATE SET handler = excluded.handler, min_loader = excluded.min_loader, active = excluded.active;`
    );
  }
  const tokenHash = createHash("sha256").update(cfg.adminToken).digest("hex");
  statements.push(
    `INSERT INTO admins (id, discord_id, role, api_token_hash, quota_keys, created_at) ` +
      `SELECT ${sqlStr(cfg.adminId)}, ${sqlStr(cfg.admin.discordId)}, 'owner', ${sqlStr(tokenHash)}, NULL, ${cfg.now} ` +
      `WHERE NOT EXISTS (SELECT 1 FROM admins WHERE role = 'owner');`
  );
  return { sql: statements.join("\n") + "\n", statements };
}

const cfg = loadConfig();
const { sql, statements } = buildSql(cfg);

if (wantPrint) {
  process.stdout.write(sql);
  process.stderr.write(
    `admin token (shown once, only effective if no owner row existed): ${cfg.adminToken}\n`
  );
}

if (localFile) {
  const { Database } = await import("bun:sqlite");
  const db = new Database(localFile);
  db.exec("PRAGMA foreign_keys = on;");
  const tx = db.transaction((stmts: string[]) => {
    for (const s of stmts) db.exec(s);
  });
  tx(statements);
  db.close();
  process.stderr.write(
    `admin token (shown once, only effective if no owner row existed): ${cfg.adminToken}\n`
  );
}
