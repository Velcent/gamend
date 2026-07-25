# July 2026

- [breaking] **Hostless lobbies are server-owned** — `PATCH /lobbies` (and `Lobbies.update_lobby_by_host/3`) now returns `403 not_host` for every player in a hostless (matchmaking) lobby, where any member could previously rewrite `metadata`, `max_users`, `password_hash`, `title` and the visibility flags. Server-side code uses `Lobbies.update_lobby/2`; the admin API and console are unchanged.
- [added] **Retention for every unbounded table** — lobbies nobody in them has been seen in for `RETENTION_ABANDONED_LOBBY_MINUTES` (never around a reconnect; ending a match is the game's job to clean up, not retention's), expired auth tokens, resolved invites, matchmaking tickets, plus opt-in tournaments and ledgers. Batched and failure-isolated per class, with a Data Retention card and "Run now" under Admin -> System and `GET`/`POST /api/v1/admin/retention`. Every window's default now applies in all environments; previously the whole config block was prod-only, so dev pruned nothing.
- [added] **Push notifications** — FCM + APNs-direct via Pigeon, routed per token; offline notification delivery.
- [added] **Push-token registry** — `/me/push-tokens`, admin page, retention pruning.
- [added] **Lobby state** — server-owned `state` + `state_changed_at`, a game-defined vocabulary via the `lobby_states/0` declaration (a state is a word and a description; core attaches no lifecycle meaning to any of them), `POST /lobbies/state` for hosts (hostless lobbies stay server-only), `state` filter, `state_changed` event and `before_lobby_state_change` / `after_lobby_state_changed` hooks.
- [added] **Quests / progression**.
- [breaking] **Achievements removed** — replaced by permanent quests categorised "achievement"; `/quests` supersedes the `/achievements` API, page and hooks.
- [added] **Economy**.
- [added] **Inventory**.
- [added] **Object storage** — with local-disk and S3/R2 backends; presigned avatar uploads.
- [added] Admin **Oban Web** dashboard at `/admin/oban` + jobs/storage.
- [added] **Lobby snapshots** — opt-in via `LOBBY_SNAPSHOTS_ENABLED`.
- [added] **Matchmaking** (ticket queue), admin page and hooks.
- [added] **Party matchmaking**, matched as one unit.
- [added] **Tournaments** (bracket system).
- [added] **User blacklist**, enforced in matchmaking and lobbies.
- [added] **Admin runtime page**: hooks, env vars, protobuf, channels, events, ER diagram, plugins, jobs.
- [added] Protobuf realtime format (opt-in).
- [changed] Realtime state events send full payloads.
- [removed] JSON delta encoding.
- [removed] Dead modules and client delta code.
- [added] **Unique usernames**.
- [breaking] **UUIDv7 string ids**.
- [added] JWT revocation.
- [added] Persistent IP bans.
- [added] Redis rate limiting.
- [added] Data retention pruning.
- [added] New plugin hooks.
- [added] Observability metrics.
- [security] Auth, payments, RPC hardening.
- [perf] Faster broadcasts and queries.
- [fixed] WebRTC RPC replies.

# April 2026

- [changed] Root host app restructure.
- [added] Browser theme color, sitemap.xml, robots.txt.
- [added] **Native HTTPS**
- [added] **Account Activation** beta mode.
- [added] Translations: Spanish, French, Romanian.
- [added] Roadmap page.
- [added] Security: RealIp, IP bans, OAuth CSRF, rate limiting, WebRTC - limits, security headers.
- [added] **OPENAPI_ENABLED** feature gate.

# March 2026

- [changed] Make Leaderboards accept label instead of user_id.
- [added] Initial version of **Achievements**.
- [added] Initial version of **Rate Limiting**.
- [changed] Self-hosted Inter font and eliminated all inline scripts.
- [added] Initial version of **WebSocket** updates.
- [added] Initial version of **WebRTC** updates.
- [changed] Admin interface with realtime connections view.

# Feb 2026

- [added] Initial version of **CHANGELOG** and **Blog**.
- [added] Initial version of **Groups**.
- [added] Initial version of **Parties**.
- [added] Initial version of **Notifications**.
- [added] Initial version of **Chat**.
