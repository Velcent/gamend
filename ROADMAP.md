# Gamend Roadmap & Architecture

Living document for planned work. Each phase lists what ships and, where it's
being built, the concrete architecture and the full CONTRIBUTING checklist it
must satisfy. Keep this in sync as phases land.

---

## Roadmap at a glance

Two structural bets drive the ordering: **Phase 0 is the keystone** (push
fan-out, webhooks and scheduled quests all ride on the job queue; cloud saves
ride on object storage), and **economy → quests → achievements are one reward
spine**, designed together rather than bolted on.

| Phase | Item | Value | Effort | Depends on |
|:-----:|------|:-----:|:------:|-----------|
| **0** | Background jobs (Oban) — queue, `Jobs` API, scheduled actions, dashboard | High | M | — |
| **0** | Object storage — disk ↔ S3/R2, presigned uploads | High | M | — |
| **1** | Push — server delivery + push-token storage | High | M | Jobs |
| **1** | Push — Godot client (Android → iOS) | High | M–L | — |
| **1** | Chat moderation — word filter, report queue, mute | Med–High | M | — |
| **2** | Economy/inventory — generic currencies, atomic wallet, ledger | High | L | — |
| **2** | Cloud saves — versioned save-slots | Med | M | Object storage |
| **2** | Skill matchmaking — rating + widening bands + hook override | Med–High | M | matchmaker |
| **2** | Ready check — one primitive, bound to matchmaking accept + lobby ready | Med–High | M | matchmaker, lobby state |
| **3** | Quests/progression — generalizes achievements, pays into economy | High | L | Economy + Jobs |
| **3** | Webhooks (signed, retried) + remote config | Med | S–M | Jobs |
| **3** | Event-tracking API → Postgres `events` table | Med | S | — |
| **4** | Locking that holds on SQLite — `Lock.serialize/3` is a no-op there | High | S | — |
| **4** | Lobby session — one serialized process per lobby | High | M | locking |
| **4** | Server time + state revision + action idempotency | Med–High | M | lobby session |
| **4** | Disconnect grace + state-aware lobby reaping | Med–High | S–M | jobs, lobby state |
| **4** | Regenerating currencies (lives / energy) | Med | S–M | economy |
| **4** | KV prefix queries + streaming | Med | S | — |
| **4** | Discord notifications | Med | S | jobs |
| Later | ClickHouse / PostHog analytics | Med | L (ops) | Event API |
| Defer | Unity / Unreal SDKs | Med | XL | — |

### Deferred / rejected, with reasons

- **More Ecto SQL adapters (MySQL, SQL Server): no.** The two adapters already
  cover the only two deployment modes that matter (embedded single-binary
  SQLite, scale-out Postgres). A third multiplies the hand-maintained
  cross-dialect SQL surface (`escape_like`, `ESCAPE '\'`, `lower(coalesce())`,
  ~34 raw `fragment/2` sites) for no user demand. Postgres-wire-compatible
  scale-out DBs (CockroachDB, YugabyteDB, Neon, Supabase, Timescale) already
  work through `postgrex` — verify + document instead of adapting.
- **ClickHouse now: no.** It's a whole new database deployment. The real work
  is the *event-capture pipeline* (Phase 3); store events in Postgres first and
  only graduate to ClickHouse/PostHog when volume forces it. Prometheus (PromEx)
  can't substitute — it's aggregate ops metrics, not per-player analytics.
- **Unity/Unreal SDKs: defer.** REST clients generate cheaply from the OpenAPI
  spec, but the realtime layer (WebSocket/WebRTC + protobuf) is hand-written per
  SDK — that's the real cost. Revisit on demonstrated demand.

---

## Phase 0 — Background jobs & object storage

Goal: replace Quantum with a durable job queue, and add a storage abstraction
that works on local disk and any S3-compatible backend. Both are foundations
later phases build on, so the abstractions matter more than the first consumer.

### Why (net-new capability, not just internal reliability)

