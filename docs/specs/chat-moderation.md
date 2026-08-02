# Chat moderation — word filter, report queue, mute

Design spec for the Phase 1 **Chat moderation** item in
[ROADMAP.md](../../ROADMAP.md). Format and rigor mirror the Phase 0 sections.

Goal: give hosts the three moderation primitives every chat needs — a **word
filter** that runs before a message is stored, a **report queue** players feed
and moderators work, and **mutes** that silence an abuser without banning their
IP. All three are enforced server-side in the chat pipeline that already
exists; muting is additionally delegated to in-room authority (lobby host,
party leader, group admin).

## Why (chat exists; moderation doesn't)

`Gamend.Chat` already carries lobby/group/friend/party messages with a
`before_chat_message/2` **pipeline hook** and an `after_chat_message/1` hook, and
persists to `chat_messages`. What's missing is any way to stop abuse: today a
plugin *could* hand-roll a filter in `before_chat_message`, but there's no
built-in blocklist, no player-facing report path, and no mute. This item ships
all three as core, enforced in the same pre-persist pipeline so nothing
unmoderated ever hits the database or PubSub.

**Why core when the hook exists:** the hook stays the policy escape hatch
(custom rules, ML classifiers), but without core primitives every host rebuilds
the same machinery — an evasion-resistant normalizer, a durable report queue
with an admin UI, and mute state that survives restarts and syncs across
instances. Core ships **mechanism, not policy**: the blocklist is empty by
default and admin-managed — no curated per-language word lists (see Deferred /
rejected) — and a plugin can still veto or extend anything after core's checks.

## The enforcement point — `before_chat_message`

The filter and mute checks run inside the existing `before_chat_message/2`
pipeline (which already returns `{:ok, attrs} | {:error, reason}`), so a rejected
message is never inserted and never broadcast. Core runs its checks first, then
delegates to any plugin hook — a plugin can still veto further but cannot see a
message core already blocked. **Never inside a transaction/lock** (CONTRIBUTING
§Hooks): the checks are pure reads (ETS mute lookup, in-memory word scan) with no
write, so they add no contention.

## 1. Word filter

- **Blocklist** stored in a `chat_filter_words` table (admin-managed) — `word`
  (unique, normalized), `severity` (`"block"` | `"mask"` | `"flag"`),
  `match_mode` (`"exact"` | `"substring"`), `lang` (nullable provenance tag —
  `"en"`, `"de"`, … or null for hand-added), timestamps. **Ships empty** — hosts
  paste/import whatever list they trust; `mix demo.seed` adds a few sample words
  for dev only. Loaded into an ETS set at boot and kept fresh via PubSub on edit
  — the `IpBans` shape (durable table = source of truth, ETS = hot path, PubSub
  = cluster sync), but owned by a core `Chat.Moderation.Cache` GenServer:
  IpBans keeps its ETS in the web plug (`GamendWeb.Plugs.IpBan`), while this
  check runs in core, so the cache lives there too.
- **Bundled list (opt-in, and deliberately not a real one):**
  `priv/chat_filter/en.txt` holds two harmless placeholders (`badword`,
  `spamlink`) so the feature can be exercised end to end. Core ships **no**
  profanity or slur list: the server is MIT-licensed, and vendoring someone
  else's judgement about what is offensive in 30 languages is both a licence
  question and a policy one we should not answer for the host. Nothing is
  auto-loaded — the admin filter page gets an **Import bundled list** button
  (language picker + severity choice) that inserts through the normal changeset
  path, so `max_chat_filter_words` still applies.
- **Sourcing a real list** is documented in three places a host will actually
  look: the header of `en.txt`, the Chat guide, and the admin page itself.
  Two supported paths, both stated explicitly:
  - **Bundled file** — drop `priv/chat_filter/<lang>.txt` (one word per line,
    `#` comments) and **rebuild**; the directory is read from the compiled
    app's `priv/` via `Application.app_dir/2`, so a file added after the build
    is invisible to a running server. Then import it from admin.
  - **Admin API** — `POST /api/v1/admin/chat/filter_words` per word, for lists
    that live outside the repo or change between deploys; tagging rows with
    `lang` keeps the one-click bulk removal working.
  Pointers given: LDNOOBW (CC-BY-4.0) and Shutterstock's list (MIT), with a
  warning that search-query lists are far more aggressive than chat needs.
