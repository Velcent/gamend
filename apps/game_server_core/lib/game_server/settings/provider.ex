defmodule GameServer.Settings.Provider do
  @moduledoc """
  Declares a group of settings on a module.

      defmodule GameServer.Retention do
        use GameServer.Settings.Provider,
          app: :game_server_core,
          group: :retention,
          label: "Retention"

        setting :chat_messages_days, :integer,
          default: 0,
          doc: "Delete chat messages older than N days. 0 keeps forever."
      end

  The declaration is the only place a setting is written down. Its environment
  variable name is **derived** — `<ROOT>_<GROUP>_<KEY>`, e.g.
  `GAMEND_RETENTION_CHAT_MESSAGES_DAYS` — so the key and its env var can never
  disagree. Pass `env:` only for the handful of names other software owns
  (`PORT`, `DATABASE_URL`), which should also carry `external: true`.

  Values are read back with `GameServer.Settings.get/2`, which checks
  `Application.get_env(app, module)` and falls back to the compiled default. A
  host configures them the ordinary Elixir way and never needs an env var:

      config :game_server_core, GameServer.Retention, chat_messages_days: 90

  ## Options for `use`

  - `:app` (required) — the OTP app the values live under.
  - `:group` (required) — the middle segment of the env name, and the grouping
    the admin viewer renders. One word.
  - `:root` — first segment of the env name. Defaults to `"GAMEND"`; a plugin
    passes its own (`root: "POLYGLOT"`).
  - `:label` — display name for the group. Defaults to a capitalised `:group`.
  - `:env_prefix` — replaces the derived `<ROOT>_<GROUP>_` prefix for every
    setting in the provider, so `LIMIT_MAX_PAGE_SIZE` can keep its name while
    the group is `:limits`. A transitional escape hatch for names that predate
    the convention; a per-setting `env:` still wins over it.

  ## Options for `setting/3`

  - `:default` — the compiled default. Defaults to `nil`.
  - `:doc` — one-line description, shown in the admin viewer and generated docs.
  - `:secret` — mask the value everywhere it is displayed.
  - `:required` — `:prod` (boot fails in prod, warns in dev) or `:warn` (logs in
    prod). Omit for optional. Never enforced in test.
  - `:when` — `{path, value}` gating the requirement on another setting, e.g.
    `when: {[:storage, :adapter], :s3}`. A list of such tuples requires all of
    them to hold.
  - `:with` — sibling keys forming a complete-or-empty group. All unset is
    silent; a partial set trips `:required`.
  - `:env` — override the derived env var name. For inherited names only.
  - `:external` — this name belongs to other software; the viewer files it
    under "Inherited" rather than implying we own it.
  """

  @types [:string, :integer, :float, :boolean, :atom, :list, :log_level]

  @setting_opts [:default, :doc, :secret, :required, :when, :with, :env, :external]

  @doc false
  defmacro __using__(opts) do
    app = Keyword.fetch!(opts, :app)
    group = Keyword.fetch!(opts, :group)
    root = Keyword.get(opts, :root, "GAMEND")
    label = Keyword.get(opts, :label) || group |> to_string() |> String.capitalize()
    env_prefix = Keyword.get(opts, :env_prefix)

    quote do
      import GameServer.Settings.Provider, only: [setting: 2, setting: 3]

      Module.register_attribute(__MODULE__, :gamend_settings, accumulate: true)

      @gamend_settings_app unquote(app)
      @gamend_settings_group unquote(group)
      @gamend_settings_root unquote(root)
      @gamend_settings_label unquote(label)
      @gamend_settings_env_prefix unquote(env_prefix)

      @before_compile GameServer.Settings.Provider
    end
  end

  @doc """
  Declares one setting. See the module doc for the accepted options.
  """
  defmacro setting(key, type, opts \\ []) do
    quote do
      @gamend_settings {unquote(key), unquote(type), unquote(opts)}
    end
  end

  @doc false
  defmacro __before_compile__(env) do
    module = env.module
    app = Module.get_attribute(module, :gamend_settings_app)
    group = Module.get_attribute(module, :gamend_settings_group)
    root = Module.get_attribute(module, :gamend_settings_root)
    label = Module.get_attribute(module, :gamend_settings_label)
    env_prefix = Module.get_attribute(module, :gamend_settings_env_prefix)

    context = %{
      module: module,
      app: app,
      group: group,
      root: root,
      label: label,
      env_prefix: env_prefix
    }

    definitions =
      module
      |> Module.get_attribute(:gamend_settings)
      |> Enum.reverse()
      |> Enum.map(&build(&1, context))

    validate_unique_keys!(definitions, module)
    validate_with_targets!(definitions, module)

    quote do
      @doc false
      def __settings__, do: unquote(Macro.escape(definitions))
    end
  end

  defp build({key, type, opts}, context) do
    %{module: module, app: app, group: group, root: root, label: label} = context

    unless type in @types do
      raise ArgumentError,
            "#{inspect(module)}: setting #{inspect(key)} has unknown type #{inspect(type)}; " <>
              "expected one of #{inspect(@types)}"
    end

    case Keyword.keys(opts) -- @setting_opts do
      [] -> :ok
      unknown -> raise ArgumentError, "#{inspect(module)}: setting #{inspect(key)} has unknown \
option(s) #{inspect(unknown)}; expected one of #{inspect(@setting_opts)}"
    end

    required = Keyword.get(opts, :required)

    unless required in [nil, :prod, :warn] do
      raise ArgumentError,
            "#{inspect(module)}: setting #{inspect(key)} has required: #{inspect(required)}; " <>
              "expected :prod, :warn, or omitted"
    end

    %{
      key: key,
      module: module,
      app: app,
      group: group,
      label: label,
      type: type,
      default: Keyword.get(opts, :default),
      env: Keyword.get(opts, :env) || derive_env(root, group, key, context.env_prefix),
      doc: Keyword.get(opts, :doc, ""),
      secret: Keyword.get(opts, :secret, false),
      external: Keyword.get(opts, :external, false),
      required: required,
      when: Keyword.get(opts, :when),
      with: Keyword.get(opts, :with, [])
    }
  end

  @doc """
  The environment variable name for a group and key: `<ROOT>_<GROUP>_<KEY>`.

  A provider-level `env_prefix` replaces the `<ROOT>_<GROUP>_` part.
  """
  @spec derive_env(String.t(), atom(), atom(), String.t() | nil) :: String.t()
  def derive_env(root, group, key, env_prefix \\ nil)

  def derive_env(_root, _group, key, env_prefix) when is_binary(env_prefix) do
    env_prefix <> String.upcase(to_string(key))
  end

  def derive_env(root, group, key, nil) do
    [root, to_string(group), to_string(key)]
    |> Enum.map_join("_", &String.upcase/1)
  end

  defp validate_unique_keys!(definitions, module) do
    duplicates =
      definitions
      |> Enum.frequencies_by(& &1.key)
      |> Enum.filter(fn {_key, count} -> count > 1 end)
      |> Enum.map(&elem(&1, 0))

    if duplicates != [] do
      raise ArgumentError, "#{inspect(module)}: duplicate setting(s) #{inspect(duplicates)}"
    end
  end

  # A `with:` naming a key that does not exist would silently never trip, which
  # is the opposite of what a completeness check is for.
  defp validate_with_targets!(definitions, module) do
    declared = MapSet.new(definitions, & &1.key)

    for definition <- definitions, sibling <- definition.with, sibling not in declared do
      raise ArgumentError,
            "#{inspect(module)}: setting #{inspect(definition.key)} lists #{inspect(sibling)} " <>
              "in :with, but no such setting is declared"
    end

    :ok
  end
end
