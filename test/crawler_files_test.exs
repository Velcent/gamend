defmodule GamendHost.CrawlerFilesTest do
  @moduledoc """
  `robots.txt` and `llms.txt` are plain files under `priv/static`, but sitting
  on disk is not what makes them reachable: `Plug.Static` only serves a path
  whose first segment is listed in `:host_static_paths` (config/host_config.exs).
  Drop a name from that list and the file still exists, every page still
  renders, every other test still passes — and crawlers get a 404 instead of
  the crawl policy.

  This is also the worked example a host app copies: serve the file, register
  the path, and keep it out of the year-long `immutable` cache bucket (see
  `@revalidating_static` in `GamendWeb.Endpoint`).
  """

  use ExUnit.Case, async: false

  import Phoenix.ConnTest

  @endpoint GamendWeb.Endpoint

  setup do
    {:ok, conn: build_conn()}
  end

  test "robots.txt is served and still allows the search engines", %{conn: conn} do
    body =
      conn
      |> get("/robots.txt")
      |> response(200)

    # The allow-group, not the blocks: a rewrite that accidentally drops these
    # is the expensive mistake. Google's own parser reads one rule block per
    # run of `User-agent` lines (RFC 9309), so these share the `Allow: /` below
    # them — several third-party SEO tools misparse that and report the whole
    # site as blocked, which is a false alarm rather than a bug to fix here.
    for agent <- ~w(Googlebot GoogleOther Bingbot Slurp DuckDuckBot Applebot SeznamBot) do
      assert body =~ "User-agent: #{agent}\n"
    end

    # Answer engines are allowed; their training-only siblings are not. The two
    # are one word apart, which is exactly why this is asserted and not eyeballed.
    for agent <- ~w(OAI-SearchBot Claude-SearchBot PerplexityBot) do
      assert body =~ "User-agent: #{agent}\n"
    end

    for agent <- ~w(GPTBot Google-Extended ClaudeBot CCBot) do
      assert body =~ "User-agent: #{agent}\n"
    end

    # A `Sitemap:` line pointing at a host that does not resolve is worse than
    # none — this one advertised gamend.appsinacup.com, which is dead.
    assert body =~ "Sitemap: https://gamend.org/sitemap.xml"
  end

  test "llms.txt is served", %{conn: conn} do
    body =
      conn
      |> get("/llms.txt")
      |> response(200)

    assert body =~ "# Gamend"
  end
end
