defmodule GamendWeb.StaticCacheTest do
  @moduledoc """
  The game directory is served `max-age=0, must-revalidate` on purpose: Godot's
  export reuses filenames across builds (`index.png`, `index.wasm`, `index.pck`),
  so a bare URL must be rechecked or a deploy strands players on the previous
  build.

  That is right for a bare URL and wrong for a versioned one. `?vsn=<hash>`
  names one exact revision, so it can be cached forever — changing the file
  changes the hash and therefore the URL. Before this split, versioned requests
  were pinned to the same revalidating policy, so every asset paid a round-trip
  on every load with no way for a caller to opt out.
  """
  use GamendWeb.ConnCase, async: false

  @asset "cache-probe.txt"

  setup do
    # The game build lives in the host app, not here, so nothing under /game
    # exists in this checkout. Without a real file both requests 404 and every
    # assertion below passes while proving nothing — hence the probe test.
    #
    # `:host_static_app` is what the endpoint serves /game from, so the file has
    # to land in that app's priv, not this test file's idea of the repo layout.
    host_app = Application.get_env(:gamend_web, :host_static_app, :gamend_web)
    dir = Application.app_dir(host_app, "priv/static/game")
    File.mkdir_p!(dir)
    path = Path.join(dir, @asset)
    File.write!(path, "probe")

    on_exit(fn ->
      File.rm(path)
      File.rmdir(dir)
    end)

    %{url: "/game/" <> @asset}
  end

  defp cache_control(conn), do: get_resp_header(conn, "cache-control")

  test "the probe file is actually served (guards against a vacuous pass)", %{
    conn: conn,
    url: url
  } do
    conn = get(conn, url)

    assert conn.status == 200, "expected /game/#{@asset} to be served, got #{conn.status}"
    assert response(conn, 200) == "probe"
  end

  test "a bare request must be revalidated", %{conn: conn, url: url} do
    conn = get(conn, url)

    assert ["public, max-age=0, must-revalidate"] = cache_control(conn)
  end

  test "a ?vsn= request is cached forever", %{conn: conn, url: url} do
    conn = get(conn, url <> "?vsn=abc123")

    assert ["public, max-age=31536000, immutable"] = cache_control(conn),
           "a versioned URL names one exact revision, so it must not be revalidated"
  end
end
