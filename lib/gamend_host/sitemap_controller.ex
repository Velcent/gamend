defmodule GamendHost.SitemapController do
  @moduledoc """
  Host-owned `sitemap.xml` controller.

  Edit `@static_pages` here to advertise host-specific public pages such as
  custom docs, landing pages, or host-only routes.

  Pages that `GamendWeb.Plugs.LocalePath` serves under a locale prefix get one
  `<url>` entry per locale, each carrying the full `xhtml:link` alternate set.
  That is what tells Google the translations exist and are equivalent, rather
  than competing duplicates. Pages outside that list — `/docs/setup`, and the
  blog posts, whose bodies are English-only markdown — get a single entry.

  ## Dates

  `<lastmod>` comes from `GamendHost.Sitemap.Source` via the manifest, so it
  reflects when the words on a page last changed rather than when a file was
  touched. Blog posts carry their own front-matter date and use it directly.

  The XML itself — the `<urlset>`, the per-locale entries and their `xhtml:link`
  alternates — is `GamendWeb.Sitemap.Xml`. Only the page list is here.
  """

  use GamendWeb, :controller

  alias Gamend.Content
  alias GamendWeb.Sitemap.Xml

  # `/users/register` and `/users/log_in` are deliberately absent. They are
  # blocked in robots.txt as account surfaces, and a sitemap entry for a page
  # we ask crawlers not to fetch is a contradiction that shows up in Search
  # Console as "Submitted URL blocked by robots.txt".
  @static_pages [
    %{loc: "/"},
    %{loc: "/blog"},
    %{loc: "/changelog", lastmod_key: "changelog"},
    %{loc: "/roadmap", lastmod_key: "roadmap"},
    %{loc: "/docs/setup", lastmod_key: "docs"},
    %{loc: "/privacy"},
    %{loc: "/terms"},
    %{loc: "/data_deletion"}
  ]

  def index(conn, _params) do
    ctx = Xml.context()

    blog_posts =
      Enum.map(Content.list_blog_posts(), fn post ->
        %{loc: "/blog/#{post.slug}", lastmod: Date.to_iso8601(post.date)}
      end)

    # One entry per guide. These are the pages with a topic specific enough to
    # match a query, so leaving them out of the sitemap was leaving out most of
    # what this site has to offer a search engine.
    guides =
      Enum.map(Content.list_docs(), fn doc ->
        %{loc: "/docs/#{doc.slug}", lastmod_key: "docs/#{doc.slug}"}
      end)

    (@static_pages ++ guides ++ blog_posts)
    |> Enum.flat_map(&Xml.entries_for(ctx, &1))
    |> Xml.urlset()
    |> then(&send_xml(conn, &1))
  end

  defp send_xml(conn, xml) do
    conn
    |> put_resp_content_type("application/xml")
    |> send_resp(200, xml)
  end
end
