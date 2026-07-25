defmodule GameServer.Lobbies.States do
  @moduledoc """
  The vocabulary a lobby's `state` may use.

  Core does not model a state *machine* — it does not know when a match starts,
  ends, drafts, pauses or goes to overtime. It knows a lobby was created, and
  nothing more. So the values below are a documented default vocabulary, not an
  enum, and any state may follow any other; a game that needs ordering enforces
  it in `before_lobby_state_change`.

  Games add their own by exporting `lobby_states/0` (see
  `GameServer.Hooks.Declarations`), which merge with the core defaults:

      def lobby_states do
        %{
          "drafting" => %{description: "Picking teams"},
          "post_game" => %{description: "Scoreboard", terminal: true, prune_after_minutes: 10}
        }
      end

  Declaring is optional — a game that says nothing simply uses the defaults.
  `terminal`/`prune_after_minutes` are read by lobby retention (see
  docs/specs/lobby-state.md); they have no other effect.
  """

  alias GameServer.Hooks.Declarations

  @initial "created"

  @core %{
    "created" => %{description: "Lobby exists; core sets this on creation"},
    "starting" => %{description: "Match is being set up (countdown, loading)"},
    "playing" => %{description: "Match is running"},
    "ended" => %{description: "Match finished", terminal: true}
  }

  @doc "The state core assigns when a lobby is created."
  @spec initial() :: String.t()
  def initial, do: @initial

  @doc "Core's default vocabulary, mapped to its metadata."
  @spec core() :: %{String.t() => map()}
  def core, do: @core

  @doc "Core defaults plus every plugin-declared state."
  @spec all() :: %{String.t() => map()}
  def all, do: Map.merge(@core, Declarations.lobby_states())

  @doc "True when `state` is a core default or declared by a loaded plugin."
  @spec known?(term()) :: boolean()
  def known?(state) when is_binary(state), do: Map.has_key?(all(), state)
  def known?(_state), do: false

  @doc """
  States that end a lobby's life, mapped to their metadata. Lobby retention
  consumes this; nothing else in core reads it.
  """
  @spec terminal() :: %{String.t() => map()}
  def terminal do
    all() |> Enum.filter(fn {_state, meta} -> meta[:terminal] end) |> Map.new()
  end
end
