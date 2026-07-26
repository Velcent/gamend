# July 2026

- [breaking] **The theme is one file, translated through gettext.**
  `theme/config.json` replaces the 30 per-locale copies, and its text is
  translated via the `theme` gettext domain. Two thirds of each copy was
  structure rather than text, and they drifted — a `theme_color` added to
  English never reached the other 29. Configuration (colours, hrefs, icons,
  layout) is now structurally untranslatable. Extract with
  `mix gamend.theme.extract`; migrate existing per-locale files with
  `mix gamend.theme.migrate_locales`. `modules/example_config*.json` is gone —
  nothing loaded it.
- [breaking] **Quest and leaderboard translations are no longer stored in the
  database.** The per-locale `metadata["titles"][locale]` /
  `["descriptions"][locale]` copies, their admin editor and
  `Quest.localized_title/2` (plus the `Leaderboard` equivalents) are removed —
  the same duplicate-store problem the theme had. A row now holds only its
  source text and gettext translates it at render.
  `mix gamend.content.migrate_metadata` lifts existing per-locale metadata into
  `content.po` (`--dry-run` to preview, `--prune` to clear the dead keys).
- [added] **Quest, leaderboard and tournament text is translatable.**
  `mix gamend.content.extract` reads the titles and descriptions from the
  database into a `content` domain, so plugin-defined *and* admin-created rows
  are covered; `GameServerWeb.ContentText` translates them per viewer. Admin
  pages deliberately keep showing the stored source string.
- [added] **All 30 locales are fully translated** (352 strings each, up from
  266) — machine-translated through the CSV round-trip and awaiting native
  review.
- [changed] `mix gettext.export_csv` / `import_csv` cover both gettext trees
  and every domain; the `_config` pseudo-domain and `--config` flag are gone,
  since theme text is now a normal PO domain.
- [added] **Quest chains are browsable** — clicking a chained quest shows every
  tier, including locked ones ahead.
- [breaking] **A chain lists as one quest.** `list_user_quests` (and
  `GET /quests/me`) return a single entry per chain — the earliest tier not yet
  claimed; once all are claimed, the final tier. Previously a finished tier and
  its unlocked successor listed side by side.
- [breaking] **String fields in API responses are never `null`** — an unset
  value serializes as `""` (Godot clients choke on `null` where a string is
  expected). Applies to REST, realtime payloads and struct-encoded responses
  alike: `icon_url`, `description`, `recur`, `prerequisite_quest_key`,
  notification `sender_id`, and friends. Datetimes/numbers keep `null` where
  absence is semantic.
- [added] `icon_url` on **notifications, tournaments, groups and leaderboards**
  (quests already had it). Group admins upload via `POST /groups/:id/icon/upload_url` +
  `POST /groups/:id/icon`; tournaments and leaderboards take a URL in admin.
  Entities without an icon fall back to one shared default per type, from the
  typed icon set in `GameServerWeb.Icons`.
- [breaking] **API route paths use underscores throughout.** The API mixed the
  two styles (`/me/push-tokens` next to `/groups/:id/join_requests`); every
  hyphenated path is renamed, with no redirects. Notably `/users/log-in`,
  `/users/log-out`, `/users/update-password`,
  `/users/settings/confirm-email/:token`, `/me/push-tokens`,
  `/me/friend-requests`, `/me/avatar/upload-url`, `/data-deletion`,
  `/tournaments/:id/my-match`, `/economy/grant-item`, `/economy/consume-item`
  and the `/admin/rate-limiting` and `/admin/lobby-snapshots` pages. **Update
  any external registration of `/data-deletion`** (Meta/Facebook app settings),
  and note that confirmation links already emailed under the old path will 404.
- [added] **The typed icon set is served as SVG** at `GET /icons/<name>.svg`
  (324 heroicons), so an entity's `icon_url` can point at an icon the server
  already ships instead of artwork someone has to host. The web UI recognises
  its own URLs and inlines them, so `currentColor` follows the reader's theme —
  in an `<img>` a heroicon renders black and disappears on the dark theme.
- [fixed] SDK structs had drifted from core: `Group`, `Tournament` and
  `Leaderboard` were missing `icon_url`, and `ReadyChecks.Check` /
  `Tournaments.Match` still carried `deadline` after core renamed it to
  `deadline_at` — which broke `mix compile` for any plugin. `mix gen.sdk` now
  also emits a non-nil placeholder for `Group.t() | nil` lookups.
- [added] **Two-step icon upload for tournaments, leaderboards and quests**
  (admins), matching the flow groups and avatars already had:
  `POST .../icon/upload_url` returns a presigned ticket, the client PUTs the
  image straight to storage, `POST .../icon` confirms the key. The mechanism
  now lives in one place, `GameServerWeb.Uploads`, which also confines a
  client-supplied key to its own entity's prefix.
- [fixed] Admin `GET`/`PATCH /api/v1/admin/tournaments` documented `icon_url`
  in its OpenAPI schema but never returned it.
- [fixed] **Uploaded icons are cached like avatars.** `icons/` now carries the
  same immutable one-year `Cache-Control` as `avatars/` — every icon key is
  content-unique (`Storage.build_key/3`), so revalidating one on each page load
  was pure waste.
- [added] **API conventions are enforced.** `docs/specs/api-conventions.md`
  writes down the naming and serialization rules (identifiers, names, time,
  lifecycle, the null policy, response shapes, paths); `mix gamend.api.lint`
  checks six of them mechanically in precommit and CI. It found six schemas
  encoding `null` through `@derive Jason.Encoder`, three OpenAPI schemas
  contradicting their serializers, and eleven fields whose names hid their
  unit or type.
- [breaking] **`deadline` is `deadline_at`** on ready checks and tournament
  matches — instants are `*_at` everywhere else.
- [breaking] **Duration settings name their unit.** `GAMEND_DB_POOL_TIMEOUT`,
  `_QUEUE_INTERVAL`, `_QUERY_TIMEOUT`, `_SQLITE_BUSY_TIMEOUT` and the five
  `GAMEND_RATELIMIT_*_WINDOW` variables gain an `_MS` suffix. All were
  milliseconds; none said so.
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
