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
        %{"drafting" => "Picking teams", "post_game" => "Scoreboard"}
      end

  Declaring is optional — a game that says nothing simply uses the defaults.
  A state is a word, not a lifecycle: core attaches no meaning to any of them,
  including whether one ends the lobby. A game that finishes a match deletes
  the lobby itself; retention only reaps lobbies everyone has gone quiet in.
  """

  alias GameServer.Hooks.Declarations

  @initial "created"

  @core %{
    "created" => "Lobby exists; core sets this on creation",
    "starting" => "Match is being set up (countdown, loading)",
    "playing" => "Match is running",
    "ended" => "Match finished"
  }

  @doc "The state core assigns when a lobby is created."
  @spec initial() :: String.t()
  def initial, do: @initial

  @doc "Core's default vocabulary, mapped to each state's description."
  @spec core() :: %{String.t() => String.t()}
  def core, do: @core

  @doc "Core defaults plus every plugin-declared state."
  @spec all() :: %{String.t() => String.t()}
  def all, do: Map.merge(@core, Declarations.lobby_states())

  @doc "True when `state` is a core default or declared by a loaded plugin."
  @spec known?(term()) :: boolean()
  def known?(state) when is_binary(state), do: Map.has_key?(all(), state)
  def known?(_state), do: false
end
