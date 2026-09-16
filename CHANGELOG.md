# September 2026

- [fixed] **`GAMEND_PAYMENTS_ENVIRONMENT=sandbox` selected production.** Every `:atom` setting cast through `String.to_existing_atom/1`, which only succeeds when some *other* compiled module happens to name that atom — so a perfectly valid choice that nothing else mentioned was rejected and silently replaced by the default. Three documented values could not be set at all: payments `sandbox` (real money, in a configuration that asked for the sandbox), push `apns_env=sandbox` (dev builds talking to the production APNs gateway) and mail `smtp_tls=if_available` (STARTTLS quietly off). Settings now declare their choices with `values:`, cast against that list, and the generated settings coverage test proves every documented value round-trips.
- [fixed] **APNs sandbox mode was unreachable a second way.** The endpoint config compared the `:apns_env` *atom* against the string `"sandbox"`, which is never true, so every host used the production gateway whatever it configured.
- [fixed] **A stale user id returned 500.** Submitting a leaderboard score, granting or spending currency, or granting or consuming an item for a user who does not exist raised `Ecto.ConstraintError`. The schemas did declare `foreign_key_constraint(:user_id)`, but SQLite — the default adapter — does not report *which* constraint an INSERT violated, so Ecto cannot match the declaration and raises instead of returning a changeset; the adapter's own docs say these changeset functions "may not work at all" there. The contexts check with `Gamend.Accounts.user_exists?/1` first and answer `{:error, :user_not_found}`, which the admin endpoints return as a 404. The constraints stay declared: they are what makes the row impossible, and on Postgres they still report.
- [changed] **One shape for validation errors.** A failed changeset now always answers `{"error": "validation_failed", "errors": {field: [message]}}`, with messages interpolated and translated. Seventeen of the forty-six hand-rolled call sites had left the raw `{msg, opts}` tuple in the payload, which `Jason` cannot encode — those endpoints answered **500** where their own OpenAPI operation documented a 422, and none of those branches had a test. Twenty-two others shipped the uninterpolated msgid, so a client read `"should be at most %{count} character(s)"` verbatim. **Breaking:** endpoints that previously returned `"invalid_data"`, or put the field map under `error`/`details`, now use the shape above. `mix gamend.api.lint` (R12) rejects a new hand-rolled copy.
- [changed] **The blog page moved into `gamend_web`**, joining the changelog and roadmap in `GamendWeb.ContentPages`. It had stayed a shim that looked up `GamendWeb.HostBlogLive` by name, so each host wrote the page itself — gamend and the starter carried byte-identical 237-line copies, each with a private reimplementation of `Gamend.Content.blog_posts_grouped/0`, and they had already drifted apart on date rendering. A host that wants a different page still routes its own module.
- [fixed] **The daily chat-report cap survives a restart.** It was enforced only by the in-memory rate limiter, so restarting a node cleared the counter. `Gamend.Chat.Reports.report_message/3` now also counts committed rows, which covers plugins calling it directly as well as the HTTP edge.
- [added] **Node-local moderation cache sizes** on the admin chat filter and chat mutes pages — the blocklist page flags when this node's in-memory matcher holds fewer words than the database, which is what a missed change broadcast looks like.
- [fixed] **A context could be asked for a million rows.** Seven contexts each had their own `paginate/2`, in four behaviours: three applied `:page_size` straight from the caller, two clamped to a hard-coded 1000 that ignored the configurable `max_page_size`. `GamendWeb.Pagination` had already fixed this at the controller layer, but a plugin calls the context directly. All of them window through `Gamend.Query` now, which clamps through `Gamend.Limits`; `mix gamend.api.lint` (R13) rejects a new copy. Chat messages and leaderboard listings clamp before their cache key, where an unclamped size also meant unbounded distinct cache entries.
- [changed] **One way to name a user.** `Gamend.Accounts.display_name/1` joins `display_label/1`, which had a single caller while four inline fallbacks were in use. A party invite from a player who had set no display name used to arrive from nobody (`display_name || ""`); three admin views fell through to the email and then the raw id. R14 rejects a new inline chain.
- [changed] Deduplication with no behaviour change: `Gamend.Payments.Params` (four copies of the JSON-shape helpers), `Gamend.Ledger` (the idempotent-transaction shape economy and inventory both implement), `GamendWeb.ControllerScope`, `GamendWeb.AdminLive.Shared`, `Gamend.Codegen`, and the two upload helpers into `GamendWeb.Uploads` — where the two copies had quietly disagreed on what a missing `content-type` means, now an explicit argument.
- [added] **`Gamend.Payments.Provider` and `GamendWeb.PageMeta.Provider` behaviours.** Both seams were swappable by config but had no declared contract, so a host discovered it by reading core and a misspelled callback failed silently at runtime. Also gives `provider_adapter/1` a catch-all: an unknown provider string raised `CaseClauseError`, which is a 500 for what is really "no such provider".
- [removed] Dead code: `GamendWeb.AdminLive.Users.Index` (an unrouted duplicate of `AdminLive.Users`), `GamendWeb.Plugs.Locale` (superseded by `Plugs.LocalePath`, and redirecting the opposite way), and eleven unreferenced functions. `ConnectionTracker.count_other_user_channels/1` went with the per-user registry key it was the only reader of — every user-channel join had been paying for a write nothing read since cluster-wide presence replaced it.

