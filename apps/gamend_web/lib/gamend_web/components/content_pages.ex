defmodule GamendWeb.ContentPages do
  @moduledoc """
  The changelog and roadmap pages: one markup, two rendering styles.

  ## Why components rather than one LiveView

  gamend serves these as LiveViews; Polyglot Pirates serves them from a plain
  controller, because a changelog has nothing live on it and a dead render is
  one less socket. Both are defensible, and neither host should have to change
  to share the page — so what is shared is the *markup*, which a LiveView's
  `render/1` and a `.html.heex` template can both call.

  The three copies that existed before this said the same thing in three
  slightly different ways, and the differences were all accidents: gamend's
  `page_title` was an untranslated string and its empty-state body was an
  English literal, while Polyglot's had a card around the article and a
  reusable empty state. Nothing chose any of that; one was written after the
  other.

  ## `href`, not `navigate`

  The cross-links between the two pages are plain anchors. `navigate` needs a
  LiveView root to push into, and on a controller-rendered page there is none —
  it would render an `<a>` that the client script treats as live and the server
  has nowhere to route. These are static documents where a full navigation is
  what happens anyway.
  """

  use GamendWeb, :html

  attr :flash, :map, required: true
  attr :current_scope, :any, default: nil
  attr :current_path, :string, default: nil
  attr :html, :string, default: nil
  attr :roadmap_available?, :boolean, default: false

  @doc "The changelog page, with a link across to the roadmap when there is one."
  def changelog(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={@current_path}>
      <.content_page
        title={gettext("Changelog")}
        html={@html}
        sibling_path={@roadmap_available? && ~p"/roadmap"}
        sibling_icon="hero-map"
        sibling_label={gettext("Roadmap")}
        empty_icon="hero-document-text"
        empty_text={gettext("Add a changelog file at CHANGELOG.md to display it here.")}
      />
    </Layouts.app>
    """
  end

  attr :flash, :map, required: true
  attr :current_scope, :any, default: nil
  attr :current_path, :string, default: nil
  attr :html, :string, default: nil
  attr :changelog_available?, :boolean, default: false

  @doc "The roadmap page, with a link across to the changelog when there is one."
  def roadmap(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={@current_path}>
      <.content_page
        title={gettext("Roadmap")}
        html={@html}
        sibling_path={@changelog_available? && ~p"/changelog"}
        sibling_icon="hero-document-text"
        sibling_label={gettext("Changelog")}
        empty_icon="hero-map"
        empty_text={gettext("Add a roadmap file at ROADMAP.md to display it here.")}
      />
    </Layouts.app>
    """
  end

  attr :title, :string, required: true
  attr :html, :string, default: nil
  attr :sibling_path, :any, default: nil
  attr :sibling_icon, :string, required: true
  attr :sibling_label, :string, required: true
  attr :empty_icon, :string, required: true
  attr :empty_text, :string, required: true

  # The two pages differ only in their copy and which way the cross-link
  # points, so the shape is written once. `sibling_path` is false rather than
  # nil when the other page has no file, which `:if` reads the same way.
  defp content_page(assigns) do
    ~H"""
    <div class="space-y-6">
      <div class="flex flex-row items-center justify-between gap-3">
        <h1 class="text-4xl font-black text-base-content/95">{@title}</h1>

        <.link :if={@sibling_path} href={@sibling_path} class="btn btn-outline btn-sm">
          <.icon name={@sibling_icon} class="size-4" />
          {@sibling_label}
        </.link>
      </div>

      <section
        :if={@html}
        class="rounded-3xl border border-base-300 bg-base-100/90 p-5 shadow-sm sm:p-8"
      >
        <article class="markdown-content">{raw(@html)}</article>
      </section>

      <.empty_state :if={!@html} icon={@empty_icon} title={gettext("No results.")} text={@empty_text} />
    </div>
    """
  end
end
