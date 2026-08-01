defmodule GamendWeb.StatsLive do
  @moduledoc """
  Public server activity page — the browser view of the `/<resource>/stats`
  endpoints.

  Anonymous like the endpoints it mirrors, and gated by the same
  `:public_stats` flag, so turning stats off closes the page and the API
  together rather than leaving a second way in.

  Rendered once on mount. The numbers come from the contexts' cached snapshots,
  so live-updating would mostly re-render identical values — a page reload is
  the refresh.
  """
  use GamendWeb, :live_view

  alias Gamend.Accounts
  alias Gamend.Lobbies
  alias Gamend.Matchmaking
  alias Gamend.Parties
  alias Gamend.Quests
  alias Gamend.Signaling
  alias GamendWeb.Plugs.FeatureGate

  @impl true
  def mount(_params, _session, socket) do
    unless FeatureGate.enabled?(:public_stats) do
      raise GamendWeb.NotFoundError
    end

    {:ok,
     socket
     |> assign(:page_title, gettext("Server stats"))
     |> assign(:players, Accounts.player_stats())
     |> assign(:lobbies, Lobbies.stats())
     |> assign(:parties, Parties.stats())
     |> assign(:quests, Quests.stats())
     |> assign(:signaling, Signaling.stats())
     |> assign(:matchmaking, Matchmaking.stats())}
  end

  attr :title, :string, required: true
  attr :icon, :string, required: true
  slot :inner_block, required: true

  defp section(assigns) do
    ~H"""
    <div>
      <h2 class="mb-2 flex items-center gap-2 text-xl font-semibold">
        <.icon name={@icon} class="size-5 text-base-content/60" />
        {@title}
      </h2>
      {render_slot(@inner_block)}
    </div>
    """
  end

  attr :title, :string, required: true
  attr :value, :integer, required: true
  attr :desc, :string, default: nil

  defp stat(assigns) do
    ~H"""
    <div class="stat">
      <div class="stat-title">{@title}</div>
      <div class="stat-value">{@value}</div>
      <div :if={@desc} class="stat-desc">{@desc}</div>
    </div>
    """
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={assigns[:current_path]}>
      <div class="space-y-6">
        <div>
          <h1 class="text-3xl font-bold">{gettext("Server stats")}</h1>
        </div>

        <.section title={gettext("Players")} icon="hero-users-solid">
          <div class="stats stats-vertical sm:stats-horizontal shadow bg-base-200 w-full">
            <.stat title={gettext("Online")} value={@players.players_online} />
            <.stat title={gettext("Total")} value={@players.players_total} />
            <.stat title={gettext("In lobbies")} value={@players.players_in_lobbies} />
            <.stat title={gettext("In parties")} value={@players.players_in_parties} />
          </div>
        </.section>

        <.section title={gettext("Lobbies and parties")} icon="hero-rectangle-group-solid">
          <div class="stats stats-vertical sm:stats-horizontal shadow bg-base-200 w-full">
            <.stat title={gettext("Lobbies")} value={@lobbies.lobbies_total} />
            <.stat title={gettext("Spectators")} value={@lobbies.spectators} />
            <.stat title={gettext("Parties")} value={@parties.parties_active} />
            <.stat
              title={gettext("In queue")}
              value={@matchmaking.queued}
              desc={gettext("waiting for a match")}
            />
          </div>

          <div :if={@lobbies.by_state != %{}} class="mt-3 flex flex-wrap gap-2">
            <span :for={{state, count} <- Enum.sort(@lobbies.by_state)} class="badge badge-outline">
              {state}: {count}
            </span>
          </div>
        </.section>

        <.section title={gettext("WebRTC")} icon="hero-signal-solid">
          <div class="stats stats-vertical sm:stats-horizontal shadow bg-base-200 w-full">
            <.stat title={gettext("Rooms enabled")} value={@signaling.rooms_enabled} />
            <.stat title={gettext("Rooms in use")} value={@signaling.rooms_active} />
            <.stat title={gettext("Peers connected")} value={@signaling.peers_connected} />
          </div>
        </.section>

        <.section title={gettext("Quests")} icon="hero-trophy-solid">
          <div class="stats stats-vertical sm:stats-horizontal shadow bg-base-200 w-full">
            <.stat title={gettext("Quests")} value={@quests.quests_total} />
            <.stat title={gettext("Completed")} value={@quests.completed} />
            <.stat title={gettext("Claimed")} value={@quests.claimed} />
          </div>
        </.section>
      </div>
    </Layouts.app>
    """
  end
end
