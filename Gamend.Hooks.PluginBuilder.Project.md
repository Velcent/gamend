# `Gamend.Hooks.PluginBuilder.Project`
[🔗](https://github.com/appsinacup/gamend/blob/v1.0.7/lib/gamend/hooks/plugin_builder/project.ex#L1)

What a plugin's `mix.exs` declares, read without evaluating it.

The in-process build (`Gamend.Hooks.PluginBuilder.InProcess`) runs inside
the server, so the project file is parsed with `Code.string_to_quoted/2` and
only literal values are taken from it: `app`, `version`, `description` and
`elixirc_paths` from `project/0`; `extra_applications`, `applications`,
`env` and `mod` from `application/0`; and the name and options of each
entry in `deps`.

"Literal" includes what a mix.exs usually spells indirectly: a module
attribute (`version: @version`), a local function returning a literal
(`deps: deps()`, `elixirc_paths: elixirc_paths(Mix.env())`, resolved as
`:prod`), and `System.get_env("X") || @version`, which reads the right-hand
side. Anything else is left at its fallback and named in `warnings`:
app = the directory name, version `"0.0.0"`, elixirc_paths `["lib"]`.

# `dep`

```elixir
@type dep() :: %{
  name: atom(),
  runtime?: boolean(),
  optional?: boolean(),
  prod?: boolean()
}
```

# `t`

```elixir
@type t() :: %Gamend.Hooks.PluginBuilder.Project{
  app: atom(),
  applications: [atom()] | nil,
  deps: [dep()],
  description: String.t() | nil,
  elixirc_paths: [String.t()],
  env: keyword(),
  extra_applications: [atom()],
  hooks_module: module() | nil,
  mod: {module(), term()} | nil,
  version: String.t(),
  warnings: [String.t()]
}
```

# `read`

```elixir
@spec read(Path.t()) :: {:ok, t()} | {:error, String.t()}
```

Reads `<plugin_dir>/mix.exs`. The app name falls back to the directory's
basename.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