- [added] **Site search reads what you meant.** A name is matched on its first few letters, so "casa in spanish" searches for "casa" rather than for "casa in", in the thirty locales whose readers inflect the language name or write it with a suffix. A word nothing matched is retried as a typo, where two letters swapped count as one mistake rather than two. And a host can now answer queries too numerous to put in the index at all, through an optional `search/2` on its search provider — asked once the reader stops typing, with the languages or sections they most likely mean.
- [added] **Site search.** A magnifier in the header and Ctrl/⌘+K open a palette that searches the whole site. Out of the box it finds every navigation destination, including the ones a phone buries two taps deep in the hamburger menu; a host puts its own content in it with a `search_provider` module, and turns the feature off with `search_provider: false`. An entry whose href carries `{q}` is a search rather than a destination, which is how a query the palette cannot answer reaches the page that can.
- [added] `GamendWeb.Plugs.VisitorId` — a stable id for one browser session, signed in or not, for the things that must count something about a visitor who has no account (a free daily allowance, an A/B bucket). Not in the `:browser` pipeline, so a content host's crawlable pages keep answering without a `Set-Cookie`; `gamend_current_user_routes/2` takes `:extra_pipelines` to add it to a host's public scope.
- [fixed] **Navbar menus stay open.** The layout shell re-derived the theme, the navigation, the breadcrumbs and the unread count on every render, and every one of them counted as changed — so the navbar and footer re-rendered on *every* diff a LiveView sent, and the browser morphed an open `<details>` dropdown shut. A page with a clock in it, like a timed test, closed its own menu once a second. The derived values now only count as changed when an attr they are built from does, which also takes an unread-count query off every patch the site sends.
- [added] **`gamend_core` and `gamend_web` publish to Hex.** Both packages were held back by pigeon: its kadabra-to-mint rewrite sat unreleased for over a year, Hex refuses a package with a git dependency, and the released 2.0.1 would have dragged httpoison and hackney back in. pigeon 2.1.0 shipped, so the dependency points at Hex and CI publishes both packages alongside the SDK.
- [changed] **Push credential errors stop retrying.** pigeon 2.1.0 reports a rejected FCM service account as `:unauthenticated` and Apple's two token-key mismatches as their own responses, instead of folding them into the generic error every dispatcher retried until the attempt budget ran out.
- [fixed] **mint 1.10** — closes two denial-of-service advisories in the HTTP client that push and outbound requests run on.
- [fixed] **Typed text survives a reconnect.** A chat draft or message edit, the login email, the group create/edit forms and the admin live-lobby forms come back after the connection drops; which edit or panel is open now lives in the URL, since a form missing from the re-mounted page cannot be recovered.
- [fixed] **Admin quest and tournament filters** respond again — LiveView only sends change events from inputs inside a form.
- [added] **Offline notice.** Five seconds into a dropped connection every page says so, and clears itself on reconnect. It sets `<html data-connection="offline">` and fires `gs:connection`, so a page can lock input LiveView would silently drop. Replaces the two "Loading..." flashes, which fired together, and the heartbeat goes to 15 s so a dead network is noticed within half a minute.
- [fixed] **An edit on an older chat message** survives a reconnect too: the pages of older messages loaded are in the URL (`page`), and an edit whose message is still not loaded pages back until it is.
- [fixed] **Opening a chat no longer crashes** when it is already read up to its last message — the forward-only read cursor updated no row, which Ecto raised as a stale entry.

