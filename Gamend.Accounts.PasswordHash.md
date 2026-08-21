# `Gamend.Accounts.PasswordHash`
[🔗](https://github.com/appsinacup/gamend/blob/v1.0.7/lib/gamend/accounts/password_hash.ex#L1)

Password hashing: Argon2id for new hashes, bcrypt still accepted for old ones.

Argon2id is memory-hard, which is the property bcrypt lacks — bcrypt works in
about 4 KB, so an attacker who steals the table can run guesses thousands-wide
on a GPU. Argon2id makes every guess reserve real memory, capping that
parallelism on the hardware attackers actually own. It is OWASP's first
choice for new systems; bcrypt is their fallback.

It is also faster here at equal-or-better strength. Measured on an M1:
bcrypt at its default cost 12 takes **260ms**, and Argon2id at the settings
below takes **~24ms** — roughly ten times the logins per second, from the
slowest row in the whole load test.

## The memory is bounded by schedulers, not by traffic

Argon2id's cost that bcrypt does not have is RAM, charged per *concurrent*
hash. It does not grow with request volume, because the NIF runs on a dirty
CPU scheduler and the BEAM has a fixed number of those — one per visible
vCPU. At most that many hashes hold memory at once; the rest queue without
allocating.

Measured on an 8-core machine at the settings below: 8 concurrent hashes
added 112 MB of RSS, and **512 concurrent added the same 112 MB**, taking
longer instead of more memory. So the ceiling is `vCPUs x m_cost` —

    shared-cpu-1x / performance-1x   1 vCPU    16 MiB
    shared-cpu-4x                    4 vCPU    64 MiB
    shared-cpu-8x                    8 vCPU   128 MiB
    performance-2x                   2 vCPU    32 MiB

— which is a few percent of any of those machines' RAM. A login flood gets
slow, not fatal, and that is the right failure mode. `GAMEND_AUTH_ARGON2_
MEMORY_LOG2` still lowers it if a box is tight, and the per-IP auth rate
limit (10/minute) sits in front regardless.

The library's own defaults (64 MiB, parallelism 4) are wrong for a game
server on a shared vCPU, which is why every parameter is set explicitly
here. The chosen settings sit between two configurations OWASP rates as
equivalent (19 MiB/t=2 and 12 MiB/t=3); `m_cost` is a log2 exponent, so
19 MiB is not expressible and 16 MiB is the nearest step.

## Migration

Nothing rewrites the table. `verify/2` dispatches on the hash's own prefix,
so a bcrypt hash keeps working for as long as it exists, and
`needs_rehash?/1` lets a successful login upgrade that user in the
background. A password that is never used again stays bcrypt forever, which
is fine: it is still a bcrypt hash, exactly as safe as it was yesterday.

# `hash`

```elixir
@spec hash(String.t()) :: String.t()
```

Hashes `password` with Argon2id at the configured settings.

# `needs_rehash?`

```elixir
@spec needs_rehash?(String.t()) :: boolean()
```

Whether `hash` was written by something other than current settings, and the
owner should be upgraded on their next successful login.

# `no_user_verify`

```elixir
@spec no_user_verify() :: false
```

Burns the time a real verification would take, for the no-such-user branch.

This is deliberately Argon2id's dummy and not bcrypt's. It cannot match both
while the table holds a mix, and matching the algorithm new accounts get is
the one that keeps mattering as the bcrypt rows drain away. Until they do,
the gap between a 24ms Argon2id user and a 260ms bcrypt user is observable —
it reveals only whether that account has signed in since the switch, never
whether the password was right.

# `verify`

```elixir
@spec verify(String.t(), String.t()) :: boolean()
```

Verifies `password` against `hash`, dispatching on the algorithm that wrote
it. Returns false for anything unrecognised rather than raising, so a corrupt
row is a failed login and not a 500.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
