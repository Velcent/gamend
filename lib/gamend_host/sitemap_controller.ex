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

  There is no `<changefreq>` or `<priority>`: Google ignores both outright and
  Bing effectively does, so they were bytes advertising nothing.
  """

  use GamendWeb, :controller

  alias Gamend.Content
  alias GamendWeb.Plugs.LocalePath
  alias GamendWeb.Sitemap.Lastmod
  alias GamendWeb.Sitemap.Source

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
    ctx = context()

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
    |> Enum.flat_map(&entries_for(ctx, &1))
    |> urlset()
    |> then(&send_xml(conn, &1))
  end

  # Everything a URL entry needs that is the same for every URL in the file.
  defp context do
    default = LocalePath.default_locale()
    locales = [default | Enum.reject(LocalePath.hreflang_locales(), &(&1 == default))]

    %{
      manifest: Source.manifest(),
      base_url: base_url(),
      default_locale: default,
      locales: locales,
      url_locales: Map.new(locales, &{&1, LocalePath.url_locale(&1)})
    }
  end

  # One entry per page, or one per locale when the page is translated.
  defp entries_for(ctx, page) do
    lastmod = lastmod_for(ctx, page)

    if LocalePath.localized_path?(page.loc) do
      alternates = alternate_links(ctx, page.loc)

      Enum.map(ctx.locales, fn locale ->
        url_entry(locale_url(ctx, locale, page.loc), lastmod, alternates)
      end)
    else
      [url_entry(ctx.base_url <> page.loc, lastmod, "")]
    end
  end

  # A literal date (blog posts) or the manifest's; nil when untracked.
  defp lastmod_for(_ctx, %{lastmod: lastmod}), do: lastmod
  defp lastmod_for(ctx, %{lastmod_key: key}), do: Lastmod.date(ctx.manifest, key)
  defp lastmod_for(_ctx, _page), do: nil

  # The default locale lives at the clean URL; every other locale is prefixed.
  defp locale_url(ctx, locale, loc) do
    if locale == ctx.default_locale do
      ctx.base_url <> loc
    else
      suffix = if loc == "/", do: "", else: loc
      ctx.base_url <> "/" <> Map.fetch!(ctx.url_locales, locale) <> suffix
    end
  end

  # Built once per page and shared by that page's locale entries — as iodata,
  # so sharing it costs a pointer rather than a copy each time.
  defp alternate_links(ctx, loc) do
    links =
      Enum.map(ctx.locales, fn locale ->
        alternate(Map.fetch!(ctx.url_locales, locale), locale_url(ctx, locale, loc))
      end)

    [Enum.intersperse([alternate("x-default", ctx.base_url <> loc) | links], "\n"), "\n"]
  end

  defp alternate(hreflang, href) do
    [~s(    <xhtml:link rel="alternate" hreflang="), hreflang, ~s(" href="), href, ~s("/>)]
  end

  defp urlset(urls) do
    [
      ~s(<?xml version="1.0" encoding="UTF-8"?>\n),
      ~s(<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9"\n),
      ~s(        xmlns:xhtml="http://www.w3.org/1999/xhtml">\n),
      Enum.intersperse(urls, "\n"),
      "\n</urlset>\n"
    ]
  end

  defp url_entry(loc, lastmod, alternates) do
    ["  <url>\n    <loc>", loc, "</loc>\n", lastmod_tag(lastmod), alternates, "  </url>\n"]
  end

  defp lastmod_tag(nil), do: ""
  defp lastmod_tag(lastmod), do: "    <lastmod>#{lastmod}</lastmod>\n"

  defp base_url, do: String.trim_trailing(GamendWeb.endpoint().url(), "/")

  defp send_xml(conn, xml) do
    conn
    |> put_resp_content_type("application/xml")
    |> send_resp(200, xml)
  end
end