Today the only async primitives are `GameServer.Async` (fire-and-forget, best
effort, lost on crash) and `GameServer.Schedule` (Quantum cron, in-memory, no
retries, no one-off/delayed jobs, lost on restart). A durable queue unlocks
API/hook surface that cannot be built safely on either:

1. **Delayed / scheduled actions** — "grant daily reward in 24h", "trial expires
   in 7 days", "tournament-starts-in-1h reminder", "energy refills at T+30m".
2. **A jobs API for plugin authors** — retryable/delayed background work from
   inside custom hooks, impossible for them today.
3. **Reliable fan-out** — push to a whole group/party/all-users, with backoff.
4. **Reliable webhooks** (Phase 3) and **durable receipt validation** — survive
   restarts and transient provider errors.

### Licensing note

Oban **core** (Apache-2.0) and **Oban Web** dashboard (Apache-2.0, OSS since
v2.11) are free. Only **Oban Pro** (workflows, `DynamicCron`, chunks) is paid —
**we do not need it.** Dynamic runtime cron (the current `Schedule` behaviour)
is a Pro feature, so we reimplement a thin dynamic layer on free Oban (below).

### Engines: one switch, mirroring the DB adapter

Oban runs on both our DBs: `Oban.Engines.Basic` (Postgres) and
`Oban.Engines.Lite` (SQLite). Select it in the **same place and the same way**
as the Repo adapter (`config/host_config.exs` compile-time `default_adapter`,
overridable at runtime in `config/host_runtime.exs`):

```elixir
# host_config.exs — next to the existing Repo adapter block
oban_engine =
  if default_adapter == Ecto.Adapters.Postgres,
    do: Oban.Engines.Basic,
    else: Oban.Engines.Lite

config :game_server_core, Oban,
  repo: GameServer.Repo,
  engine: oban_engine,
  queues: [default: 10, hooks: 20, mailers: 5, storage: 5, webhooks: 10],
  plugins: [
    {Oban.Plugins.Pruner, max_age: 60 * 60 * 24 * 7},
    {Oban.Plugins.Cron, crontab: [{"* * * * *", GameServer.Schedule.TickWorker}]}
  ]
```

Test env uses `testing: :manual` (Oban's `Oban.Engines.Inline`-style manual
mode) so jobs don't run unless drained, matching the existing Sandbox setup.

### Migrations (both adapters)

Oban ships `Oban.Migration` which supports Basic (Postgres) and Lite (SQLite).
One migration in `apps/game_server_core/priv/repo/migrations/`:

```elixir
def up,   do: Oban.Migration.up(version: 12)
def down, do: Oban.Migration.down(version: 1)
```

Verify it applies cleanly under `GAMEND_DB_ADAPTER=postgres` **and** default
SQLite (CONTRIBUTING §Data model). A **separate** migration drops the now-dead
`schedule_locks` table — dropping a table is safe on both adapters.

### `GameServer.Jobs` — the new plugin-facing API

Thin wrapper over Oban so plugins never import Oban directly (keeps us free to
swap internals, and lets the SDK stub it):

```elixir
GameServer.Jobs.enqueue(worker, args, opts \\ [])   # one-off
GameServer.Jobs.enqueue_in(seconds, worker, args)   # delayed
GameServer.Jobs.enqueue_hook(hook_fn, args, opts)   # run a hook async/retryably
GameServer.Jobs.cancel(job_id)
```

- Backed by a generic `GameServer.Jobs.HookWorker` (an `Oban.Worker`) that calls
  `GameServer.Hooks.invoke(hook_fn, [args])`, inheriting retries/backoff.
- `opts` pass through Oban's `:queue`, `:schedule_in`, `:max_attempts`,
  `:unique` (dedupe window).
- **RPC safety:** any hook name reachable via `enqueue_hook` is registered in the
  same protected-callbacks set that `Schedule` already maintains, so clients
  can't invoke it over RPC (CONTRIBUTING §Hooks step 2 pattern).

### `GameServer.Schedule` reworked onto Oban (Quantum removed)

**The public API is unchanged** — `cron/3`, `every_minutes/2`, `hourly/2`,
`daily/2`, `weekly/2`, `cancel/1`, `list/0` — so existing plugins that call it in
`after_startup` keep working. Only the engine underneath changes:

