defmodule GamendWeb.Plugs.VisitorIdTest do
  use GamendWeb.ConnCase, async: false

  alias GamendWeb.Plugs.VisitorId

  defp run(conn), do: VisitorId.call(conn, VisitorId.init([]))

  defp with_session(conn) do
    conn
    |> Plug.Test.init_test_session(%{})
    |> Plug.Conn.fetch_session()
  end

  test "mints an id when the session has none", %{conn: conn} do
    conn = conn |> with_session() |> run()

    assert is_binary(conn.assigns.visitor_id)
    assert conn.assigns.visitor_id != ""
    assert Plug.Conn.get_session(conn, VisitorId.session_key()) == conn.assigns.visitor_id
  end

  test "keeps the id it already has", %{conn: conn} do
    first = conn |> with_session() |> run()

    second =
      conn
      |> Plug.Test.init_test_session(%{VisitorId.session_key() => first.assigns.visitor_id})
      |> Plug.Conn.fetch_session()
      |> run()

    # A visitor who reloads is the same visitor: a fresh id every request would
    # hand out a fresh free allowance every request.
    assert second.assigns.visitor_id == first.assigns.visitor_id
  end

  test "two visitors do not collide", %{conn: conn} do
    a = conn |> with_session() |> run()
    b = conn |> with_session() |> run()

    refute a.assigns.visitor_id == b.assigns.visitor_id
  end

  test "replaces a blank or non-binary id rather than carrying it", %{conn: conn} do
    for junk <- ["", 42, nil] do
      conn =
        conn
        |> Plug.Test.init_test_session(%{VisitorId.session_key() => junk})
        |> Plug.Conn.fetch_session()
        |> run()

      assert is_binary(conn.assigns.visitor_id)
      assert conn.assigns.visitor_id != ""
    end
  end

  test "the id is URL-safe, so it is readable in a log line unescaped" do
    for _n <- 1..20 do
      assert VisitorId.generate() =~ ~r/\A[A-Za-z0-9_-]+\z/
    end
  end
end