- **Which language applies at runtime: all of them.** A message carries no
  reliable language signal (players code-switch, and detecting per-message is
  both slow and wrong on short strings), so matching is **language-agnostic** —
  every enabled word is one flat ETS set, checked against every message. `lang`
  is provenance only: it records which bundled list a row came from, powers
  "remove the German list" as a bulk action, and is shown as a column in admin.
  The host controls exposure by choosing which lists to import — importing all
  30 raises false positives (a benign word in one language is a slur in
  another), so the admin page defaults the picker to the host's configured
  locales and says so.
- **Normalization** before matching: lower-case, collapse repeated chars
  (`heeeello`→`helo`), strip zero-width/diacritics, map common leetspeak
  (`@→a`, `3→e`, `1→i`). Kept in `Gamend.Chat.Moderation.Normalizer` so the
  admin "test this phrase" tool and the runtime path share one implementation.
- **Actions** by severity: `block` rejects (`{:error, :blocked_content}`);
  `mask` replaces the hit with `***` and lets the (masked) message through;
  `flag` stores it verbatim but sets `metadata["flagged"] = true` and auto-files
  a report for the queue. Timing: in `before_chat_message` no message id exists
  yet, so `flag` only marks the attrs; the report row is inserted after the
  message commits, on the same deferred post-persist path as
  `after_chat_message`.
- Config caps in `Gamend.Limits`: `max_chat_filter_words`,
  `max_chat_filter_word_len`.

## 2. Report queue

- **`chat_reports`** table: `reporter_id`, `message_id`
  (`references(:chat_messages, on_delete: :nilify_all)` — keep the report if the
  message is deleted), a denormalized `reported_user_id` + `content_snapshot`
  (so the queue survives message deletion), `reason` (string), `status`
  (`"open"` | `"reviewing"` | `"actioned"` | `"dismissed"`), `resolved_by`,
  `resolution_note`, timestamps.
- **Indexes:** partial `index([:status], where: "status = 'open'")` for the
  queue sweep + dashboard counter; `index([:reported_user_id])` for "history for
  this user"; `unique_index([:reporter_id, :message_id])` so a player can't
  spam-report one message.
- **Endpoint** `POST /chat/messages/:id/report {reason}` — auth'd, rate-limited
  via `max_chat_reports_per_user_per_day` (`Gamend.Limits`, same rolling-24h
  pattern as `max_chat_messages_per_day`). Auto-flag from the word filter files a
  report with `reporter_id = nil` (system).
- **Context:** `Chat.report_message/3`, `Chat.list_reports/2` + `count_reports/1`
  (paginated, filter by status/user), `Chat.resolve_report/3` (admin: set status
  + note, optionally mute/delete in one call).

## 3. Mute

- **`chat_mutes`** table: `user_id`, `scope` (`"global"` | `"lobby"` |
  `"group"` | `"party"` — the room-like `@chat_types`; friend DMs are silenced
  only by a `global` mute), `scope_ref_id` (null for global), `expires_at`
  (null = permanent),
  `reason`, `muted_by`, timestamps. `unique_index([:user_id, :scope, :scope_ref_id])`;
  partial `index([:user_id], where: "expires_at IS NULL OR expires_at > now()")`
  is not portable, so index `[:user_id]` and filter expiry in the query.
- **Who can mute — authority follows the room, mirroring kick:**
  - `global` — server-side only: admin UI/API or a plugin (`Chat.mute_user/4`).
  - `lobby` — the lobby host (`host_id`); hostless lobbies have no in-game
    muter (admin/plugin only).
  - `group` — members with role `"admin"`.
  - `party` — the party leader (`leader_id`).

  Unmute takes the same authority. `Chat.mute_user/4` stays the trusted
  mechanism with no permission logic; authorization lives in the controllers,
  reusing each kick endpoint's checks.
