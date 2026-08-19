defmodule Gamend.Repo.Migrations.CreateClientSessions do
  use Ecto.Migration

  # The index over client-side logs. One row per run of the game, not one per
  # log line: the lines themselves go to `Logger` and out to whatever log store
  # the host runs (stdout, a file, an aggregator), where they sit next to the
  # server lines they need to be read against. This table is what makes them
  # findable — which sessions errored, on which build, in which lobbies.
  #
  # Keeping bodies out of the database is the whole point. A log store indexes
  # and compresses them for a fraction of what a row each would cost here, and
  # the merged client+server timeline falls out of putting both in the same
  # stream rather than out of a join.
  def change do
    create table(:client_sessions) do
      # Client-generated UUIDv4, not this table's primary key. The client has
      # to name the session before it can talk to us — the logs worth having
      # are the ones from before login, when there is no user to key on.
      add :client_session_id, :string, null: false

      # Owner, bound on first write and enforced after: a session is claimable
      # once. `user_id` when authenticated, `device_id` when not.
      add :user_id, references(:users, on_delete: :nilify_all)
      add :device_id, :string

      add :platform, :string
      add :app_version, :string
      add :build, :string
      add :locale, :string

      add :started_at, :utc_datetime_usec, null: false
      add :last_seen_at, :utc_datetime_usec, null: false

      add :entry_count, :integer, null: false, default: 0
      add :warn_count, :integer, null: false, default: 0
      add :error_count, :integer, null: false, default: 0

      # Entries the client buffered but never sent: its ring buffer overran, or
      # a batch failed to upload. Derived from gaps in the client's per-session
      # sequence. Without it a lossy session reads as a quiet one.
      add :dropped_count, :integer, null: false, default: 0
      add :max_seq, :integer, null: false, default: 0

      # Exempt from the ordinary retention sweep. Set when a session errors, or
      # by hand when it is worth keeping.
      add :flagged, :boolean, null: false, default: false

      add :meta, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:client_sessions, [:client_session_id])
    create index(:client_sessions, [:user_id])
    create index(:client_sessions, [:device_id])

    # The default landing order (most recent first) and the retention sweep.
    create index(:client_sessions, [:last_seen_at])

    # "Show me the sessions that went wrong" — partial, because the rows that
    # matter are a small minority and a full index would be mostly zeroes.
    create index(:client_sessions, [:last_seen_at],
             where: "error_count > 0",
             name: :client_sessions_errored_index
           )

    # Which lobbies a session touched. A join table rather than an array column
    # on the session: arrays are a Postgres feature, and the engine's default
    # adapter is SQLite, so a `lobby_ids text[]` would have made this table —
    # and every query that unions into it — Postgres-only.
    #
    # It also makes the reverse lookup a plain index scan. Both directions get
    # asked: session -> "which runs was this player in", lobby -> "which
    # clients were in this run", the second being how a server-side lobby
    # timeline finds the client logs that belong beside it.
    #
    # No foreign key on `lobby_id`, matching `lobby_snapshots`: lobbies are
    # deleted long before the logs about them stop being useful.
    create table(:client_session_lobbies) do
      add :client_session_id, :string, null: false
      add :lobby_id, :string, null: false

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create unique_index(:client_session_lobbies, [:client_session_id, :lobby_id])
    create index(:client_session_lobbies, [:lobby_id])
  end
end
