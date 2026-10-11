// M8 — typed admin API client (doc §15: "Admin permission checks happen
// server-side via the admin API" — every privileged action below travels
// through the documented endpoints with the Bearer admin token; the bot
// never touches the database).
export interface KeyRow {
  id: string;
  project_id: string;
  tier: string;
  status: string;
  hwid_bound: boolean;
  hwid_resets: number;
  discord_id: string | null;
  roblox_user_id: number | null;
  note: string | null;
  total_executions: number;
  created_by: string;
  created_at: number;
  expires_at: number | null;
  first_used_at: number | null;
  last_used_at: number | null;
}

export interface KeyScriptRow {
  script_id: string;
  name: string;
  keyless: boolean;
}

export interface KeyDetail extends KeyRow {
  scripts: KeyScriptRow[];
}

export interface UserRow {
  identity: string;
  kind: string;
  key_count: number;
  active_keys: number;
  hwids: number;
  total_executions: number;
  first_seen: number;
  last_used: number | null;
}

export interface LinkResult {
  ok: boolean;
  id: string;
  tier: string;
  status: string;
  expires_at: number | null;
  already: boolean;
}

export interface ApiError {
  error: string;
  field?: string;
  retry_after_sec?: number;
  detail?: string;
}

export interface MetricsSnapshot {
  window: string;
  generated_at: number;
  auth: { total_ok: number; total_fail: number; success_rate: number | null; attempts: number };
  tamper: { total: number };
  free_flow: { starts: number; claims: number; keys_issued: number; conversion: number | null };
  sessions: { created: number; live_now: number; killed: number };
  keys: { active: number; revoked: number; expiring_7d: number };
  server_errors: { total: number };
  nodes: { active: number; inactive: number };
}

export interface LeakLookupResult {
  watermark_id: string;
  sessions: { id: string; key_id: string | null; script_id: string | null; created_at: number; expires_at: number | null }[];
  key: { id: string; tier: string; status: string; discord_id: string | null; expires_at: number | null } | null;
  events: { type: string; detail: string | null; created_at: number }[];
}

export type ApiCall<T> = ({ ok: true } & T) | { ok: false; status: number; error: ApiError | "network" };

export class AdminApi {
  constructor(
    private readonly baseUrl: string,
    private readonly token: string,
  ) {}

  private async call<T>(method: string, path: string, body?: unknown): Promise<ApiCall<T>> {
    let res: Response;
    try {
      res = await fetch(this.baseUrl + path, {
        method,
        headers: {
          authorization: `Bearer ${this.token}`,
          ...(body !== undefined ? { "content-type": "application/json" } : {}),
        },
        ...(body !== undefined ? { body: JSON.stringify(body) } : {}),
      });
    } catch {
      return { ok: false, status: 0, error: "network" };
    }
    let data: unknown = null;
    const text = await res.text();
    if (text.length > 0) {
      try {
        data = JSON.parse(text);
      } catch {
        data = null;
      }
    }
    if (!res.ok) {
      // The api has two error shapes: admin handlers answer {"error": ...},
      // envelope-signed endpoints answer {"code": ..., "data": {...}}
      // (e.g. reset-hwid's 429 RATE_LIMITED carries retry_after_sec in data).
      let err: ApiError | "network" = "network";
      if (typeof data === "object" && data !== null) {
        const d = data as Record<string, unknown>;
        if (typeof d.error === "string") {
          err = d as unknown as ApiError;
        } else if (typeof d.code === "string") {
          const inner = typeof d.data === "object" && d.data !== null ? (d.data as { retry_after_sec?: number }) : {};
          err = { error: d.code, ...inner };
        }
      }
      return { ok: false, status: res.status, error: err };
    }
    return { ok: true, ...(typeof data === "object" && data !== null ? (data as object) : {}) } as ApiCall<T>;
  }

