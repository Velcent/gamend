# `Gamend.Apple`
[🔗](https://github.com/appsinacup/gamend/blob/v1.0.7/lib/gamend/apple.ex#L1)

Apple OAuth client secret generation for Ueberauth.

Apple requires client secrets to be generated dynamically as they expire after 6 months.
This module handles the generation and caching of Apple client secrets.

# `client_secret`

```elixir
@spec client_secret(keyword()) :: String.t()
```

Generates or retrieves a cached Apple client secret.

Returns the client secret string, either from cache or newly generated.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
