defmodule GamendWeb.RoadmapLive do
  @moduledoc """
  `/roadmap`, rendered from the registered `:roadmap` markdown file.

  See `GamendWeb.ChangelogLive` for why this is no longer a shim looking up a
  host module by name. The page itself is `GamendWeb.ContentPages.roadmap/1`.
  """

  use GamendWeb, :live_view

  alias Gamend.Content

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, gettext("Roadmap"))
     |> assign(:html, Content.roadmap_html())
     |> assign(:changelog_available?, Content.path(:changelog) != nil)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <GamendWeb.ContentPages.roadmap
      flash={@flash}
      current_scope={@current_scope}
      current_path={assigns[:current_path]}
      html={@html}
      changelog_available?={@changelog_available?}
    />
    """
  end
end
