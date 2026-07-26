# `GameServer.ApiConventions`
[🔗](https://github.com/appsinacup/game_server/blob/v1.0.7/lib/game_server/api_conventions.ex#L1)

Mechanical checks for the conventions in `docs/specs/api-conventions.md`.

Source-level, not runtime: the rules are about how code is *written*
(field names, serializer shapes, route paths), so they are checked by
parsing files rather than by introspecting a booted app. `mix gamend.api.lint`
runs them; CI fails on any violation.

These exist because the conventions were implicit for a year and drifted
exactly where nobody was looking — 16 fields serialized `null` against a
documented "never null" policy, OpenAPI schemas contradicted their own
serializers, and one duration setting shipped with no unit in its name.
A convention nothing enforces is a suggestion.

# `violation`

```elixir
@type violation() :: %{
  rule: String.t(),
  file: String.t(),
  line: pos_integer(),
  message: String.t()
}
```

# `declared_route_paths`

```elixir
@spec declared_route_paths() :: [String.t()]
```

Every path the compiled router serves, `:params` as `{}`.

Read from `Phoenix.Router.routes/1` rather than parsed from source — routes
live inside `scope` blocks, so the literal strings in the source are
suffixes, not full paths.

# `nullable_schema_fields`

```elixir
@spec nullable_schema_fields() :: %{required(String.t()) =&gt; String.t()}
```

String/map schema fields that can actually be nil: no `default:`, and not in
the changeset's required list.

# `violations`

```elixir
@spec violations() :: [violation()]
```

Every violation, ordered by rule then file.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
