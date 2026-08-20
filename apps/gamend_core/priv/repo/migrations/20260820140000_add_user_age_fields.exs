defmodule Gamend.Repo.Migrations.AddUserAgeFields do
  @moduledoc """
  Age on `users`, so a service can treat a child differently from an adult.

  Until now there was no age anywhere in the schema, which meant every
  age-dependent rule — chat defaults, discoverability, purchasing, leaderboard
  identity — was unimplementable rather than merely unimplemented.

  ## Why year and month, and never the day

  A full date of birth is more personal information than any of these rules
  need. Every question the product asks is a threshold question ("is this
  account under 13, under its country's digital-consent age, under 18"), and
  year plus month answers all of them. Storing the day would add precision
  nothing reads, cannot be rotated after a breach, and is the field Apple's
  Kids Category rules name explicitly among data that may not be passed to
  third parties — which is a fair indication of how the platform classifies its
  sensitivity.

  Rolling on the first of the birth month is conservative by up to 30 days: an
  account graduates slightly late rather than slightly early, which is the
  direction to err.

  ## Why `account_class` is stored rather than derived on read

  It is derivable from the other columns, and it is denormalised anyway because
  it is the column that gets filtered on: excluding children from user search,
  from public group listings, from the leaderboard identity path. Those are
  `WHERE` clauses on hot paths, and recomputing a bracket per row to satisfy
  them would be the wrong shape. `Gamend.Accounts.AgePolicy` owns the
  derivation and is the only thing that should write this.

  ## Why every existing row is grandfathered

  `unknown` means "no age answer", and for a new account the safe reading of
  that is "treat as a child". Applied to a live database it would also mean
  every current player loses chat, purchasing and their leaderboard identity on
  deploy, having done nothing — a self-inflicted outage aimed at exactly the
  people already using the product.

  So `grandfathered_at` records a fact rather than a permission: this account
  existed before the age gate did. `AgePolicy` reads it as "unknown, but do not
  restrict yet". The age prompt still reaches these accounts; answering clears
  the grandfathering, and from that point the answer governs.

  The honest cost, recorded here because it is a decision and not an accident:
  a child already playing keeps an unrestricted account until they answer. The
  mitigations that cost nothing are to make the prompt unskippable rather than
  dismissable, and to seed `adult` from a real signal — a linked payment method
  or a past purchase — so the prompt lands mostly on accounts nothing is known
  about.
  """
  use Ecto.Migration

  def up do
    alter table(:users) do
      add :birth_year, :integer
      add :birth_month, :integer
      add :age_country, :string, size: 2
      add :age_method, :string
      add :age_locked_at, :utc_datetime
      add :account_class, :string, default: "unknown", null: false
      add :grandfathered_at, :utc_datetime
    end

    # Written as a literal rather than through the repo: a migration that
    # depends on the application's schemas breaks the first time one of them
    # changes shape underneath it.
    #
    # And a literal rather than CURRENT_TIMESTAMP, which is portable but not
    # unambiguous: in Postgres it returns `timestamptz`, and assigning that to a
    # `timestamp` column casts through the session timezone, so a non-UTC
    # session would shift every stamp. Computing UTC here removes the question.
    # The round-trip is covered by `age_grandfathering_test.exs`.
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second) |> NaiveDateTime.to_string()
    execute("UPDATE users SET grandfathered_at = '#{now}' WHERE grandfathered_at IS NULL")

    # The filter behind "children are not discoverable" — user search, public
    # group listings, leaderboard identity.
    create index(:users, [:account_class])
  end

  def down do
    drop index(:users, [:account_class])

    alter table(:users) do
      remove :birth_year
      remove :birth_month
      remove :age_country
      remove :age_method
      remove :age_locked_at
      remove :account_class
      remove :grandfathered_at
    end
  end
end
