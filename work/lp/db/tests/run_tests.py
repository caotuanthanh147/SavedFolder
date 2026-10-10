#!/usr/bin/env python3
"""M2 Database test suite.

Runs the migration SQL and seed SQL against a local SQLite database with
PRAGMA foreign_keys = on, mirroring D1's default foreign-key enforcement
(developers.cloudflare.com/d1/sql-api/foreign-keys/). No third-party Python
packages required.

Usage:  python3 db/tests/run_tests.py     (from the repo root, or anywhere —
        paths are resolved relative to this file)
Requires `bun` on PATH for the seed tests (the platform runtime).
"""

import hashlib
import os
import shutil
import sqlite3
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
DB_ROOT = os.path.dirname(HERE)
MIGRATIONS_DIR = os.path.join(DB_ROOT, "migrations")
SEED_TS = os.path.join(DB_ROOT, "seed", "seed.ts")

FAILURES = []
CHECKS = 0


def check(name, ok, detail=""):
    global CHECKS
    CHECKS += 1
    status = "PASS" if ok else "FAIL"
    print(f"[{status}] {name}" + (f" — {detail}" if detail and not ok else ""))
    if not ok:
        FAILURES.append(name)


def apply_migrations(conn):
    files = sorted(f for f in os.listdir(MIGRATIONS_DIR) if f.endswith(".sql"))
    for f in files:
        with open(os.path.join(MIGRATIONS_DIR, f), "r", encoding="utf-8") as fh:
            sql = fh.read()
        conn.executescript(sql)
    return files


def fresh_db(path):
    conn = sqlite3.connect(path)
    conn.execute("PRAGMA foreign_keys = on;")
    return conn


def plan_of(conn, sql, params=()):
    rows = conn.execute("EXPLAIN QUERY PLAN " + sql, params).fetchall()
    return " | ".join(r[3] for r in rows)


def insert_fixture(conn):
    """Minimal runtime fixture exercising the doc.md section 6 relations."""
    conn.execute(
        "INSERT INTO projects (id, name, slug, owner_id, signing_key_id, created_at) "
        "VALUES ('p1', 'Demo', 'demo', 'owner1', 'sk1', 1700000000)"
    )
    conn.execute(
        "INSERT INTO scripts (id, project_id, name, keyless, active_version, created_at) "
        "VALUES ('s1', 'p1', 'demo-script', 0, 1, 1700000000)"
    )
    conn.execute(
        "INSERT INTO script_games (script_id, game_id) VALUES ('s1', 12345)"
    )
    conn.execute(
        "INSERT INTO script_versions (script_id, version, blob_ref, build_hash, init_build, notes, created_at) "
        "VALUES ('s1', 1, 'blob1', 'hash1', 'init1', NULL, 1700000000)"
    )
    conn.execute(
        "INSERT INTO keys (id, project_id, key_hash, tier, status, created_by, created_at) "
        "VALUES ('k1', 'p1', 'aa11', 'paid', 'active', 'owner1', 1700000000)"
    )
    conn.execute("INSERT INTO key_scripts (key_id, script_id) VALUES ('k1', 's1')")
    conn.execute(
        "INSERT INTO sessions (id, key_id, script_id, version, hwid_hash, ip_hash, watermark_id, created_at, expires_at) "
        "VALUES ('sess1', 'k1', 's1', 1, 'hw1', 'ip1', 'wm1', 1700000000, 1700003600)"
    )
    conn.execute(
        "INSERT INTO events (id, key_id, type, detail, created_at) "
        "VALUES ('e1', 'k1', 'validate_ok', NULL, 1700000000)"
    )


