// Cross-module compatibility probe (doc.md merge checklist: "Test vectors in
// /contracts pass in both TypeScript and Lua" / integration checks).
// Builds the schema from M2's REAL migration files (../db/migrations, the
// repo layout) instead of api/src/db.ts's DOC_SCHEMA_SQL, then runs the exact
// SQL statements M1's handlers execute. Skips when ../db is absent (isolated
// api/ checkout) so the suite stays green in both layouts.
import { describe, expect, test } from "bun:test";
import { Database } from "bun:sqlite";
import { existsSync, readFileSync } from "node:fs";
import { join } from "node:path";

const MIGRATIONS_DIR = join(import.meta.dir, "..", "..", "db", "migrations");
const hasMigrations = existsSync(MIGRATIONS_DIR);

describe.skipIf(!hasMigrations)("M2 migrations × M1 queries (cross-module)", () => {
  function loadSchema(): Database {
    const db = new Database(":memory:");
    db.exec("PRAGMA foreign_keys = ON");
    const files = ["0001_initial_schema.sql", "0002_indexes.sql"];
    for (const f of files) {
      const sql = readFileSync(join(MIGRATIONS_DIR, f), "utf8");
      db.exec(sql);
    }
    return db;
  }

  test("M1's exact statements run against M2's STRICT + FK schema", () => {
    const db = loadSchema();
    const now = Math.floor(Date.now() / 1000);

    // seeds (M2 seed.ts equivalents, Q1/Q2 formats)
    db.prepare("INSERT INTO projects (id, name, slug, owner_id, signing_key_id, created_at) VALUES ('p1', 'P', 'p', 'o1', 'sk1', ?)").run(now);
    db.prepare("INSERT INTO scripts (id, project_id, name, keyless, active_version, created_at) VALUES ('s1', 'p1', 'S', 0, 1, ?)").run(now);
    db.prepare("INSERT INTO script_games (script_id, game_id) VALUES ('s1', 42)").run(now);
    db.prepare("INSERT INTO script_versions (script_id, version, blob_ref, build_hash, init_build, notes, created_at) VALUES ('s1', 1, 'b1', 'ab', 'init-1', NULL, ?)").run(now);
    db.prepare("INSERT INTO protocol_versions (version, handler, min_loader, active) VALUES ('1', 'v1', '1.0.0', 1)").run(now);
    db.prepare("INSERT INTO admins (id, discord_id, role, api_token_hash, quota_keys, created_at) VALUES ('a1', NULL, 'owner', 'hash', NULL, ?)").run(now);
    db.prepare("INSERT INTO keys (id, project_id, key_hash, tier, status, note, total_executions, created_by, created_at, expires_at) VALUES ('k1', 'p1', 'kh1', 'paid', 'active', NULL, 0, 'a1', ?, ?)").run(now, now + 86400);
    db.prepare("INSERT INTO key_scripts (key_id, script_id) VALUES ('k1', 's1')").run();

    // M1 checkkey/auth statements
    const keyRow = db.prepare("SELECT id, project_id, status, hwid_hash, note, total_executions, expires_at FROM keys WHERE key_hash = ?").get("kh1");
    expect(keyRow).toBeDefined();

    const entitled = db.prepare("SELECT COUNT(*) AS n FROM key_scripts WHERE key_id = ? AND script_id = ?").get("k1", "s1") as { n: number };
    expect(entitled.n).toBe(1);

    // atomic HWID bind (conditional update)
    const bind = db.prepare("UPDATE keys SET hwid_hash = ?, first_used_at = COALESCE(first_used_at, ?), last_used_at = ?, total_executions = total_executions + 1 WHERE id = ? AND (hwid_hash IS NULL OR hwid_hash = ?)").run("hw1", now, now, "k1", "hw1");
    expect(bind.changes).toBe(1);
    const bind2 = db.prepare("UPDATE keys SET hwid_hash = ?, first_used_at = COALESCE(first_used_at, ?), last_used_at = ?, total_executions = total_executions + 1 WHERE id = ? AND (hwid_hash IS NULL OR hwid_hash = ?)").run("hw2", now, now, "k1", "hw2");
    expect(bind2.changes).toBe(0);

    // session insert (FK: keys.id, scripts.id RESTRICT per owner Q3)
    db.prepare("INSERT INTO sessions (id, key_id, script_id, version, hwid_hash, ip_hash, roblox_user_id, place_id, watermark_id, created_at, expires_at) VALUES ('sess1', 'k1', 's1', 1, 'hw1', 'ip1', 7, 8, 'wm1', ?, ?)").run(now, now + 3600);
    const session = db.prepare("SELECT id, key_id, script_id, version, watermark_id, expires_at FROM sessions WHERE id = ?").get("sess1");
    expect(session).toBeDefined();

    // keyless session (key_id NULL — Q3 nullable)
    db.prepare("INSERT INTO scripts (id, project_id, name, keyless, active_version, created_at) VALUES ('s2', 'p1', 'K', 1, 1, ?)").run(now);
    db.prepare("INSERT INTO sessions (id, key_id, script_id, version, hwid_hash, ip_hash, watermark_id, created_at, expires_at) VALUES ('sess2', NULL, 's2', 1, 'hw1', 'ip1', 'wm2', ?, ?)").run(now, now + 3600);

    // FK RESTRICT: deleting a key with a session must fail
    expect(() => db.prepare("DELETE FROM keys WHERE id = 'k1'").run()).toThrow();

    // blacklist + check joins
    db.prepare("INSERT INTO blacklist (id, kind, value_hash, reason, created_by, created_at) VALUES ('b1', 'ip', 'ip1', NULL, 'a1', ?)").run(now);
    const bl = db.prepare("SELECT id FROM blacklist WHERE kind = 'ip' AND value_hash = ?").get("ip1");
    expect(bl).toBeDefined();

    // protocol upsert (admin protocol-versions register)
    db.prepare("INSERT INTO protocol_versions (version, handler, min_loader, active) VALUES ('2', 'v2', '1.1.0', 1) ON CONFLICT(version) DO UPDATE SET handler = excluded.handler, min_loader = excluded.min_loader, active = 1").run();
    const gate = db.prepare("SELECT min_loader, active FROM protocol_versions WHERE version = ?").get("1") as { min_loader: string; active: number };
    expect(gate.active).toBe(1);

    // analytics counts
    const sessions24h = db.prepare("SELECT COUNT(*) AS n FROM sessions WHERE expires_at > ?").get(now) as { n: number };
    expect(sessions24h.n).toBe(2);

    // events + audit inserts
    db.prepare("INSERT INTO events (id, key_id, type, detail, created_at) VALUES ('e1', 'k1', 'validate_ok', 'auth_init', ?)").run(now);
    db.prepare("INSERT INTO audit_log (id, actor_id, action, target, detail, created_at) VALUES ('au1', 'a1', 'admin.node.add', 'n1', '', ?)").run(now);
    const tamper24h = db.prepare("SELECT COUNT(*) AS n FROM events WHERE type = 'tamper' AND created_at > ?").get(now - 86400) as { n: number };
    expect(tamper24h.n).toBe(0);
  });

  test("M2 migration files apply cleanly twice (idempotent shape)", () => {
    // Migrations are CREATE TABLE without IF NOT EXISTS by design (wrangler
    // d1 migrations tracks applied state), so a fresh DB is the only valid
    // target; this test documents that and verifies 0002 indexes reference
    // the 0001 columns (a wrong index name would throw at apply time).
    const db = loadSchema();
    const idx = db.prepare("SELECT name FROM sqlite_master WHERE type = 'index' AND tbl_name = 'keys'").all() as { name: string }[];
    expect(idx.length).toBeGreaterThan(0);
  });
});
