# Named API schemas

Goal: every response shape in the OpenAPI document is a named component —
`Lobby`, `LobbyPage`, `PageMeta`, `ErrorResponse` — checked against what the
server actually sends, so any generator in any language produces types a
person would have written by hand.

This is the prerequisite for every SDK in [client-sdks.md](client-sdks.md).
It changes no wire format.

## Why

The document describes 251 operations with 9 named schemas (the five
`ClientLog*` ones, `ErrorResponse`, `HealthResponse`, two OAuth). Everything
else is inline: 777 inline object schemas, 150 distinct shapes. The
`{error: string}` shape alone is restated 374 times.

Generators name what the document does not, from the operation and its
position:

- Godot gets 157 classes like `ListLobbies200ResponseDataInner`, and
  `generate_godot.sh` carries ~90 lines of `perl -i` rewriting the generator's
  snake/Pascal confusion about those invented names.
- A generator dedupes identical inline shapes, so every `{error}` becomes one
  class named after whichever operation came first.
- `polyglot-pirates-game` references 26 of these names across 8 files
  (`UserQuests200ResponseDataInner`, `GetMyRecord200ResponseData`, …).
- A C#, TypeScript or C++ SDK would ship the same names to every user,
  permanently.

And inline schemas drift, because nothing ties them to the serializer:

- `@lobby_schema` omits `state` and `state_changed_at`, which
  `Serializers.serialize_lobby/2` has sent since the lobby-state work.
- `join_lobby` and `set_lobby_state` document `%Schema{type: :object}` — no
  properties — while both return a full lobby.

A typed SDK drops a field its schema does not declare. Naming the shapes
without checking them would ship that loss into every generated client, so
the check is half of this spec.

## Scope

**In:** every response schema, public and admin.

**Out, deliberately:**

- **Wire changes.** Mutations that return a bare lobby rather than `{data: …}`,
  and `{}` rather than `{"ok": true}`, contradict
  [api-conventions.md](api-conventions.md) but are what clients parse today.
  They are listed as found (see *Wire inconsistencies*) for a later, separately
  versioned change. This spec names what is sent; it does not change it.
- **Request bodies.** Generators already name an inline body
  `<OperationId>Request` (`CreateLobbyRequest`), which is the name anyone would
  choose. A body shared by several operations gets a module; the rest stay put.
  This also leaves `generate_balaur.py`, which reads `requestBody` schemas
  directly, untouched.

## Names

| Shape | Name | Example |
|---|---|---|
| A serialized entity | Singular noun, the proto message name where one exists | `Lobby`, `Group`, `UserBrief`, `ChatMessage` |
| A variant | Role prefix/suffix, never the operation | `User` / `UserBrief` / `CurrentUser`; `AdminLobby` |
| `{data: [T], meta}` | `<T>Page` | `LobbyPage` |
| `{data: T, …extras}` | `<T>Response` | `LobbyResponse` (`data`, `members`, `spectator_count`) |
| A bare entity | The entity | `create_lobby` → `Lobby` |
| Pagination block | `PageMeta` | the six keys from `Pagination.meta/4` |
| Any error | `ErrorResponse` | `error`, optional `reason`, optional `errors` (R12) |
| `/stats` counters | `<Area>Stats` | `LobbyStats` |

Matching the realtime proto's names (`Lobby`, `Group`, `Party`, `UserBrief`,
`ChatMessage`, `Notification`, `QuestProgress`, `KvEntry`) is the point, not
a nicety: an SDK can then use one `Lobby` type for `GET /lobbies/:id` and for
the `lobby:<id>` `updated` event.

A module's title is its last segment (`GamendWeb.Schemas.LobbyPage` →
`"LobbyPage"`), so the component key is predictable from the code. A test
asserts titles are unique across `GamendWeb.Schemas.*`: OpenApiSpex keys
components by title, and a clash silently keeps one.

## Mechanism

One module per shape in `apps/gamend_web/lib/gamend_web/schemas/`, the way
`ErrorResponse` and the `ClientLog*` schemas already are:

```elixir
defmodule GamendWeb.Schemas.Lobby do
  @moduledoc "A lobby as `Serializers.serialize_lobby/2` sends it."
  require OpenApiSpex
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "Lobby",
    type: :object,
    properties: %{id: %Schema{type: :string, format: :uuid}, …},
    required: [:id, :title, …]
  })
end
```

Envelopes repeat the same few lines per entity, so one macro,
`GamendWeb.Schemas.Envelope`, writes them:

```elixir
defmodule GamendWeb.Schemas.LobbyPage do
  use GamendWeb.Schemas.Envelope, page: GamendWeb.Schemas.Lobby
end

defmodule GamendWeb.Schemas.LobbyStatsResponse do
  use GamendWeb.Schemas.Envelope, data: GamendWeb.Schemas.LobbyStats
end
```

Controllers reference modules (`items: Lobby`, `{"…", "application/json",
LobbyPage}`), and `OpenApiSpex.resolve_schema_modules/1` — already the last
step of `GamendWeb.ApiSpec.spec/0` — turns them into `$ref`s. Error responses
go through one helper, `GamendWeb.Schemas.error("Not authenticated")`, so the
374 restatements become one reference each.