- **Hot path:** an ETS mirror keyed by `user_id` (loaded at boot, PubSub-synced,
  same core-side cache GenServer as the filter), checked in
  `before_chat_message` — a muted sender (matching scope; `global` covers every
  chat type) is rejected with `{:error, :muted}` before persist. Entries carry
  `expires_at` and are ignored once past it, so enforcement never depends on
  the sweep.
- **Sweep:** hygiene only, never load-bearing (expiry is checked at read time).
  IP bans purge lazily (`IpBans.purge_expired/0`, called from the plug); mutes
  instead get a supervised periodic worker, folded into the same
  `Chat.Moderation.Sync` GenServer that owns the boot load and PubSub mirror.
  It goes in `GamendWeb.HostSupervision.children/1` **only** — that module
  exists precisely because hand-maintained per-host child lists drifted, and
  the starter repo picks it up automatically. It is disabled in `config/test.exs`
  (`enabled: false`, like `Tournaments.Ticker` and `Matchmaking.Worker`): a
  boot-time read has no sandbox connection and starves the pool.
- **Context:** `Chat.mute_user/4`, `Chat.unmute_user/2`, `Chat.muted?/2`,
  `Chat.list_mutes/1` + `count_mutes/1`.

## Hooks (all six places, per CONTRIBUTING §Hooks)

Enforcement reuses the existing `before_chat_message`. Two **new observation**
callbacks so plugins can react (auto-escalate, notify moderators, tally strikes):

- **`after_chat_message_reported(report)`**
- **`after_user_muted(mute)`**

Each in all six places: `@callback` + `@optional_callbacks` in `Gamend.Hooks`,
`internal_hooks()` (RPC-blocked), no-op in `Hooks.Default`, SDK mirror
(`@callback`, `@optional_callbacks`, `__using__` default, **and `defoverridable`**),
Server-scripting docs. Both are fire-and-forget after commit (deferred, never in
the insert transaction).

## Limits (`Gamend.Limits`, auto `GAMEND_LIMITS_*`, listed in `@limit_categories`)

`max_chat_filter_words`, `max_chat_filter_word_len`, `max_report_reason` (len),
`max_chat_reports_per_user_per_day`, `max_mute_reason` (len).

## Web / API

- `POST /chat/messages/:id/report {reason}` — player reports (rate-limited).
- Scoped mutes mirror the kick routes: `POST /lobbies/mute` + `/lobbies/unmute`
  (host), `POST /groups/:id/mute` + `/groups/:id/unmute` (group admin),
  `POST /parties/mute` + `/parties/unmute` (leader) — body
  `{user_id, expires_at?, reason?}` — plus a paginated mute listing per scope
  for the same authority (needed for the unmute UX).
- **Global** muting and filter-word editing stay **server-authoritative** →
  **no public endpoint**; admin API + admin UI only (a plugin mutes via
  `Chat.mute_user/4`).
- Realtime: push `chat_muted` / `chat_unmuted` to the muted user over
  `UserChannel` (so clients can grey the input), listed in the realtime events
  table.
- Routes in `router/shared.ex`. Report submission returns `{"ok": true}`, not
  204 — no controller in this repo hand-rolls a 204, and `docs/specs/
  api-conventions.md` says a mutation returns `data` or `{"ok": true}`. The
  content snapshot is taken server-side.

## Admin

- `admin_live/chat_reports.ex` — the queue (paginated, filter by status/user,
  shows names + content snapshot). The lifecycle a moderator drives:
  **Review** claims an `open` report (→ `reviewing`, no resolution, so it stays
  in the queue and other moderators can see it is taken); **Dismiss**,
  **Delete message**, **Warn** and **Mute** each resolve it. Mute opens a dialog
  with scope, a duration (10m / 1h / 24h / 7d / permanent) and an editable
  reason — not a hardcoded permanent global mute. Warn notifies without muting.
  Every resolving action can also notify the **reporter** (skipped when the
  filter filed the report, which has no reporter).
- **Notifications** (`Chat.Moderation.Notices`) — admins get a standing "new
  chat reports" alert when one lands (upserted on title, so it stays one unread
  entry with a live count rather than one per report); the player gets an
  editable notice when warned or muted; the reporter gets an editable reply when
  their report is resolved. Core supplies `default_*_message/1` prefills only —
  the wording is the moderator's to change before sending.
