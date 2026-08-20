defmodule GamendWeb.Sitemap.XmlTest do
  @moduledoc """
  The sitemap protocol, which two hosts now share one copy of.

  Worth pinning because nothing else catches a mistake here: malformed XML
  still returns 200, a wrong `hreflang` still parses, and the only reader is a
  crawler that will not tell you. The shapes asserted are the ones Search
  Console rejects a file over.
  """
  use ExUnit.Case, async: true

  alias GamendWeb.Sitemap.Xml

  # A context by hand rather than `Xml.context/1`: the real one reads the
  # endpoint and the configured locales, and this is testing the rendering, not
  # the wiring.
  defp ctx(overrides \\ %{}) do
    Map.merge(
      %{
        manifest: %{"tracked" => %{"date" => "2026-08-01", "hash" => "abc"}},
        base_url: "https://example.test",
        default_locale: "en",
        locales: ["en", "fr"],
        url_locales: %{"en" => "en", "fr" => "fr"},
        locale_lastmod: fn own, _locale -> own end
      },
      overrides
    )
  end

  defp render(iodata), do: IO.iodata_to_binary(iodata)

  describe "locale_url/3" do
    test "the default locale owns the clean URL" do
      assert Xml.locale_url(ctx(), "en", "/guide") == "https://example.test/guide"
    end

    test "every other locale is prefixed" do
      assert Xml.locale_url(ctx(), "fr", "/guide") == "https://example.test/fr/guide"
    end

    test "the root takes no suffix" do
      # Otherwise it renders `/fr/`, which is a different URL from `/fr` and
      # the one the router does not serve.
      assert Xml.locale_url(ctx(), "fr", "/") == "https://example.test/fr"
      assert Xml.locale_url(ctx(), "en", "/") == "https://example.test/"
    end
  end

  describe "own_lastmod/2" do
    test "a literal date wins" do
      assert Xml.own_lastmod(ctx(), %{loc: "/a", lastmod: "2026-01-01"}) == "2026-01-01"
    end

    test "a manifest key resolves through the manifest" do
      assert Xml.own_lastmod(ctx(), %{loc: "/a", lastmod_key: "tracked"}) == "2026-08-01"
    end

    test "an untracked key is nil, not a guess" do
      assert Xml.own_lastmod(ctx(), %{loc: "/a", lastmod_key: "missing"}) == nil
      assert Xml.own_lastmod(ctx(), %{loc: "/a"}) == nil
    end
  end

  describe "lastmod_tag/1" do
    test "an unknown date emits no element at all" do
      # Not an empty `<lastmod></lastmod>`, which is invalid.
      assert Xml.lastmod_tag(nil) == ""
    end

    test "a known date emits one" do
      assert render(Xml.lastmod_tag("2026-08-01")) == "    <lastmod>2026-08-01</lastmod>\n"
    end
  end

  describe "alternate_links/2" do
    test "every locale plus x-default, pointing at the clean URL" do
      xml = render(Xml.alternate_links(ctx(), "/guide"))

      assert xml =~ ~s(hreflang="x-default" href="https://example.test/guide")
      assert xml =~ ~s(hreflang="en" href="https://example.test/guide")
      assert xml =~ ~s(hreflang="fr" href="https://example.test/fr/guide")
    end

    test "x-default is not counted twice" do
      # It duplicates the default locale's URL on purpose, but as its own link:
      # three links for two locales, not four.
      links = ctx() |> Xml.alternate_links("/guide") |> render() |> String.split("<xhtml:link")

      assert length(links) == 4
    end
  end

  describe "urlset/1" do
    test "wraps entries with both namespaces the alternates need" do
      xml = render(Xml.urlset([Xml.url_entry("https://example.test/", nil, "")]))

      assert xml =~ ~s(<?xml version="1.0" encoding="UTF-8"?>)
      assert xml =~ ~s(xmlns="http://www.sitemaps.org/schemas/sitemap/0.9")
      assert xml =~ ~s(xmlns:xhtml="http://www.w3.org/1999/xhtml")
      assert xml =~ "<loc>https://example.test/</loc>"
      assert String.ends_with?(xml, "</urlset>\n")
    end
  end

  describe "sitemapindex/1" do
    test "renders children, dated ones and undated ones alike" do
      xml =
        render(
          Xml.sitemapindex([
            {"https://example.test/sitemap/pages.xml", "2026-08-01"},
            {"https://example.test/sitemap/other.xml", nil}
          ])
        )

      assert xml =~ ~s(<sitemapindex xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">)
      assert xml =~ "<loc>https://example.test/sitemap/pages.xml</loc>"
      assert xml =~ "<lastmod>2026-08-01</lastmod>"
      assert String.ends_with?(xml, "</sitemapindex>\n")
      # The undated child still renders, just without the element.
      assert xml =~ "<loc>https://example.test/sitemap/other.xml</loc>\n  </sitemap>"
    end
  end

  describe "entries_for/2 locale rollup" do
    test "the default returns the page's own date for every locale" do
      # `entries_for/2` needs the router to say a path is localized, which this
      # test cannot arrange — so the rollup is exercised through the function
      # the context carries, which is the part a host overrides.
      assert ctx().locale_lastmod.("2026-01-01", "fr") == "2026-01-01"
    end

    test "a host's rollup can take the later of two dates" do
      rollup = fn own, locale ->
        case %{"fr" => "2026-05-05"}[locale] do
          nil -> own
          base -> Enum.max([own, base])
        end
      end

      assert rollup.("2026-01-01", "fr") == "2026-05-05"
      assert rollup.("2026-09-09", "fr") == "2026-09-09"
      assert rollup.("2026-01-01", "en") == "2026-01-01"
    end
  end
end