- Registration still records `{name, cron_expr, hook_fn}` in the existing
  `:schedule_callbacks` ETS table (populated identically on every node from
  `after_startup`, which is deterministic plugin code).
- A single static Oban `Cron` entry runs **`GameServer.Schedule.TickWorker`
  every minute**. Oban's Cron plugin elects a leader and inserts the tick on one
  node only → exactly one tick per minute cluster-wide.
- The tick iterates the registry and, for each schedule whose cron matches the
  current minute (`Crontab.Scheduler`), enqueues a **`unique`** `HookWorker` job
  keyed on `job_name + minute-bucket`. **Oban uniqueness replaces the
  `schedule_locks` table** for distributed dedup — delete the table + `Lock`
  module.
- `list/0` reads the registry; `cancel/1` removes from it.

Removed: `quantum` dep, `GameServer.Schedule.Scheduler`, `GameServer.Schedule.Lock`,
`schedule_locks` migration/table, the `Crontab.CronExpression.Composer` display
path (replaced by the stored cron string).

### Supervision & dashboard

- `apps/game_server_web/lib/game_server_web/host_supervision.ex`: replace the
  `GameServer.Schedule.Scheduler` child with `{Oban, Application.fetch_env!(:game_server_core, Oban)}`,
  placed after `Repo` (Oban needs the repo) and before the periodic workers.
  Keep `GameServer.Schedule.start_link()` in `init_runtime/0` (still owns the
  ETS registry).
- Mount **Oban Web** at `/admin/oban` behind the existing admin auth pipeline
  (`Oban.Web.Router`), *or* render a native LiveView from `Oban` queue/job
  queries if we want it inside the existing admin shell. Default: native card
  on `/admin` (counts by state + scheduled crons) linking out to Oban Web for
  depth.

### `runtime_introspection.ex`

`scheduled_jobs/0` currently reads `Quantum` (`Scheduler.jobs()`). Repoint it at
the `Schedule` registry, and add an Oban section: counts per queue and per state
(available / scheduled / executing / retryable / discarded). This feeds the
admin runtime "jobs" page that already exists.

---

### Object storage

A storage abstraction mirroring the DB-adapter pattern: **local disk in dev, any
S3-compatible backend in prod** (AWS S3, Cloudflare R2, Backblaze B2, MinIO,
DigitalOcean Spaces — same code, different endpoint).

**Behaviour** `GameServer.Storage.Adapter`:

```elixir
@callback put(key :: String.t(), data :: iodata(), opts :: keyword()) :: {:ok, String.t()} | {:error, term()}
@callback get(key :: String.t()) :: {:ok, binary()} | {:error, term()}
@callback delete(key :: String.t()) :: :ok | {:error, term()}
@callback url(key :: String.t(), opts :: keyword()) :: String.t()            # public/read URL
@callback presigned_upload(key :: String.t(), opts :: keyword()) :: {:ok, map()} | {:error, term()}
```

- **`GameServer.Storage`** — facade dispatching to the configured adapter, plus
  shared concerns: key namespacing (`avatars/<user_id>/...`), content-type +
  size validation (caps in `GameServer.Limits` → `LIMIT_*`), and a deterministic
  key scheme.
- **`GameServer.Storage.Local`** — writes under `GAMEND_STORAGE_DIR`
  (default `priv/storage`, git-ignored). `url/2` points at a Plug route
  `GET /storage/*key`; `presigned_upload/2` returns a signed (HMAC + expiry)
  URL to a local `PUT /storage/upload` endpoint so the client-side flow is
  identical to S3.
- **`GameServer.Storage.S3`** — `ex_aws` + `ex_aws_s3`. `presigned_upload/2`
  uses `ExAws.S3.presigned_url(:put, ...)`; `url/2` returns the public or signed
  GET URL. Endpoint/region/bucket from config so R2/MinIO work unchanged.

**Config** (`host_config.exs` compile default + `host_runtime.exs` runtime),
selected like the DB adapter:

