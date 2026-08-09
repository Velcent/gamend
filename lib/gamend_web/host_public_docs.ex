defmodule GamendWeb.HostPublicDocs do
  @moduledoc """
  Renders the guides in `priv/docs`: `/docs/setup` indexes them, `/docs/:slug`
  is one guide.

  A guide is a markdown file and nothing else: the folder gives its category,
  the numeric filename prefix its order, the first heading its title, and
  optional front matter its heroicon. A folder's `_category.md` names the
  category and gives it an icon and a colour, which its guides inherit so each
  section reads as one group. Adding one takes no Elixir change, which is the
  whole point — the previous version of this page carried 9k lines of
  hand-written HEEx for the same content.

  ## Why a page per guide

  All 32 guides used to render on `/docs/setup` as `<details>` sections, with
  the open one in the query string. That gave the whole of the documentation a
  single `<title>`, a single description and a single `<h1>`, so nothing could
  match a query about any one topic — and body text collapsed behind a
  disclosure is weighted down besides. A query parameter does not fix that:
  `?guide=payments` is the same URL to a search engine, which is why those
  links canonicalised back to the index.

  Each guide now owns a URL, with `GamendHost.PageMeta` giving it its own
  title, description and breadcrumbs. The index carries titles and summaries
  only — repeating the bodies there would make every guide duplicate content
  competing with itself.
  """

  use GamendWeb, :live_view

  alias Gamend.Content

  @impl true
  def render(%{live_action: :show} = assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={assigns[:current_path]}>
      <article class="space-y-6">
        <div>
          <.link navigate={~p"/docs/setup"} class="text-sm text-base-content/60 hover:underline">
            &larr; {gettext("All guides")}
          </.link>
          <p class="mt-2 text-sm uppercase tracking-[0.24em] flex items-center gap-2">
            <.icon name={@category.icon} class={"size-4 #{@category.color}"} />
            {@category.category}
          </p>
        </div>

        <.header>
          <h1 class="text-3xl font-bold flex items-center gap-3">
            <.icon name={@guide.icon} class={"size-7 shrink-0 opacity-80 #{@category.color}"} />
            {@guide.title}
          </h1>
        </.header>

        <div class="markdown-content">
          {raw(Content.doc_html(@guide.slug))}
        </div>

        <nav :if={@siblings != []} class="border-t border-base-300/60 pt-6 space-y-2">
          <h2 class="font-semibold uppercase tracking-[0.24em] text-sm">
            {gettext("More in %{category}", category: @category.category)}
          </h2>
          <ul class="space-y-1">
            <li :for={sibling <- @siblings}>
              <.link navigate={~p"/docs/#{sibling.slug}"} class="link link-hover">
                {sibling.title}
              </.link>
            </li>
          </ul>
        </nav>
      </article>
    </Layouts.app>
    """
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={assigns[:current_path]}>
      <div class="space-y-6">
        <.header>
          <h1 class="text-3xl font-bold">{gettext("Setup & Guides")}</h1>
          <:subtitle>
            {gettext("Platform setup, OAuth providers, payments, email, and server hooks")}
          </:subtitle>
        </.header>

        <p :if={@categories == []} class="text-base-content/60">
          {gettext("No guides found.")}
        </p>

        <section :for={category <- @categories} class="space-y-2">
          <h2 class="font-semibold uppercase tracking-[0.24em] border-t border-base-300/60 pt-6 flex items-center gap-2">
            <.icon name={category.icon} class={"size-5 #{category.color}"} />
            {category.category}
          </h2>

          <.link
            :for={guide <- category.guides}
            navigate={~p"/docs/#{guide.slug}"}
            class="card bg-base-100 shadow-sm hover:shadow-md transition-shadow block"
          >
            <div class="card-body py-4 flex-row items-center gap-3">
              <.icon name={guide.icon} class={"size-6 shrink-0 opacity-80 #{category.color}"} />
              <span class="card-title text-xl shrink-0">{guide.title}</span>
              <span class="text-sm text-base-content/50 grow line-clamp-1">{guide.summary}</span>
              <.icon name="hero-chevron-right" class="size-4 shrink-0" />
            </div>
          </.link>
        </section>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, :categories, Content.list_doc_categories())}
  end

  @impl true
  def handle_params(%{"slug" => slug}, _uri, socket) do
    case Content.get_doc(slug) do
      nil ->
        raise GamendWeb.NotFoundError

      guide ->
        # By membership, not by name: a guide's `:category` is the folder
        # ("10-setup") while the category's is its display title ("Setup").
        category =
          Enum.find(socket.assigns.categories, fn category ->
            Enum.any?(category.guides, &(&1.slug == slug))
          end)

        {:noreply,
         socket
         |> assign(:page_title, guide.title)
         |> assign(:guide, guide)
         |> assign(:category, category)
         |> assign(:siblings, Enum.reject(category.guides, &(&1.slug == slug)))}
    end
  end

  # `?guide=` is how the old single-page version deep-linked a section. Those
  # links are in blog posts and chat history, so they move to the guide's own
  # URL rather than silently landing on the index.
  def handle_params(%{"guide" => slug}, _uri, socket) do
    if Content.get_doc(slug) do
      {:noreply, push_navigate(socket, to: ~p"/docs/#{slug}")}
    else
      {:noreply, assign(socket, :page_title, gettext("Documentation"))}
    end
  end

  def handle_params(_params, _uri, socket) do
    {:noreply, assign(socket, :page_title, gettext("Documentation"))}
  end
end
