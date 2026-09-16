# `Gamend.Payments.Params`
[🔗](https://github.com/appsinacup/gamend/blob/v1.0.7/lib/gamend/payments/params.ex#L1)

Shape-wrangling shared by `Gamend.Payments` and its provider adapters.

Every provider receives a JSON body from somewhere outside — Apple's signed
notifications, Google's RTDN envelopes, Steam's form responses — and each one
needed the same four things: string-keyed maps, an epoch-millis timestamp as
an ISO-8601 string, a positive integer with a fallback, and a required
non-empty string.

So each one had them. `normalize_params/1` and its `normalize_nested/1`
existed verbatim in four modules (Apple twice, once in `Apple.JWS`),
`millis_to_iso8601/1` and `parse_positive_int/2` in two, `required_binary/2`
in two. None of the copies had drifted yet, which is the only reason this is
a tidy-up rather than a bug hunt.

# `millis_to_iso8601`

```elixir
@spec millis_to_iso8601(term()) :: String.t() | nil
```

Epoch milliseconds as an ISO-8601 string; `nil` when it is not one.

# `normalize`

```elixir
@spec normalize(term()) :: term()
```

Recursively string-keys a map, so a body that arrived as atoms and one that
arrived as JSON can be read the same way.

# `normalize_private_key`

```elixir
@spec normalize_private_key(String.t()) :: String.t()
```

Turns the literal `\n` sequences a PEM key picks up when it travels through an
environment variable back into real newlines.

# `parse_int`

```elixir
@spec parse_int(term()) :: integer() | nil
```

An integer, or an integer written as a string. `nil` for anything else.

# `parse_positive_int`

```elixir
@spec parse_positive_int(term(), integer()) :: integer()
```

A positive integer, or `default` when the value is missing or not one.

# `required_binary`

```elixir
@spec required_binary(map(), String.t()) :: {:ok, String.t()} | {:error, atom()}
```

Fetches `key` as a non-empty string, or `{:error, :missing_<key>}`.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