```
GAMEND_STORAGE_ADAPTER=local|s3          # default local
GAMEND_STORAGE_DIR=priv/storage
GAMEND_STORAGE_PUBLIC_URL=               # CDN / base URL override
GAMEND_STORAGE_BUCKET=
GAMEND_STORAGE_REGION=auto
GAMEND_STORAGE_ENDPOINT=              # e.g. https://<acct>.r2.cloudflarestorage.com
GAMEND_STORAGE_ACCESS_KEY_ID=
GAMEND_STORAGE_SECRET_ACCESS_KEY=
STORAGE_MAX_UPLOAD_BYTES=5242880
```

**Upload flow (client-agnostic, same for Godot/JS):**
1. Client asks `POST /me/avatar/upload-url` → server validates size/type,
   returns `{url, method, headers, key}` from `presigned_upload/2`.
2. Client uploads bytes directly to `url` (S3/R2 or the local endpoint).
3. Client `POST /me/avatar {key}` → server verifies the object exists and
   records it on the user.

**First consumer: user avatars.** Today `profile_url` only ever holds an OAuth
provider URL (Discord/Google). Add uploaded-avatar support behind Storage; the
provider-URL path stays as the fallback. (Server-authoritative per
CONTRIBUTING §Web — the mutation is a validated endpoint, not a raw client
write.)

---

### "Update everywhere we mention features" — concrete file list

Per CONTRIBUTING §Finish, plus the user's ask to reframe cron→jobs everywhere:

- **README.md** — Features list: add **Background jobs** and **Object storage /
  uploads**; the Key-Value/Server-scripting bullets mention durable scheduled
  jobs.
- **CHANGELOG.md** — `[added]` Background jobs (Oban) · `[added]` Object storage
  (local + S3/R2) · `[changed]` Schedule now durable/retryable · `[breaking]`
  removed Quantum + `schedule_locks`.
- **.env.example** — Oban queue sizes/concurrency, all `STORAGE_*` vars,
  `STORAGE_MAX_UPLOAD_BYTES`.