def main():
    tmpdir = tempfile.mkdtemp(prefix="m2-tests-")
    dbfile = os.path.join(tmpdir, "test.db")
    try:
        conn = fresh_db(dbfile)
        files = apply_migrations(conn)

        # --- schema ---------------------------------------------------------
        expected_tables = {
            "projects", "scripts", "script_games", "script_versions", "keys",
            "key_scripts", "sessions", "blacklist", "nodes",
            "protocol_versions", "checkpoints", "free_attempts", "admins",
            "audit_log", "events",
        }
        got = {r[0] for r in conn.execute(
            "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'")}
        check("all 15 doc.md 6 tables created", got == expected_tables,
              f"missing={expected_tables - got} extra={got - expected_tables}")
        check("migrations applied as sequential .sql files",
              files == ["0001_initial_schema.sql", "0002_indexes.sql"], f"got {files}")

        strict_flags = {r[1]: r[5] for r in conn.execute("PRAGMA table_list") if r[1] in expected_tables}
        check("every table is STRICT", all(v == 1 for v in strict_flags.values()),
              str({k: v for k, v in strict_flags.items() if v != 1}))

        cols = {r[1]: r[2] for r in conn.execute("PRAGMA table_info(keys)")}
        expected_key_cols = {
            "id", "project_id", "key_hash", "tier", "status", "hwid_hash",
            "hwid_resets", "last_reset_at", "discord_id", "roblox_user_id",
            "note", "total_executions", "created_by", "created_at",
            "expires_at", "first_used_at", "last_used_at",
        }
        check("keys columns verbatim from doc.md 6", set(cols) == expected_key_cols,
              f"got {sorted(cols)}")

        # --- indexes --------------------------------------------------------
        idx = {r[0] for r in conn.execute(
            "SELECT name FROM sqlite_master WHERE type='index' AND name NOT LIKE 'sqlite_autoindex%'")}
        expected_idx = {
            "idx_keys_discord_id", "idx_sessions_key_id_created_at",
            "idx_events_key_id_created_at", "idx_blacklist_kind_value_hash",
            "idx_script_games_game_id",
        }
        check("documented indexes created", expected_idx <= idx, f"got {sorted(idx)}")

        patterns = [
            ("keys by key_hash (doc index list, via UNIQUE)",
             "SELECT * FROM keys WHERE key_hash = ?", ("aa11",)),
            ("keys by discord_id",
             "SELECT * FROM keys WHERE discord_id = ?", ("dd1",)),
            ("sessions by key_id, created_at",
             "SELECT * FROM sessions WHERE key_id = ? ORDER BY created_at", ("k1",)),
            ("events by key_id, created_at",
             "SELECT * FROM events WHERE key_id = ? ORDER BY created_at", ("k1",)),
            ("blacklist by kind + value_hash",
             "SELECT * FROM blacklist WHERE kind = ? AND value_hash = ?", ("hwid", "hh1")),
            ("script_games by game_id",
             "SELECT * FROM script_games WHERE game_id = ?", (12345,)),
        ]
        insert_fixture(conn)
        for name, sql, params in patterns:
            plan = plan_of(conn, sql, params)
            check(f"index used: {name}", "USING INDEX" in plan and "SCAN" not in plan, plan)

        # --- constraints ----------------------------------------------------
        try:
            conn.execute("INSERT INTO keys (id, project_id, key_hash, tier, status, created_by, created_at) "
                         "VALUES ('k2', 'p1', 'aa11', 'paid', 'active', 'owner1', 1)")
            ok = False
        except sqlite3.IntegrityError:
            ok = True
        check("keys.key_hash UNIQUE enforced", ok)

        try:
            conn.execute("INSERT INTO keys (id, project_id, key_hash, tier, status, created_by, created_at) "
                         "VALUES ('k3', 'nope', 'bb22', 'paid', 'active', 'owner1', 1)")
            ok = False
        except sqlite3.IntegrityError:
            ok = True
        check("foreign key keys.project_id enforced", ok)

        try:
            conn.execute("INSERT INTO key_scripts (key_id, script_id) VALUES ('ghost', 's1')")
            ok = False
        except sqlite3.IntegrityError:
            ok = True
        check("foreign key key_scripts.key_id enforced", ok)

        try:
            conn.execute("INSERT INTO keys (id, project_id, key_hash, tier, status, created_by, created_at, roblox_user_id) "
                         "VALUES ('k4', 'p1', 'cc33', 'paid', 'active', 'owner1', 1, 'abc')")
            conn.execute("INSERT INTO keys (id, project_id, key_hash, tier, status, created_by, created_at, note) "
                         "VALUES ('k5', 'p1', 'dd44', 'paid', 'active', 'owner1', 1, x'00')")
            ok = False
        except sqlite3.IntegrityError:
            ok = True
        check("STRICT rejects wrong types (text->INTEGER, blob->TEXT)", ok)

        defaults = conn.execute(
            "SELECT hwid_resets, total_executions FROM keys WHERE id = 'k1'").fetchone()
        check("keys defaults (hwid_resets=0, total_executions=0)",
              defaults == (0, 0), str(defaults))

        conn.execute(
            "INSERT INTO sessions (id, key_id, script_id, version, hwid_hash, ip_hash, watermark_id, created_at, expires_at) "
            "VALUES ('sess2', NULL, 's1', 1, 'hw2', 'ip2', 'wm2', 1, 2)")
        check("keyless session (key_id NULL) insertable",
              conn.execute("SELECT COUNT(*) FROM sessions WHERE key_id IS NULL").fetchone()[0] == 1)

        # --- owner rulings 2026-10-10 (msgs/docowner.txt Q3/Q4) ------------
        # sessions: FK RESTRICT — hard-deleting a key/script with sessions fails;
        # revoke/deactivate instead of hard-deleting
        try:
            conn.execute("DELETE FROM keys WHERE id = 'k1'")
            ok = False
        except sqlite3.IntegrityError:
            ok = True
        check("sessions FK: DELETE key with session RESTRICTed (owner Q3)", ok)
        try:
            conn.execute("DELETE FROM scripts WHERE id = 's1'")
            ok = False
        except sqlite3.IntegrityError:
            ok = True
        check("sessions FK: DELETE script with session RESTRICTed (owner Q3)", ok)

        # events: deliberately FK-less — failed validations may reference
        # non-existent keys (owner Q3)
        conn.execute(
            "INSERT INTO events (id, key_id, type, detail, created_at) "
            "VALUES ('e9', 'no-such-key', 'check_key_failed', 'x', 1)")
        check("events FK-less: unknown key_id insertable (owner Q3)",
              conn.execute("SELECT COUNT(*) FROM events WHERE key_id = 'no-such-key'").fetchone()[0] == 1)

        # checkpoints / free_attempts: project_id ON DELETE CASCADE (owner Q4)
        # (uses a fresh project p2 so unrelated FKs on p1 don't block the delete)
        conn.execute(
            "INSERT INTO projects (id, name, slug, owner_id, signing_key_id, created_at) "
            "VALUES ('p2', 'cascade probe', 'cascade-probe', 'owner1', 'sk2', 1)")
        conn.execute(
            "INSERT INTO checkpoints (id, project_id, position, provider, config) "
            "VALUES ('cp2', 'p2', 1, 'test', '{}')")
        conn.execute(
            "INSERT INTO free_attempts (id, project_id, fingerprint, step, token_hash, started_at, step_started_at) "
            "VALUES ('fa2', 'p2', 'fp2', 1, 'th2', 1, 1)")
        conn.execute("DELETE FROM projects WHERE id = 'p2'")
        left = (
            conn.execute("SELECT COUNT(*) FROM checkpoints WHERE id = 'cp2'").fetchone()[0],
            conn.execute("SELECT COUNT(*) FROM free_attempts WHERE id = 'fa2'").fetchone()[0],
        )
        check("project delete cascades checkpoints + free_attempts (owner Q4)",
              left == (0, 0), str(left))
        conn.close()

        # --- seed (bun) -----------------------------------------------------
        bun = shutil.which("bun")
        check("bun available on PATH for seed tests", bun is not None)
        if bun:
            seeddb = os.path.join(tmpdir, "seed.db")
            sconn = fresh_db(seeddb)
            apply_migrations(sconn)

            proc = subprocess.run(
                [bun, SEED_TS, "--print", "--test-fixtures"],
                capture_output=True, text=True, check=True)
            seed_sql = proc.stdout
            sconn.executescript(seed_sql)

            n_nodes = sconn.execute("SELECT COUNT(*) FROM nodes").fetchone()[0]
            check("seed: 1 node row", n_nodes == 1, str(n_nodes))
            node = sconn.execute("SELECT hostname, region, active FROM nodes").fetchone()
            check("seed: node values from fixtures", node == ("auth-node-1.test", "test", 1), str(node))

            pv = sconn.execute(
                "SELECT version, handler, min_loader, active FROM protocol_versions").fetchall()
            check("seed: protocol_versions row (owner Q1: v1/handler v1/1.0.0/active)",
                  pv == [("1", "v1", "1.0.0", 1)], str(pv))

            admin = sconn.execute(
                "SELECT role, api_token_hash FROM admins").fetchone()
            # owner Q2: store ONLY the SHA-256 of the SECRET part; the full
            # token is adm_<id>.<secret> (printed once, never stored)
            want_hash = hashlib.sha256(b"test-admin-secret-0123456789abcdef").hexdigest()
            check("seed: owner admin stores SHA-256 of the SECRET (adm_<id>.<secret> format)",
                  admin == ("owner", want_hash), str(admin))
            token_line = proc.stderr
            check("seed: full adm_<id>.<secret> token printed once to stderr",
                  "adm_000102030405060708090a0b0c0d0e0f.test-admin-secret-0123456789abcdef" in token_line,
                  token_line.strip()[:120])

            sconn.executescript(seed_sql)
            counts = (
                sconn.execute("SELECT COUNT(*) FROM nodes").fetchone()[0],
                sconn.execute("SELECT COUNT(*) FROM protocol_versions").fetchone()[0],
                sconn.execute("SELECT COUNT(*) FROM admins").fetchone()[0],
            )
            check("seed: idempotent (re-apply keeps counts)", counts == (1, 1, 1), str(counts))

            sconn.executescript(
                "INSERT INTO protocol_versions (version, handler, min_loader, active) "
                "VALUES ('1', 'v2handler', '2.0.0', 1) "
                "ON CONFLICT(version) DO UPDATE SET handler = excluded.handler, "
                "min_loader = excluded.min_loader, active = excluded.active;")
            pv2 = sconn.execute("SELECT handler, min_loader FROM protocol_versions WHERE version='1'").fetchone()
            check("seed: protocol row upserts on config change", pv2 == ("v2handler", "2.0.0"), str(pv2))

            # --- batch-style atomicity (db.batch abort semantics) ----------
            try:
                sconn.execute("BEGIN")
                sconn.execute(
                    "INSERT INTO nodes (id, hostname, region, active) VALUES ('n2', 'node-2.test', 'test', 1)")
                sconn.execute(
                    "INSERT INTO nodes (id, hostname, region, active) VALUES ('n3', 'auth-node-1.test', 'test', 1)")  # dup hostname
                sconn.commit()
                ok = False
            except sqlite3.IntegrityError:
                sconn.rollback()
                ok = True
            n_after = sconn.execute("SELECT COUNT(*) FROM nodes").fetchone()[0]
            check("batch-style atomicity: failed sequence rolls back entirely",
                  ok and n_after == 1, f"ok={ok} nodes={n_after}")

            # --- auth-init access pattern (doc 8 step 7) --------------------
            sconn.execute(
                "INSERT INTO projects (id, name, slug, owner_id, signing_key_id, created_at) "
                "VALUES ('p1', 'Demo', 'demo', 'owner1', 'sk1', 1)")
            sconn.execute(
                "INSERT INTO scripts (id, project_id, name, keyless, active_version, created_at) "
                "VALUES ('s1', 'p1', 'demo', 0, 1, 1)")
            sconn.execute("INSERT INTO script_games (script_id, game_id) VALUES ('s1', 777)")
            sconn.execute(
                "INSERT INTO keys (id, project_id, key_hash, tier, status, created_by, created_at) "
                "VALUES ('k1', 'p1', 'ee55', 'paid', 'active', 'owner1', 1)")
            sconn.execute("INSERT INTO key_scripts (key_id, script_id) VALUES ('k1', 's1')")
            row = sconn.execute(
                "SELECT k.status, k.tier, k.expires_at, s.keyless "
                "FROM keys k JOIN key_scripts ks ON ks.key_id = k.id "
                "JOIN scripts s ON s.id = ks.script_id "
                "LEFT JOIN script_games sg ON sg.script_id = s.id AND sg.game_id = ? "
                "WHERE k.key_hash = ? AND k.status = 'active'",
                (777, "ee55")).fetchone()
            check("auth-init join resolves key -> entitlement -> game",
                  row == ("active", "paid", None, 0), str(row))
            sconn.close()

        print(f"\n{CHECKS - len(FAILURES)}/{CHECKS} checks passed")
        if FAILURES:
            print("FAILED: " + ", ".join(FAILURES))
            return 1
        return 0
    finally:
        shutil.rmtree(tmpdir, ignore_errors=True)


if __name__ == "__main__":
    sys.exit(main())
