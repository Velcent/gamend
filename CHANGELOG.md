# September 2026

- [added] **Email and password registration for game clients.** `POST /api/v1/register` takes `email`, `password` and an optional `username`, creates the account and answers `201` with the same tokens as login. Registration was browser-only, so a game had device login and nothing to sign a player up with an email. It sends no email: the browser form's captcha exists because sign-up mails an address the caller chose, and this path mails nothing. The auth rate limit applies, first-user-is-admin and `GAMEND_AUTH_REQUIRE_ACTIVATION` hold as for every sign-up, a taken email or username is `409` and a closed door is `403 registration_closed`. `GAMEND_AUTH_API_REGISTRATION_ENABLED=false` turns it off.
- [fixed] **`DELETE /api/v1/me` documents its body.** An account with a password has to send `current_password`, and the operation declared no body, so generated clients could not delete such an account. The OpenAPI operation now carries the optional `current_password`.
- [fixed] **Chat messages never created a notification.** `chat_friend`, `chat_group`, `chat_lobby` and `chat_party` were missing from `Gamend.Notifications.Types`, so every chat notification was rejected at write, inside a background task that dropped the error. They are registered now, with `quest_completed`, which only got through because it was written with atom keys the type check did not read; the check reads both. A chat notification that fails to write is now logged. Tests cover each chat kind and the quest notification.
- [changed] **Social sign-in buttons name the provider.** "Log in with Discord", "Register with Google" in place of the same "Log in" five times. `oauth_buttons` takes `action={:login | :register}` instead of `label`; the grid is one column below `lg`, where the form is `max-w-sm` and a named label does not fit half of it. Two new strings, translated in all 28 catalogs.
- [changed] **The log in page has one submit button.** "Remember me" is a checkbox, on by default, in place of the second "Log in and remember me" button, and a "Forgot password?" link points at the magic link form: a magic link logs the user in and the Account page sets a new password without the old one. Three new strings, translated in all 29 catalogs.
- [added] **Theme `contact_email`.** The privacy, data deletion and terms pages give it as a mailto link for access, correction and deletion requests. Without it they still say "support channels", which app-store review and a data-protection request cannot act on.
- [changed] **Lobby responses have names in the OpenAPI document.** `Lobby`, `LobbyPage`, `LobbyResponse`, `LobbyStatsResponse`, `PageMeta` and `UserBrief` replace the inline schemas, and every lobby error is `ErrorResponse`, so generated clients get `LobbyPage` instead of `ListLobbies200Response`. The inline schema had drifted from the serializer: it lacked `state`, `state_changed_at` and the members' `is_activated`, which a typed client drops, and typed `host_id` as a UUID though a hostless lobby sends `""`. `GamendWeb.ResponseContract` now checks every lobby response in the test suite against its schema, undeclared keys included. Nothing changes on the wire; the generated class names change at the next SDK release. First slice of `docs/specs/named-api-schemas.md`.
- [changed] **User, sign-in and friend responses have names too.** `CurrentUser`, `PublicUser`, `Session`, `OAuthResult`, `Friend`, `FriendRequest`, `ProfileUpdate`, `UploadTicket` and their pages replace 26 generated classes such as `Login200ResponseData` and `ListFriends200ResponseDataInner`. The document had drifted here too: every user row lacked `is_activated`, `lobby_id` and `party_id` were typed as UUIDs though they are `""` outside a lobby or party, device login was documented with the OAuth polling payload, and the profile, avatar and upload-ticket answers were documented as empty objects. Two fixes on the wire: a friend request whose user was not loaded now sends that user's whole row (adding `profile_url` and `is_activated`), and an OAuth sign-up that fails validation answers 400 with `errors` instead of a 500 from an unencodable changeset.
- [fixed] **17 authenticated endpoints answered 401 to the JavaScript SDK.** A generated client sends the bearer token only where the OpenAPI document declares it, and `get_lobby`, every chat endpoint, matchmaking, tournament join/leave/my-match, `my_quests`, `claim_quest` and `get_my_record` declared nothing usable: nine no `security` at all, eight a `"bearer"` scheme the document does not define. The Godot SDK sends the token everywhere, which hid it. The seven optional-auth endpoints (a group, its members, quests, a tournament, client logs) now declare the token as optional, so a signed-in client sees what it is entitled to instead of the anonymous view. `GamendWeb.ApiSecurityTest` checks every route's pipeline against its document entry.
- [breaking] **One response shape for users, sign-in, friends, lobbies, groups, parties, chat, notifications and push.** Every answer is now `{"data": ...}`, a page `{"data": [...], "meta": ...}`, `{"ok": true}`, or an error `{"error": "code", "message": "..."}` — nothing else at the top level. Bare resources moved under `data` (a create answers 201 with what it made); `{}` became `{"ok": true}`; a profile change answers the whole current user instead of `{ok, id, ...}`; the OAuth session poll answers `{data: {status, message, result}}`; unmuting answers `{data: {deleted}}`; `get_lobby` puts members and spectator count inside the lobby; party invitation lists are pages; `group_name` is `group_title`, in REST, realtime and new notification metadata. Error codes are always `snake_case` (`not_authenticated`, `invalid_credentials`, `missing_param`...) with prose in `message`; `details` and `reason` are gone; a rejected form is always 422 `validation_failed` with `errors` (409 for a uniqueness clash). Unknown routes and the auth pipeline's 401 answer the same shape. `docs/specs/api-conventions.md` (R15, R16) is the rule; `GamendWeb.ApiShapeTest` checks the OpenAPI document against it and `GamendWeb.ResponseContract` checks every response the test suite provokes, so an endpoint answering any other way fails CI. The remaining domains follow in later slices.
- [changed] **Chat, notification and push responses have names.** `ChatMessage`, `ChatReadCursor`, `ChatUnread`, `ChatMuteRecord`, `UnmuteResult`, `Notification`, `DeletedCount`, `PushToken` and `OkResponse`, with their pages, replace the generated classes for 24 endpoints. Muting answers `{data: mute}`, unmuting `{ok, removed}`, reporting and deleting a message `{ok: true}` and marking a conversation read its read cursor; all were documented as something else or nothing. Eight of these endpoints had no test reaching their success response; they do now.
- [breaking] **Request body classes are named after their own endpoint.** Generators merged bodies that were identical, so 21 endpoints took another's class — the player's avatar upload an `AdminSetQuestIconRequest`, `join_lobby` a `PartyJoinLobbyRequest`, `kick_user` a `KickPartyMemberRequest`. Every body is now `<Endpoint>Request` (`SetCurrentUserAvatarRequest`, `JoinLobbyRequest`, `KickUserRequest`); the other 72 keep the names they had. In the JS SDK the option key follows the class (`joinLobby(id, { joinLobbyRequest })`). `clients/godot_migrate.py` rewrites a game's uses, choosing per call site where one old class now splits in two.
- [changed] **Group and party responses have names.** `Group`, `GroupMember`, `GroupJoinRequest`, `GroupInvite` (each with a page), `Party`, `PartyInvite`, `PartyStats` and `StatusResponse` replace 17 generated classes such as `ListMyGroups200ResponseDataInner` and `AcceptPartyInvite200Response`; party lobby actions document the `Lobby` they return, and party members are documented as the `UserBrief` rows they are. The six party-invite endpoints had no test reaching their success response; one flow test covers them now.
- [breaking] **Godot SDK model classes are prefixed `Gamend`.** `GamendLobby`, `GamendSession`, `GamendCreateLobbyRequest`: GDScript `class_name` is global, so an unprefixed `Lobby` or `Friend` would clash with a game's own class. Code that names a model class updates by adding the prefix, or to the new name where a response was named: `GetLobby200Response` is `GamendLobbyResponse`, `OauthRequest200Response` is `GamendOAuthAuthorization`. `GamendApi`, `GamendClient` and `GamendResult` keep their names.
- [fixed] **`authenticate_list_auth_providers()` in the Godot SDK returned no providers.** The generated setter compared the whole array's text against the allowed provider names, never matched, and dropped the value. Enum checks in generated models now apply to strings only. Found by a live run of the regenerated SDK against a dev server.
- [added] **SDK checks and a Godot migration tool.** `clients/check_godot.sh` compiles every script of the generated addon in a headless Godot, and with a server URL makes live calls that must land in their named classes; `clients/check_js.js` does the same for the built JS package. `clients/godot_migrate.py` rewrites a game's references to renamed SDK classes, pairing old and new classes by operation and property rather than by a hand-kept list; on a copy of `polyglot-pirates-game` it resolved all 47 references and the game compiled as before. The JS `generate` script now clears the previous output first, so a renamed model no longer lingers in the built package. `generate_godot.sh` runs a local generator jar instead of Docker when `OPENAPI_GENERATOR_JAR` is set.
- [added] **Plans for more client SDKs**: `docs/specs/client-sdks.md` (C++, C#/Unity, TypeScript, Rust, Lua, GML, and one conformance scenario for all of them) and `docs/specs/cpp-sdk.md`.

- [fixed] **The admin configuration page never showed the TLS certificate.** It read the decoded certificate's signature algorithm where its body was, every field lookup raised, and the rescue turned that into "no certificate". Serial numbers with an odd digit count also paired their hex bytes wrong. Both covered by a test against a generated certificate chain.
- [fixed] **A malformed id in an admin filter crashed or was ignored.** The KV user and lobby filters raised `Ecto.Query.CastError`; the push filter silently listed every user's tokens. `Gamend.Query.filter_id/3` matches nothing for an id that is not one. The admin matchmaking and push pages search by name or id, like economy, inventory and quests.
- [changed] **`Gamend.Accounts`, `Gamend.Payments` and the admin configuration page are split by concern.** Accounts (3,000 lines) delegates to `Search`, `Stats`, `Registration`, `Identities`, `Sessions`, `Profile`, `Presence` and `Broadcasts`; Payments (2,275) to `Admin`, `StripeEvents` and `StoreEvents`, with its payload helpers in `Payments.Params`; the configuration LiveView (2,940) to `ConfigDiagnostics`, `ConfigSections` and `ConfigSystemSections`. Every public function keeps its name on the original module. `mix gen.sdk` follows the delegates, so the plugin SDK stubs keep their docs and specs.
- [changed] Deduplication with no behaviour change: `GamendWeb.Pagination.total_pages/2` (the page count, written inline or as a private `ceil_div/2` in some forty views), `Gamend.Parse.blank_to_nil/1`, `GamendWeb.AdminLive.Shared.list_opts/2`, `GamendWeb.ChannelEvents.other_info/2` for the final `handle_info/2` of six channels, and paging for the admin logs sessions, storage objects and chat history through the shared helpers.

- [fixed] **Dates read in the reader's language.** Calendar dates (`<.timestamp at={%Date{}}>`) and the blog's month headings rendered in English everywhere: the month names went through a `gettext` call that no catalog had entries for. Both now render through `Intl` in the browser, like the timestamps already did, pinned to UTC so a date never shows as the day before west of Greenwich.
- [fixed] **Core pages were English on hosts without their own translations.** `gamend_web`'s catalog had not been re-extracted since the blog, changelog and roadmap pages, the error pages, the store's closing times and the stats page's activity cards were added, so a host translating through it — the starter — showed those 33 strings in English in every locale. Extracted, merged and translated in all 29 catalogs; the starter's search palette now takes its page titles from them.
- [fixed] **Admin and player pages crashed on a hand-edited page size**, which went through `String.to_integer/1`, and "next" paged past the last page into empty tables. Twenty-nine LiveViews now share `GamendWeb.LiveHelpers.prev_page/2`, `next_page/3` and `put_page_size/3`, which clamp to the known page count and to `Gamend.Limits`.
- [fixed] **A non-numeric score answered 500** from the admin leaderboard record API (`String.to_integer/1` again). It answers 400 `invalid_score`, and a record for a deleted leaderboard answers 404. The admin leaderboard page crashed on the same input, and on any failed submit that was not a validation error — an ended leaderboard, an unknown user.
- [fixed] **A row deleted between the check and the write answered 500.** The contexts check that a user or leaderboard exists before writing — SQLite cannot name the violated constraint — but the row can go in between. `Gamend.Repo.rescue_foreign_key/2` answers that window like the check would have: `user_not_found` for currency and item changes, `user_not_found` or `leaderboard_not_found` for scores.
- [changed] **`sender_name`, `host_name`, `creator_name` and `leader_name` fall back to the username.** They sent `""` for a player with no display name, while a party or group invite's `sender_name` already fell back — the same field named the same player two ways. Fields literally named `display_name` still carry the raw column. Web pages no longer label an unknown player "User #<id>".
- [changed] **Unknown channel events** get the same `unknown_event` reply and debug line on every channel, through `GamendWeb.ChannelEvents`, which also sends the presence and member-updated pushes lobby, group and party channels each built themselves.
- [changed] Deduplication with no behaviour change: `Gamend.Parse` (integer and key-stringifying helpers copied across contexts, controllers and LiveViews), `Gamend.Broadcast.best_effort/3`, `Gamend.Query.filter_user/2` (the user search the economy, inventory and quest listings each wrote inline), `Gamend.Ledger.list_entries/2`, `GamendWeb.Serializers.serialize_kv_entry/1` and `GamendWeb.AdminLive.Shared.put_filters/3`.
- [added] **`GAMEND_DEV_BENCH=1`** runs the dev server without the code reloader and LiveView's debug annotations and expensive runtime checks, which cost more than the change being measured. `stress/README.md` uses it, with a results directory per run and a fresh database for A/B comparisons.
- [changed] **`gamend_core` has its own test suite.** The context tests lived in `gamend_web` and could lean on web modules without anyone noticing; they now run without the web app, which found a core module (`Gamend.Theme.JSONConfig`) that crashed when `gamend_web` was not loaded. `Gamend.DataCase`, the fixtures and `NoopHooks` (now `Gamend.TestSupport.NoopHooks`) are shared from `apps/gamend_core/test/support`, and root `mix test` runs both suites.

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
- [added] **Icons everywhere** — `icon_url` on notifications, tournaments, groups and leaderboards.
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
- [added] Security: RealIp, IP bans, OAuth CSRF, rate limiting, WebRTC limits, security headers.
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