  /** CCP-M8 P1 — POST /admin/keys/link. */
  linkKey(key: string, discordId: string): Promise<ApiCall<LinkResult>> {
    return this.call<LinkResult>("POST", "/admin/keys/link", { key, discord_id: discordId });
  }

  /** CCP-M8 P2 — GET /admin/keys/:id. */
  keyDetail(id: string): Promise<ApiCall<KeyDetail>> {
    return this.call<KeyDetail>("GET", `/admin/keys/${encodeURIComponent(id)}`);
  }

  listKeys(query: { status?: string; q?: string; limit?: number; offset?: number } = {}): Promise<ApiCall<{ rows: KeyRow[]; total: number }>> {
    const parts: string[] = [];
    if (query.status !== undefined) parts.push(`status=${encodeURIComponent(query.status)}`);
    if (query.q !== undefined) parts.push(`q=${encodeURIComponent(query.q)}`);
    if (query.limit !== undefined) parts.push(`limit=${query.limit}`);
    if (query.offset !== undefined) parts.push(`offset=${query.offset}`);
    const qs = parts.length > 0 ? `?${parts.join("&")}` : "";
    return this.call<{ rows: KeyRow[]; total: number }>("GET", `/admin/keys${qs}`);
  }

  createKeys(body: {
    project_id: string;
    tier: string;
    count?: number;
    days?: number | null;
    note?: string | null;
    script_ids: string[];
  }): Promise<ApiCall<{ keys: { id: string; key: string }[] }>> {
    return this.call<{ keys: { id: string; key: string }[] }>("POST", "/admin/keys", body);
  }

  patchKey(id: string, body: { extend_days?: number; tier?: string; note?: string | null }): Promise<ApiCall<{ ok: boolean }>> {
    return this.call<{ ok: boolean }>("PATCH", `/admin/keys/${encodeURIComponent(id)}`, body);
  }

  revokeKey(id: string): Promise<ApiCall<{ ok: boolean }>> {
    return this.call<{ ok: boolean }>("POST", `/admin/keys/${encodeURIComponent(id)}/revoke`, {});
  }

  resetHwid(id: string): Promise<ApiCall<{ ok: boolean }>> {
    return this.call<{ ok: boolean }>("POST", `/admin/keys/${encodeURIComponent(id)}/reset-hwid`, {});
  }

  blacklistAdd(body: { kind: string; value: string; reason?: string | null; project_id?: string | null }): Promise<ApiCall<{ ok: boolean; id: string }>> {
    return this.call<{ ok: boolean; id: string }>("POST", "/admin/blacklist", body);
  }

  /** CCP-M8 P3 — POST /admin/blacklist/:id/remove. */
  blacklistRemove(id: string): Promise<ApiCall<{ ok: boolean }>> {
    return this.call<{ ok: boolean }>("POST", `/admin/blacklist/${encodeURIComponent(id)}/remove`, {});
  }

  listUsers(q?: string): Promise<ApiCall<{ rows: UserRow[] }>> {
    const qs = q !== undefined ? `?q=${encodeURIComponent(q)}` : "";
    return this.call<{ rows: UserRow[] }>("GET", `/admin/users${qs}`);
  }

  metrics(window: string): Promise<ApiCall<MetricsSnapshot>> {
    return this.call<MetricsSnapshot>("GET", `/admin/metrics?window=${encodeURIComponent(window)}`);
  }

  alerts(): Promise<ApiCall<{ generated_at: number; alerts: { id: string; severity: string; title: string }[] }>> {
    return this.call<{ generated_at: number; alerts: { id: string; severity: string; title: string }[] }>("GET", "/admin/alerts");
  }

  leakLookup(value: string): Promise<ApiCall<LeakLookupResult>> {
    // The api checks watermark_id (hex32) first, then session_token, then
    // artifact extraction; sending the value as both fields lets the server
    // pick the right path for whatever the admin pasted.
    return this.call<LeakLookupResult>("POST", "/admin/leak/lookup", { artifact: value, watermark_id: value });
  }
}