- **host_public_docs/** (registered in `host_public_docs.ex`):
  - Server-scripting page — `Jobs` API + note that `Schedule` is now durable.
  - New **Uploads / storage** page — presigned flow, local vs S3/R2.
  - Data Schema page — add `oban_jobs`, remove `schedule_locks`.
- **api_spec.ex** — feature list + avatar-upload endpoints (+ realtime events if
  any).
- **SDK** — `sdk/lib/game_server/jobs.ex` (+ storage stubs), add to
  `@sdk_modules`, `mix gen.sdk`; struct stubs + placeholder rules per
  CONTRIBUTING §SDK.
- **Admin** — jobs page (native card + Oban Web link), storage status card,
  `/admin` stat cards, routes, `admin_pages_render_test`, admin API parity.
- **runtime_introspection.ex** — repoint `scheduled_jobs`, add Oban stats.
- **schedule.ex moduledoc / host_supervision comment / admin config copy** —
  drop "Quantum" wording; describe durable jobs.
- **.github/copilot-instructions.md** — mention jobs + storage in the feature
  overview.
- **i18n** — `gettext.extract` + `merge`, translate all 30 locales, clear
  fuzzies (CONTRIBUTING §i18n).
- **mix demo.seed** — enqueue sample jobs / seed a sample uploaded avatar so the
  admin pages show data at volume.

### Definition of done (CONTRIBUTING)

- [ ] Migrations apply on SQLite **and** `GAMEND_DB_ADAPTER=postgres`.
- [ ] `GameServer.Jobs` + reworked `Schedule` + `Storage` with pagination on any
      list endpoints and `Limits` caps enforced in changesets.
- [ ] Hooks: enqueued-hook callbacks protected from RPC; SDK mirrors any new
      callbacks (all six places).
- [ ] Admin page + `/admin` card + route + nav + `admin_pages_render_test`;
      admin API parity.
- [ ] Docs pages, `.env.example`, `CHANGELOG`, README, `api_spec.ex`.
- [ ] Tests: context + controller + admin + LiveView, on both adapters. Boot and
      actually run a job, a scheduled tick, and an upload.
- [ ] `mix format`, `mix credo --strict`, full `mix test` green; `mix gen.sdk`
      clean; example plugin compiles warning-free.

---

## Design specs (Phases 1–4)

Phase 0 is specced inline above (shipped). Every planned item in Phases 1–4 has
a full design spec under [docs/specs/](docs/specs/) — see the
[index](docs/specs/README.md). Each carries goal, architecture grounded in the
current codebase, and the CONTRIBUTING checklist.

**Phase 1**
- [Push — server delivery + token storage](docs/specs/push.md) — `push_tokens` +
  `GameServer.Push` fan-out on the Oban `push` queue; FCM + APNs-direct behind
  one behaviour, routed per token, delivered via **Pigeon 2**.
- [Push — Godot client](docs/specs/push-godot-client.md) — Android (FCM) then iOS
  (native APNs) behind one `GamendPush.gd`, registering to `/me/push-tokens`.
- [Chat moderation](docs/specs/chat-moderation.md) — word filter + report queue +
  mute, enforced in the existing `before_chat_message` pipeline.

**Phase 2**
- [Economy / inventory](docs/specs/economy-inventory.md) — generic currencies,
  atomic wallet, idempotent ledger, inventory (reintroduces the removed
  `wallet_ledger`, decoupled from payments).
- [Cloud saves](docs/specs/cloud-saves.md) — versioned save-slots on Object
  storage with lock-free optimistic conflict detection.
- [Skill matchmaking](docs/specs/skill-matchmaking.md) — rating + wait-widening
  bands in the existing pure matcher; override hook intact.
- [Ready check](docs/specs/ready-check.md) — one `ready_checks` primitive with
  two bindings: matchmaking accept (opt-in) and lobby ready-up.

**Phase 3**
- [Quests / progression](docs/specs/quests-progression.md) — one event-driven
  engine; achievements fold in; rewards pay into the economy exactly-once.
- [Webhooks + remote config](docs/specs/webhooks-remote-config.md) — signed,
  retried webhooks on the Oban `webhooks` queue; client-read-only live config.
- [Event-tracking API](docs/specs/event-tracking.md) — batched, enriched,
  auto-pruned `events` capture in Postgres.

**Phase 4 — plugin-facing foundations**

Where Phases 1–3 added features, Phase 4 adds the primitives a game needs to
build its own. Every item comes from reading the `gamend_polyglot` game and
asking what it had to write itself, or route around, because core offered
nothing.

- [Locking](docs/specs/locking.md) — `Lock.serialize/3` is a **no-op on
  SQLite**, so every plugin read-modify-write is unprotected on the default
  adapter. Polyglot's top code-review finding was a double-spend caused by
  exactly this; it now uses its own `:global.trans` lock instead of core's.
- [Lobby session](docs/specs/lobby-session.md) — one supervised, cluster-unique
  process per lobby, holding no authoritative state, that games run mutations
  inside. Replaces the per-game `BoatGameServer` every action title writes.
- [Netcode sync](docs/specs/netcode-sync.md) — `server_now`, a monotonic
  `lobbies.revision` with optimistic updates, and `seq`-deduped actions. Core
  supplies the inputs; latency compensation stays in the game.
- [Disconnect grace](docs/specs/disconnect-grace.md) — `after_user_absent/1` on
  a durable timer, plus `prune_after_minutes`/`terminal` on declared lobby
  states, which `Hooks.Declarations` already documents and nothing reads.
- [Regenerating currencies](docs/specs/resource-regen.md) — lives/energy as a
  declared `%{amount, interval, cap}` on a wallet, folded from a timestamp.
- [KV prefix streaming](docs/specs/kv-prefix-streaming.md) — indexed prefixes
  and a keyset cursor, replacing substring `LIKE` behind offset paging.
- [Discord notifications](docs/specs/discord-notifications.md) — the concrete
  slice of the parked webhooks spec, redacted by construction (polyglot's
  hand-rolled version leaked player emails).