# August 2026

- [added] **`mix host.proto.check`** — checks every registered protobuf schema against the JSON actually stored under it, and reports which values fall back to JSON and why. A schema missing one field is not an error anywhere: it simply never encodes, so the optimisation looks shipped and is inert. Covers KV entry values and user/lobby/group/party metadata, takes a captured payload with `--json FILE --message Mod`, and exits 1 so it can gate CI. Also lists what is *not* typed — the KV keys, entities and hooks still going out as JSON.
- [fixed] **Godot binding generation fails loudly.** Godot's headless script runner exits 0 whether or not the script succeeded, so `mix host.proto.gen` reported success while godobuf had written nothing — one `reserved` field it could not parse froze a game's Godot bindings for weeks while Elixir and JS kept regenerating fine. `reserved` is now stripped from godobuf's copy of the proto (it generates no code, and protoc keeps enforcing it), and a run that writes nothing is an error.

- [fixed] **Server scripting works in a release.** Plugins were loaded at runtime but a release boots in embedded mode, which refuses to load them — every plugin failed with `{:error, :embedded}` while the startup banner still counted them as loaded.
- [added] **Brotli for static assets**, alongside the gzip files the digest already wrote.

- [added] **Hero tour video** — a click-to-play walkthrough of the admin panel, quests, store, matchmaking and server hooks; `scripts/screenshots/record_tour.js` re-records it.
- [added] **Image lightbox** — clicking a home-page screenshot opens it full-size (ported from the Polyglot Pirates host).
- [changed] **Home page shows the product** — real screenshots (light and dark) of the admin dashboard, quests, groups, login, store, matchmaking, analytics, runtime hooks and economy pages instead of icons; the hero states that Gamend is backend, player website and admin panel in one. `scripts/screenshots/` recaptures them.
- [added] **News dropdown** in the navigation — blog, changelog, roadmap and guides.
- [changed] **Home page reflects the current feature set** — quests instead of achievements, GDScript/Gleam scripting, and new economy/storage and analytics/observability sections.
- [added] **Friends admin page**
- [added] **Retention admin page**
- [added] **16 new guides**
- [added] **Plugins can be written in GDScript**
- [added] **Plugins can be written in Gleam**
- [added] **Client logs**
- [added] **Logs page filters by client session and user**, and separates client entries from the server's own tail.
- [fixed] **Logins survive a busy database** — the analytics day-marker and daily counters drop a failed write instead of failing the request they ride on.
- [fixed] **Repeat quests** re-arm right away again, instead of once an hour.
- [changed] **Matchmaking is near-instant** — a join sweeps immediately instead of waiting for the tick.
- [added] **Performance guide** — measured throughput, capacity and database choice.
- [added] **Socket buffer size** is configurable — the largest per-connection memory cost.
- [changed] **Logins return sooner** — the last-seen and activity writes moved off the request path.
- [fixed] **Concurrent signups** no longer queue behind each other on SQLite.
- [added] **Load-test harness** — per-feature benchmarks and a capacity journey, in `stress/`.
- [fixed] **Benchmark RPCs** measured an error path, not a locked write.
- [fixed] **Realtime events arrived twice**
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
