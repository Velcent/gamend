# `Gamend.Accounts.AgePolicy`
[🔗](https://github.com/appsinacup/gamend/blob/v1.0.7/lib/gamend/accounts/age_policy.ex#L1)

What a user's age permits.

One module owns two things: deriving an account's bracket from the age fields
on `users`, and saying what that bracket may do. Everything that gates on age
asks here rather than re-deriving a threshold, because the thresholds are not
a single number and getting them slightly different in two places is how a
child ends up treated as an adult on one surface and not another.

## The brackets

  * `:adult` — 18 or over.
  * `:teen` — old enough for their country's digital-consent age, but under 18.
  * `:child` — under 13, **or** under their country's digital-consent age,
    whichever is higher. This is Epic's rule after the FTC action, and it is
    the one that survives contact with the EU: a 14-year-old is a teen in the
    US and a child in Romania, because Romania's Article 8 age is 16.
  * `:unknown` — no age answer. Treated as `:child`, with one exception.

## The exception: grandfathered accounts

An account created before the age gate existed has `grandfathered_at` set and
no age answer. Restricting those on deploy would take chat, purchasing and
leaderboard identity away from every existing player at once, so they keep
adult capability until they answer the prompt. `grandfathered_at` records
a fact — this account predates the gate — rather than granting a permission,
and answering clears it.

This is a deliberate, dated decision with a real cost: a child already playing
keeps an unrestricted account until they answer. See the migration.

## Which direction an age may move

Down is free; up is not. A user may always lower their stated age, because
that only ever increases protection. Raising it needs a stronger signal than
the one that set it — a platform age bracket, a guardian's action, or a
verified check — so the same session that answered "under 13" cannot simply
answer again. Google's shipped behaviour is the reference: an under-13
account's birthdate cannot be corrected by the user at all.

Graduation is automatic and needs no signal: an account leaves `:child` on the
first of its birth month, which is conservative by up to 30 days.

# `class`

```elixir
@type class() :: :unknown | :child | :teen | :adult
```

# `t`

```elixir
@type t() :: %Gamend.Accounts.AgePolicy{
  avatar_upload?: term(),
  chat_default_on?: term(),
  class: term(),
  custom_display_name?: term(),
  discoverable?: term(),
  leaderboard_identity: term(),
  map_presence_published?: term(),
  public_groups?: term(),
  purchases?: term(),
  third_party_egress?: term(),
  timers_enforced?: term()
}
```

# `age_in_years`

```elixir
@spec age_in_years(integer(), integer(), Date.t()) :: integer()
```

Age in whole years from a birth year and month, on a given date.

Rolls on the first of the birth month rather than an exact day, because the
day is deliberately not stored. An account is therefore up to 30 days older
than this says, never younger.

# `class_for_age`

```elixir
@spec class_for_age(integer(), String.t() | nil) :: class()
```

The bracket an age falls in for a country.

`child` is the higher of 13 and the country's Article 8 age, so the same age
can be a teen in one country and a child in another.

# `classify`

```elixir
@spec classify(Gamend.Accounts.User.t(), Date.t() | nil) :: class()
```

The bracket for a user, as of `on` (defaults to today, UTC).

Returns `:unknown` for an account with no age answer — which callers must
treat as `:child` unless `grandfathered?/1` says otherwise. Use `policy/2`
rather than reading this directly; it resolves that rule for you.

# `digital_consent_age`

```elixir
@spec digital_consent_age(String.t() | nil) :: pos_integer()
```

The digital-consent age for a country, defaulting to 16.

# `effective_class`

```elixir
@spec effective_class(Gamend.Accounts.User.t(), Date.t() | nil) :: class()
```

The effective bracket a caller should enforce.

This is the one to call. It collapses the `:unknown` question: an account with
no age answer is a `:child`, unless it predates the gate, in which case it is
treated as an adult until it answers.

# `grandfathered?`

```elixir
@spec grandfathered?(Gamend.Accounts.User.t()) :: boolean()
```

Whether this account predates the age gate and so keeps adult capability
while its age is still unknown.

Answering the age prompt clears `grandfathered_at`, at which point the answer
governs and this returns false.

# `known_countries`

```elixir
@spec known_countries() :: [String.t()]
```

Every country whose threshold is known, for tests and admin display.

# `may_change_age?`

```elixir
@spec may_change_age?(Gamend.Accounts.User.t(), integer(), integer(), String.t()) ::
  boolean()
```

Whether a proposed age answer may replace the one already recorded.

Lowering is always allowed. Raising needs a stronger signal than set the
current answer, so a user cannot simply re-answer their way out of a
restriction in the same session.

# `methods`

```elixir
@spec methods() :: [String.t()]
```

Every age-collection method, strongest last.

# `policy`

```elixir
@spec policy(Gamend.Accounts.User.t(), Date.t() | nil) :: t()
```

What a user may do.

The defaults on the struct are the child defaults, so a field nobody
remembered to set is closed rather than open — the same default-deny posture
as `before_kv_get/2`.

# `policy_for`

```elixir
@spec policy_for(class()) :: t()
```

The policy for a bracket, without a user.

# `stronger_signal?`

```elixir
@spec stronger_signal?(String.t() | nil, String.t() | nil) :: boolean()
```

Whether `method` is a stronger age signal than `current`.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
