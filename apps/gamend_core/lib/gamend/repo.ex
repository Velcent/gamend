defmodule Gamend.Repo do
  # The adapter must be present at compile time for Ecto.Repo's supervisor
  # initialization. Read the adapter from the application configuration
  # (config/config.exs and environment-specific files). This keeps the
  # logic out of the module and avoids reading System.env directly here.

  # Use compile-time access so the adapter selection is fixed at compile time
  # and picked up from the config files.
  repo_conf = Application.compile_env(:gamend_core, __MODULE__, []) || []
  @adapter Keyword.get(repo_conf, :adapter, Ecto.Adapters.SQLite3)

  use Ecto.Repo,
    otp_app: :gamend_core,
    adapter: @adapter

  # All tables use UUID (v7) primary/foreign keys — see Gamend.UUIDv7.
  # Set here (not only in config files) so host repos that configure the Repo
  # themselves still get binary_id migrations.
  @impl true
  def init(_type, config) do
    {:ok,
     config
     |> Keyword.put_new(:migration_primary_key, name: :id, type: :binary_id)
     |> Keyword.put_new(:migration_foreign_key, type: :binary_id)}
  end

  @doc """
  Run `fun` in a transaction whose commit is on disk before it returns.

  `db.postgres_synchronous_commit` is an app-wide durability choice, and `off`
  is a reasonable one for game data: an OS crash loses a few hundred
  milliseconds of commits, nothing is corrupted, and a player re-earns a
  little progress. That trade is wrong for money — a purchase the provider has
  already charged for must not be the thing that disappears.

  `SET LOCAL` raises `synchronous_commit` back to `on` for this transaction
  only, so payments stay durable whatever the global setting is, and every
  other write keeps the faster commit. It costs one fsync per payment, which
  is not a path that needs throughput.

  A no-op on SQLite: durability there is `db.sqlite_synchronous`, a
  connection-wide pragma with no per-transaction override.
  """
  @spec durable_transaction((-> result), keyword()) :: {:ok, result} | {:error, term()}
        when result: term()
  def durable_transaction(fun, opts \\ []) when is_function(fun, 0) do
    transaction(
      fn ->
        if postgres?() do
          query!("SET LOCAL synchronous_commit = on", [])
        end

        fun.()
      end,
      opts
    )
  end

  # Built at runtime rather than compared against the compile-time constant:
  # when SQLite is the compiled adapter, Elixir's type checker folds a literal
  # comparison to `false` and warns on the branch below it.
  defp postgres? do
    __adapter__() == Module.concat([Ecto, Adapters, Postgres])
  end

  @doc ~S"""
  Escapes `LIKE` wildcards (`%`, `_`) and the escape character (`\`) in
  user-supplied search input so it matches literally.

  Queries must pair the escaped pattern with an explicit escape clause,
  because SQLite (unlike Postgres) has no default `LIKE` escape character:

      fragment("? LIKE ? ESCAPE '\\'", u.name, ^("%" <> Repo.escape_like(term) <> "%"))
  """
  @spec escape_like(String.t()) :: String.t()
  def escape_like(str) when is_binary(str) do
    str
    |> String.replace("\\", "\\\\")
    |> String.replace("%", "\\%")
    |> String.replace("_", "\\_")
  end

  @doc ~S"""
  Builds a case-insensitive "contains" `LIKE` pattern from user search input,
  or `nil` when the input is blank and the caller should not filter at all.

  Pair it with a lowercased column so both adapters agree on case:

      fragment("lower(coalesce(?, '')) LIKE ? ESCAPE '\\'", u.username, ^pattern)
  """
  @spec search_pattern(term()) :: String.t() | nil
  def search_pattern(term) when is_binary(term) do
    case term |> String.trim() |> String.downcase() do
      "" -> nil
      normalized -> "%" <> escape_like(normalized) <> "%"
    end
  end

  def search_pattern(_term), do: nil

  @doc """
  Like `get/3`, but returns `nil` (instead of raising `Ecto.Query.CastError`)
  when `id` is not a valid UUID. Use for lookups whose id comes from external
  input (URL params, channel payloads, hook args).
  """
  @spec get_uuid(Ecto.Queryable.t(), term(), Keyword.t()) :: Ecto.Schema.t() | nil
  def get_uuid(queryable, id, opts \\ []) do
    case Ecto.UUID.cast(id) do
      {:ok, uuid} -> get(queryable, uuid, opts)
      :error -> nil
    end
  end

  @doc """
  Like `get!/3`, but raises `Ecto.NoResultsError` (instead of
  `Ecto.Query.CastError`) when `id` is not a valid UUID, so invalid ids from
  external input surface as 404s rather than 400s.
  """
  @spec get_uuid!(Ecto.Queryable.t(), term(), Keyword.t()) :: Ecto.Schema.t()
  def get_uuid!(queryable, id, opts \\ []) do
    case Ecto.UUID.cast(id) do
      {:ok, uuid} -> get!(queryable, uuid, opts)
      :error -> raise Ecto.NoResultsError, queryable: queryable
    end
  end
end
