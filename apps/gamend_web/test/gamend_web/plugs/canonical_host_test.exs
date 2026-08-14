defmodule GamendWeb.Plugs.CanonicalHostTest do
  @moduledoc """
  `www.example.com` and `example.com` are different URLs to a crawler. Serving
  both with a 200 splits every page's ranking signals across two addresses.
  """
  use ExUnit.Case, async: true

  import Plug.Test
  import Plug.Conn

  alias GamendWeb.Plugs.CanonicalHost

  @canonical "example.com"

  setup do
    previous = Application.get_env(:gamend_web, :canonical_host)
    Application.put_env(:gamend_web, :canonical_host, @canonical)

    on_exit(fn ->
      if previous,
        do: Application.put_env(:gamend_web, :canonical_host, previous),
        else: Application.delete_env(:gamend_web, :canonical_host)
    end)

    :ok
  end

  defp call(conn), do: CanonicalHost.call(conn, CanonicalHost.init([]))

  defp request(method, host, path, scheme \\ :https, port \\ 443) do
    :get
    |> conn(path)
    |> Map.merge(%{method: method, host: host, scheme: scheme, port: port})
  end

  describe "an alias host" do
    test "is redirected permanently to the canonical host" do
      conn = call(request("GET", "www." <> @canonical, "/about"))

      assert conn.halted
      assert conn.status == 301

      assert get_resp_header(conn, "location") == [
               "https://#{@canonical}/about"
             ]
    end

    test "keeps the path and query string" do
      conn =
        "GET"
        |> request("www." <> @canonical, "/vocabulary")
        |> Map.put(:query_string, "lang=ro&page=2")
        |> call()

      assert get_resp_header(conn, "location") == [
               "https://#{@canonical}/vocabulary?lang=ro&page=2"
             ]
    end

    test "matches case-insensitively" do
      conn = call(request("GET", "WWW." <> String.upcase(@canonical), "/"))

      assert conn.status == 301
    end
  end

  describe "requests that must not be redirected" do
    test "the canonical host itself passes through" do
      conn = call(request("GET", @canonical, "/about"))

      refute conn.halted
      refute conn.status == 301
    end

    test "a POST is left alone" do
      # A 301 on a POST loses the body — browsers re-issue it as a GET, so a
      # form submitted to the alias would silently do nothing.
      conn = call(request("POST", "www." <> @canonical, "/users/log_in"))

      refute conn.halted
    end

    test "the health endpoint is left alone" do
      # Container and uptime checks hit this by IP or internal service name,
      # neither of which will ever be the canonical host.
      conn = call(request("GET", "10.0.0.4", "/api/v1/health"))

      refute conn.halted
    end

    test "an ACME challenge is left alone" do
      # The challenge has to be answered on the alias itself, or a certificate
      # covering it can never be issued.
      conn =
        call(
          request("GET", "www." <> @canonical, "/.well-known/acme-challenge/token123", :http, 80)
        )

      refute conn.halted
    end
  end

  describe "when unset" do
    test "nothing is redirected" do
      Application.delete_env(:gamend_web, :canonical_host)

      conn = call(request("GET", "www." <> @canonical, "/"))

      refute conn.halted
    end
  end

  describe "local development is never redirected" do
    # Setting :canonical_host outside prod once sent `localhost:4000` to
    # `example.com:4000`. That was a config mistake, but this plug
    # should refuse to act on it either way: redirecting a developer off their
    # own machine is never what anyone meant.
    for host <- ~w(localhost 127.0.0.1 ::1 0.0.0.0 dev.local app.localhost myhostname) do
      test "#{host} is left alone" do
        conn = call(request("GET", unquote(host), "/about", :http, 4000))

        refute conn.halted, "#{unquote(host)} must not be redirected off the machine"
      end
    end
  end

  describe "ports" do
    test "a non-default port survives the redirect" do
      conn = call(request("GET", "staging.example.com", "/about", :http, 4000))

      assert get_resp_header(conn, "location") == ["http://#{@canonical}:4000/about"]
    end
  end
end