`required` lists what the serializer always sends. Fields gated by an
option (`include_members`, `include_slowdown`) are declared but not required.

## The check

A test-only plug, `GamendWeb.ResponseContract`, registered by the endpoint
when `config :gamend_web, :response_contract, true` (set in
`apps/gamend_web/config/test.exs`, absent everywhere else, host repos
included). Before every JSON response from a controller that
declares OpenAPI operations, it:

1. validates the body against the documented schema for that status
   (OpenApiSpex's own cast, as `assert_operation_response/2` does);
2. fails on any key the schema does not declare — the drift typed SDKs would
   silently drop — for every object schema with `properties` and no
   `additionalProperties`;
3. fails on an undocumented 2xx status. An undocumented 4xx must still be an
   `ErrorResponse`, but need not be listed per operation: every error is the
   same type, so a missing status costs a client nothing. 5xx is skipped — a
   crash already fails the test, and the error page Phoenix renders after a
   violation would otherwise replace the violation's own message.

It raises inside the request, so the existing controller tests become the
contract tests without being edited: the lobby suite's 44 tests exercise
every lobby operation. Enforcement is by tag — a list in the plug that grows
one domain per slice and is deleted when every domain is in. That list is a
migration ratchet, not a baseline: it only ever grows, and it ends empty.

## Slices

One domain per change, each self-contained: modules, controller references,
the tag added to the check, tests green, spec regenerated.

1. **Pilot — Lobbies. Done.** `PageMeta`, `UserBrief`, `Lobby`, `LobbyPage`,
   `LobbyResponse`, `LobbyStats`, `LobbyStatsResponse`; `ErrorResponse`
   gains optional `reason` and `errors`. On the old inline schemas the check
   failed 17 of the 44 lobby tests — the drift below — and passes all of them
   on the named ones; the full web suite (1,993 tests) passes with it on.
   `generate_balaur.py` output is byte-identical before and after.
2. Users, Authentication, Friends (the `User` family and `CurrentUser`).
3. Groups, Parties.
4. Chat, Notifications, Push.
5. Leaderboards, Tournaments.
6. Quests, Economy, Payments.
7. KV, Hooks, Matchmaking, Ready checks, Time, Signaling, Storage.
8. Admin – * (mostly `Admin<T>` variants and pages of existing entities).
9. **Close-out.** Drop the tag list (enforce everywhere); add R15 to
   `mix gamend.api.lint` — no inline object schema with `properties` in any
   response; delete the per-model `perl` fixups from `generate_godot.sh` that
   no longer match anything.

## SDK impact

The document gets better; generated client class names change. Nothing on
the wire moves, so an existing build keeps working until it regenerates.

- **Godot.** GDScript `class_name` is global, and a game is likely to have
  its own `Lobby` or `Quest`. Generate with `--model-name-prefix Gamend`
  (`GamendLobby`), which also renames the request classes — once, in the same
  release as the response renames, rather than two breaks. The hand-written
  facade's references (`GamendApi.gd`, `GamendAuth.gd`, `GamendClient.gd`)
  update in that change. *Decision needed before the first Godot release after
  slice 1.*
- **JavaScript.** Model classes are renamed; method names and call shapes are
  not. Only code importing model classes by name notices.
- **Balaur.** Untouched — it is untyped, and request bodies stay inline.
- **Migration table.** Each slice's CHANGELOG `[breaking]` entry lists old →
  new generated names for its operations, produced by diffing the generator
  output before and after, so `polyglot-pirates-game`'s 26 references are a
  find-and-replace.

## Wire inconsistencies (found, not fixed here)

Recorded as each slice finds them, for a later versioned change:

- Lobby mutations (`create`, `update`, `join`, `quick_join`, `set_state`)
  return a bare lobby, not `{data: lobby}`.
- `leave`, `kick`, `disband` return `{}`, not `{"ok": true}`.
- `set_lobby_state` returns `{error, reason}` where `reason` is an
  `inspect/1` of an Elixir term.
- `host_id` is `""` for a hostless lobby, so it cannot carry `format: :uuid`
  (the never-null policy and the format disagree).

Schema drift the pilot fixed in the document (the wire was already right):

- `Lobby` lacked `state` and `state_changed_at`.
- Lobby members lacked `is_activated`.
- `host_id` was `format: :uuid, nullable: true`; it is a string that is
  `""` when hostless.
- `join_lobby` and `set_lobby_state` documented an empty object; both return
  a `Lobby`. Six operations gained the error statuses their code returns.

## Definition of done (CONTRIBUTING)

- [ ] Every response schema is a `GamendWeb.Schemas.*` module or a `$ref` to
      one; request bodies inline unless shared.
- [ ] `GamendWeb.ResponseContract` enforced for every tag; tag list removed.
- [ ] Title uniqueness test.
- [ ] R15 in `Gamend.ApiConventions` with no violations; documented in
      [api-conventions.md](api-conventions.md), including the naming table.
- [ ] `generate_godot.sh` regenerated with the model prefix; dead `perl`
      fixups removed; facade updated; JS SDK regenerated; Balaur `--check`
      clean.
- [ ] CHANGELOG `[breaking]` per slice with the old → new name table.
- [ ] `mix format`, `mix credo --strict`, full `mix test` green on both
      adapters; `mix gamend.api.lint` clean.