- `admin_live/chat_mutes.ex` — active mutes, add/edit/remove, scope + expiry. An
  existing mute is **editable** (shorten, extend, re-word) rather than
  unmute-and-redo: `mute_user/4` upserts on the same scope key.
- `admin_live/chat_filter.ex` — blocklist CRUD, the **Import bundled list**
  button (language + severity), and a "test a phrase" box using the shared
  `Normalizer`.
- `/admin` stat card (open reports, active mutes) + routes + nav links +
  `admin_pages_render_test` entries.
- Admin API controllers under `controllers/api/v1/admin/` with **parity** for
  every action above.

## "Update everywhere" — file list

- **CHANGELOG** `[added]` Chat moderation (filter, reports, mute).
- **.env.example** — regenerated (`mix gamend.settings.env_example`), not hand-edited; CI runs it with
  `--check`. Same for `mix gamend.settings.guide`.
- **host_public_docs/** — Chat docs page gains a Moderation section; Data Schema
  page gains `chat_filter_words`, `chat_reports`, `chat_mutes`.
- **api_spec.ex** — feature list, report + scoped mute/unmute endpoints, and
  the realtime events table (`chat_muted` / `chat_unmuted`).
- **SDK** — regenerated `Chat`/admin stubs; struct stubs for the new schemas +
  `gen.sdk` placeholder rules for them (`T | nil`, `{:ok, T}`); hooks mirrored.
- **runtime_introspection.ex** — moderation counts (open reports, active mutes,
  filter size).
- **i18n** — extract/merge + translate 30 locales; clear fuzzies.
- **mix demo.seed** — seed filter words, a few open reports, and a sample mute.

## Deferred / rejected

- **ML / third-party toxicity classifiers: defer.** Ship the deterministic word
  filter first; the `before_chat_message` hook already lets a plugin call out to
  Perspective API etc. without core taking that dependency.
- **Shadow-muting (message visible only to sender): defer.** Adds per-recipient
  delivery filtering to the broadcast path; the `flag` severity + report queue
  cover the same need for v1.
- **Strike/auto-escalation policy: defer.** `after_chat_message_reported` +
  `after_user_muted` give a plugin everything needed to implement strikes
  without baking one policy into core.
- **Auto-enabled lists, and curated lists for all 30 locales: reject.** The
  filter ships inert and core does not curate content per language — that's
  policy (context, Scunthorpe-style false positives, locale politics), and a
  permanent maintenance tail. What core ships is the mechanism plus one small
  English starter list, importable in a click and removable in a click
  (`delete_filter_words_by_lang/1`). Hosts drop in their own or a third-party
  list per language.
- **Player-side friend/DM blocking (ignore lists): defer.** Global mutes cover
  DMs from the moderation side; a per-player block list is a social feature
  with its own UX surface, not moderation.

## Definition of done (CONTRIBUTING)

- [ ] Migrations for `chat_filter_words` / `chat_reports` / `chat_mutes` apply on
      SQLite **and** `GAMEND_DB_ADAPTER=postgres`; indexes as above.
- [ ] Filter + mute enforced in `before_chat_message` (nothing unmoderated
      persists/broadcasts); expired-mute sweep supervised in both trees.
- [ ] Paginated `list_*`/`count_*`; `Limits` caps in changesets; report
      rate-limit enforced.
- [ ] Hooks `after_chat_message_reported` / `after_user_muted` in all six places,
      RPC-blocked, SDK-mirrored.
- [ ] Admin pages (reports/mutes/filter) + `/admin` card + routes + nav +
      `admin_pages_render_test`; admin API parity.
- [ ] Docs, `.env.example`, CHANGELOG, `api_spec.ex`; i18n across 30 locales.
- [ ] Tests: context + controller (report + scoped mute auth: host / leader /
      group admin can, plain member cannot) + admin + LiveView, both adapters;
      boot and actually block a word, import a bundled list, file+resolve a
      report, mute+reject a sender.
- [ ] `mix format`, `mix credo --strict`, full `mix test` green; `mix gen.sdk`
      clean; example plugin compiles warning-free.
