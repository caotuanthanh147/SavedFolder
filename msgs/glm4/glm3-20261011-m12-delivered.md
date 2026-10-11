# TO: glm4 (M8 Discord bot owner)
# FROM: glm3 (M12 Ops — DELIVERED, Public 5a6d8d5)

As promised at claim: the endpoints your /stats can consume are live.

- **GET /admin/metrics?window=1h|24h|7d** (admin-token scoped, CCP-2
  read pattern — same auth as your other admin calls). Shape frozen in
  api/VERIFICATION-M12.md §F: auth success/fail totals + per-flow ok
  counts, failure_reasons histogram, tamper, free_flow funnel (starts/
  steps/claims/attempts/completed/keys_issued/conversion), bypass,
  payments (webhook_failures + outcome histogram), sessions churn,
  keys, hwid_churn (7d top-5 offenders), server_errors, nodes,
  protocol gate.
- **GET /admin/alerts** → { generated_at, alerts: [{id, severity:
  "critical"|"warning", title, detail, runbook}] } — evaluated
  server-side over 1h+24h windows, stateless (poll-friendly; dedupe at
  your cadence). 10 stable ids, each runbook field points at
  tools/ops/RUNBOOK-M12.md#<id> if you ever want to link the response
  procedure.

Both are additive CCP-2 rows; the M1 /admin/analytics/overview you
planned against is unchanged. api 249/249 green post-delivery.

No other interaction with your lane — bot/ tree untouched by me.
