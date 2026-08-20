defmodule GamendWeb.Sitemap.Xml do
  @moduledoc """
  Rendering a `<urlset>` or a `<sitemapindex>`: the parts no host varies.

  `GamendWeb.Sitemap.Source` says which pages exist and `GamendWeb.Sitemap.Lastmod`
  says when they changed; this turns the answers into bytes. Which pages, and
  where their dates come from, stay the host's — this owns the XML, the
  hreflang alternates and the locale URL shape, which are the sitemaps protocol
  rather than anybody's content.

  Both hosts had a byte-identical copy of every function here. They were not
  even a fork: the second was pasted from the first and then both were edited.

  ## Iodata throughout

  A large sitemap is ~5,000 URLs and ~19 MB, 90% of it the alternate set every
  URL carries. Nothing is joined into a binary on the way out — `alternate_links/2`
  is built once per page and shared by that page's 30 locale entries as a
  pointer rather than a 3 KB copy each time, and `Plug.Conn.send_resp/3` takes
  the nested list directly.

  ## What is not here

  No `<changefreq>` and no `<priority>`: Google ignores both outright and Bing
  effectively does, so they were bytes advertising nothing.
  """

  alias GamendWeb.Plugs.LocalePath
  alias GamendWeb.Sitemap.Lastmod
  alias GamendWeb.Sitemap.Source

  @typedoc """
  A page to render. `:loc` is a path, not a URL — the host names the route and
  this prefixes the endpoint.

  Its date comes from `:lastmod` when the page carries a literal one (a blog
  post's front matter), from `:lastmod_key` when the manifest tracks it, and is
  absent otherwise. Absent is a real answer, not a gap to fill: a date derived
  from a file mtime is a lie that costs the whole sitemap its credibility.
  """
  @type page :: %{
          required(:loc) => String.t(),
          optional(:lastmod) => String.t() | nil,
          optional(:lastmod_key) => String.t()
        }

  @doc """
  Everything a URL entry needs that is the same for every URL in the file.

  Read once per sitemap rather than per entry: `Source.manifest/0` stats the
  file on every call and the locale list is rebuilt each time — times 5,000
  URLs × 30 locales, that was the bulk of rendering a large one.

  Options:

    * `:manifest` — a manifest already loaded, when the caller needs it too
    * `:locale_lastmod` — `(own_lastmod, locale -> lastmod)`, for a host whose
      translated pages change on their own schedule. The default returns the
      page's own date for every locale.
    * `:extra` — merged into the returned map, for whatever else the host's
      entry building needs.
  """
  @spec context(keyword()) :: map()
  def context(opts \\ []) do
    default = LocalePath.default_locale()
    locales = locales()

    %{
      manifest: Keyword.get_lazy(opts, :manifest, &Source.manifest/0),
      base_url: base_url(),
      default_locale: default,
      locales: locales,
      url_locales: Map.new(locales, &{&1, LocalePath.url_locale(&1)}),
      locale_lastmod: Keyword.get(opts, :locale_lastmod, fn own, _locale -> own end)
    }
    |> Map.merge(Map.new(Keyword.get(opts, :extra, %{})))
  end

  @doc """
  Every locale a translated page is advertised in, default first.

  Order matters: the default locale owns the clean URL, so it leads and the
  rest follow prefixed. A host that needs the list before it can build a
  context — to precompute something per locale and close over it — calls this
  rather than deriving it again.
  """
  @spec locales() :: [String.t()]
  def locales do
    default = LocalePath.default_locale()

    [default | Enum.reject(LocalePath.hreflang_locales(), &(&1 == default))]
  end

  @doc "The endpoint's URL with any trailing slash removed, so `<> path` is well-formed."
  @spec base_url() :: String.t()
  def base_url, do: String.trim_trailing(GamendWeb.endpoint().url(), "/")

  @doc """
  One `<url>` entry per page, or one per locale when the page is translated.

  Whether a path is translated is `LocalePath.localized_path?/1` — the same
  answer the router gives, so a page cannot be advertised under a prefix that
  does not serve it.
  """
  @spec entries_for(map(), page()) :: [iodata()]
  def entries_for(ctx, page) do
    own = own_lastmod(ctx, page)

    if LocalePath.localized_path?(page.loc) do
      alternates = alternate_links(ctx, page.loc)

      Enum.map(ctx.locales, fn locale ->
        url_entry(
          locale_url(ctx, locale, page.loc),
          ctx.locale_lastmod.(own, locale),
          alternates
        )
      end)
    else
      [url_entry(ctx.base_url <> page.loc, own, "")]
    end
  end

  @doc "A page's own date: a literal one, the manifest's, or none."
  @spec own_lastmod(map(), page()) :: String.t() | nil
  def own_lastmod(_ctx, %{lastmod: lastmod}), do: lastmod
  def own_lastmod(ctx, %{lastmod_key: key}), do: Lastmod.date(ctx.manifest, key)
  def own_lastmod(_ctx, _page), do: nil

  @doc """
  The URL a path has in one locale.

  The default locale lives at the clean URL and every other is prefixed — the
  root is the one path that takes no suffix, or it would render `/fr/`.
  """
  @spec locale_url(map(), String.t(), String.t()) :: String.t()
  def locale_url(ctx, locale, loc) do
    if locale == ctx.default_locale do
      ctx.base_url <> loc
    else
      suffix = if loc == "/", do: "", else: loc
      ctx.base_url <> "/" <> Map.fetch!(ctx.url_locales, locale) <> suffix
    end
  end

  @doc """
  The `xhtml:link` alternate set for one path, as shared iodata.

  Build it once per page, not once per entry: this is the 90%. `x-default`
  points at the clean URL, which is what tells a crawler which one to serve
  when it has no better signal.
  """
  @spec alternate_links(map(), String.t()) :: iodata()
  def alternate_links(ctx, loc) do
    links =
      Enum.map(ctx.locales, fn locale ->
        alternate(Map.fetch!(ctx.url_locales, locale), locale_url(ctx, locale, loc))
      end)

    [Enum.intersperse([alternate("x-default", ctx.base_url <> loc) | links], "\n"), "\n"]
  end

  @doc "One `xhtml:link` alternate."
  @spec alternate(String.t(), String.t()) :: iodata()
  def alternate(hreflang, href) do
    [~s(    <xhtml:link rel="alternate" hreflang="), hreflang, ~s(" href="), href, ~s("/>)]
  end

  @doc "One `<url>` element."
  @spec url_entry(String.t(), String.t() | nil, iodata()) :: iodata()
  def url_entry(loc, lastmod, alternates) do
    ["  <url>\n    <loc>", loc, "</loc>\n", lastmod_tag(lastmod), alternates, "  </url>\n"]
  end

  @doc "A `<lastmod>` line, or nothing at all when the date is unknown."
  @spec lastmod_tag(String.t() | nil) :: iodata()
  def lastmod_tag(nil), do: ""
  def lastmod_tag(lastmod), do: "    <lastmod>#{lastmod}</lastmod>\n"

  @doc "Wraps rendered `<url>` entries in a `<urlset>`."
  @spec urlset([iodata()]) :: iodata()
  def urlset(urls) do
    [
      ~s(<?xml version="1.0" encoding="UTF-8"?>\n),
      ~s(<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9"\n),
      ~s(        xmlns:xhtml="http://www.w3.org/1999/xhtml">\n),
      Enum.intersperse(urls, "\n"),
      "\n</urlset>\n"
    ]
  end

  @doc """
  A `<sitemapindex>` over `{url, lastmod}` children.

  Takes whole URLs rather than paths, because an index may point at another
  host entirely — which the protocol allows and `entries_for/2` does not.
  """
  @spec sitemapindex([{String.t(), String.t() | nil}]) :: iodata()
  def sitemapindex(children) do
    entries =
      Enum.map(children, fn {loc, lastmod} ->
        ["  <sitemap>\n    <loc>", loc, "</loc>\n", lastmod_tag(lastmod), "  </sitemap>"]
      end)

    [
      ~s(<?xml version="1.0" encoding="UTF-8"?>\n),
      ~s(<sitemapindex xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n),
      Enum.intersperse(entries, "\n"),
      "\n</sitemapindex>\n"
    ]
  end
end
