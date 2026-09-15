defmodule GamendHost.Search do
  @moduledoc """
  What the site search palette finds on this host.

  Core owns the palette — the button, the dialog, the ranking, the keyboard —
  and this owns the catalogue. Everything here is derived from the same
  `Gamend.Content` collections the pages themselves render from, so a guide or
  a post cannot exist on the site and be missing from search.

  The navigation comes first because `GamendWeb.SearchIndex` dedupes by href
  and keeps the first row it saw: `/blog` is the nav's own link, not a post
  that happens to share the path.

  Only destinations, no query actions: every answerable thing on this host is
  a page, and a page is small enough to send in the index. A host whose
  content is too large to enumerate — a dictionary, a product catalogue —
  implements `c:GamendWeb.SearchIndex.Provider.search/2` as well.
  """

  @behaviour GamendWeb.SearchIndex.Provider

  use Gettext, backend: GamendHost.Gettext

  alias Gamend.Content
  alias GamendWeb.SearchIndex

  @impl true
  def entries(context) do
    SearchIndex.navigation_entries(context) ++ doc_entries() ++ blog_entries()
  end

  # One heading for every guide rather than one per category. A category title
  # comes from its `_category.md` and is English only, so seven of them would
  # put seven untranslated headings in a palette whose every other heading is
  # translated. The category is not lost — it rides along as a keyword, so
  # "monetization" still finds the guides under it without being printed on
  # each row.
  defp doc_entries do
    group = gettext("Documentation")

    Enum.flat_map(Content.list_doc_categories(), fn %{category: category, guides: guides} ->
      Enum.map(guides, fn doc ->
        %{
          title: doc.title,
          href: "/docs/#{doc.slug}",
          group: group,
          subtitle: doc.summary,
          keywords: [category]
        }
      end)
    end)
  end

  # The date and not the excerpt: the subtitle is the truncated right-hand half
  # of a row, and half of a first sentence tells a reader less than knowing
  # which post is the recent one.
  defp blog_entries do
    group = gettext("Blog")

    Enum.map(Content.list_blog_posts(), fn post ->
      %{title: post.title, href: "/blog/#{post.slug}", group: group, subtitle: blog_date(post)}
    end)
  end

  defp blog_date(%{date: %Date{} = date}), do: Date.to_iso8601(date)
  defp blog_date(_post), do: nil
end
