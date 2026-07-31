# `Gamend.Time`
[🔗](https://github.com/appsinacup/gamend/blob/v1.0.7/lib/gamend/time.ex#L1)

The server's wall clock, in milliseconds since the epoch, for sending to
clients.

Wall clock and not monotonic because the value leaves the machine: a client
compares it against its own. Durations measured *inside* the server keep using
`System.monotonic_time/1`; never mix the two.

# `now_ms`

```elixir
@spec now_ms() :: integer()
```

---

*Consult [api-reference.md](api-reference.md) for complete listing*
