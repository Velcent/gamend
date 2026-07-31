# `Gamend.Retention`
[🔗](https://github.com/appsinacup/gamend/blob/v1.0.7/lib/gamend/retention.ex#L1)

Periodically prunes old rows from unbounded tables.

Retention is configured per table in days via env vars (see
`config/host_runtime.exs`); `0` or unset keeps data forever:

- `RETENTION_CHAT_DAYS` — `chat_messages` older than N days
- `RETENTION_NOTIFICATIONS_DAYS` — `notifications` older than N days
- `RETENTION_PAYMENT_EVENTS_DAYS` — payment provider webhook events older
  than N days (purchases/entitlements are never pruned)
- `RETENTION_LOBBY_SNAPSHOTS_DAYS` — lobby snapshots, events and their
  content blobs. Unlike the others this defaults to 30 rather than "keep
  forever": snapshots hold user metadata, and the window is what bounds that
  exposure. Runs flagged anomalous keep
  `RETENTION_LOBBY_SNAPSHOTS_FLAGGED_DAYS` instead (default 90).
- `RETENTION_PUSH_TOKENS_DAYS` — push tokens untouched (registered, used,
  or disabled) for N days. Defaults to 270 — Google's stale-token guidance
  — so the table tracks live devices, not install history.
- `RETENTION_INVITES_DAYS` — resolved group/party invites and join requests,
  N days after resolution (default 30). Pending rows are never pruned.
- `RETENTION_MATCHMAKING_TICKETS_HOURS` — tickets older than N hours
  (default 24), in any status.
- `RETENTION_TOURNAMENTS_DAYS` / `RETENTION_LEDGER_DAYS` — finished
  tournaments and the wallet/inventory ledgers. Both default to `0`: they
  are history an operator may be required to keep.
- `RETENTION_ABANDONED_LOBBY_MINUTES` (15) — lobbies nobody has been seen in
  for N minutes, in minutes rather than days. The same window releases a lobby
  seat held by a long-offline player and disbands a party everyone abandoned.

Expired IP bans, OAuth sessions older than a day, and user tokens past their
own context's validity are always removed (independent of the env vars
above). Deletes are idempotent, so running on several instances at once is
harmless; each class is batched and failure-isolated, and emits
`[:gamend, :retention, :pruned]` telemetry with its count.

# `child_spec`

Returns a specification to start this module under a supervisor.

See `Supervisor`.

# `prune_all`

```elixir
@spec prune_all() :: %{required(atom()) =&gt; non_neg_integer()}
```

Runs all configured pruning steps once. Returns a map of deleted row
counts per table.

# `run_now`

```elixir
@spec run_now() :: %{required(atom()) =&gt; non_neg_integer()}
```

Sweeps now instead of waiting for the next cycle, and records the run like a
scheduled one. Runs inside the GenServer so a manual run and the timer can
never overlap.

# `start_link`

# `status`

```elixir
@spec status() :: %{
  last_run_at: DateTime.t() | nil,
  duration_ms: non_neg_integer() | nil,
  results: %{required(atom()) =&gt; non_neg_integer()}
}
```

What the last sweep did, for the admin page. Falls back to "never run" when
the sweeper is not supervised (tests, or an instance with it disabled).

---

*Consult [api-reference.md](api-reference.md) for complete listing*
