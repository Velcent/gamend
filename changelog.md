# August 2026

- [added] **A host can hide quests per viewer** — `config :gamend_core, :quest_visibility_filter, {Module, :fun}` is called with `(user_id | nil, quests)` on every per-user listing, count and category list (and the signed-out catalog with `nil`); progress is not filtered, so a quest a player cannot see yet still advances. For premium-only or unlock-gated quests.
- [added] **`user_title/1`** — the line under a name (a rank, a title) read from a metadata path the host names in `config :gamend_web, :user_title_meta_path`; used on leaderboards, tournaments and the nav dropdown.
- [changed] **Pagination hides itself** when a list fits on one page — no more disabled Prev/Next and a "1 / 1" counter under every short list. The page-size selector stays only when a smaller size would actually split the list.
- [fixed] **Realtime events arrived twice**
- [fixed] **A LiveView could stack PubSub subscriptions** — `GroupsLive` subscribed
  to the selected group on every `handle_params/3`, and `kv:subscribe` registered
  again each time a client asked for the same key.
- [fixed] **Scroll position** is restored without showing the top of the page first.
- [fixed] **Language flags** are cached, so they no longer pop in after the text.
- [fixed] **Deleting an account deletes its avatar** from storage.
- [changed] **One heading scale** across the shipped pages.
- [added] **Player analytics** — D1 / D7 / D30
- [fixed] **Accessible theme colors**
- [added] **RULES.md** — design & accessibility rules.
- [added] **Grouped** quests.
- [added] **Repeat** quest reset type.

# July 2026

- [breaking] **Renamed to Gamend.**
- [added] **Captcha** on the register and magic-link forms
- [added] **Chat moderation** — word filter, report queue, mutes
- [breaking] **One theme file**
- [added] **Translation pipeline**
- [added] All **30 locales fully translated** (machine-translated, pending review).
- [added] **Icons everywhere** — `icon_url` on notifications, tournaments, groups and leaderboards;
- [added] **Quest chains** are browsable; a chain lists as one quest.
- [breaking] **API paths use underscores**
- [breaking] One **pagination meta** shape on every list response.
- [added] **API conventions** spec + `mix gamend.api.lint` in precommit and CI.
- [added] **Settings**: one declared config surface.
- [changed] **Guides are markdown files.** `/docs/setup`
- [changed] **Times are shown in the reader's timezone.**
- [added] Retention for every unbounded table.
- [added] **Ready checks**
- [added] **Push notifications**
- [added] **Lobby state**
- [added] **Quests / progression**.
- [breaking] **Achievements removed** — replaced by permanent quests
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
