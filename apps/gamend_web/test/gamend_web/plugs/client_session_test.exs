defmodule GamendWeb.Plugs.ClientSessionTest do
  use GamendWeb.ConnCase, async: false

  import ExUnit.CaptureLog

  require Logger

  alias Gamend.ClientLogs
  alias Gamend.SettingsHelpers
  alias GamendWeb.Plugs.ClientSession

  setup do
    SettingsHelpers.put(:gamend_core, ClientLogs, :enabled, true)
    on_exit(fn -> SettingsHelpers.delete(:gamend_core, ClientLogs, :enabled) end)
    :ok
  end

  describe "sanitize/1" do
    test "accepts the shapes a generated id takes" do
      assert ClientSession.sanitize("0f1e2d3c4b5a6978") == "0f1e2d3c4b5a6978"
      assert ClientSession.sanitize("sess-0f1e_2d3c") == "sess-0f1e_2d3c"
      assert ClientSession.sanitize("  0f1e2d3c4b5a6978  ") == "0f1e2d3c4b5a6978"
    end

    test "refuses anything that could forge a field into a log line" do
      # The id is interpolated into a logfmt line, so a space or an `=` would
      # let a caller invent `user=someone-else` in the server's own logs.
      assert ClientSession.sanitize("0f1e2d3c user=admin") == nil
      assert ClientSession.sanitize("0f1e=2d3c4b5a") == nil
      assert ClientSession.sanitize("with\nnewline") == nil
      assert ClientSession.sanitize("short") == nil
      assert ClientSession.sanitize(String.duplicate("a", 129)) == nil
      assert ClientSession.sanitize(nil) == nil
      assert ClientSession.sanitize(12_345) == nil
    end
  end

  describe "the correlation key" do
    test "a server line and a client line share one searchable id", %{conn: conn} do
      sid = "corr-" <> Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)

      previous = Logger.level()
      Logger.configure(level: :info)

      on_exit(fn -> Logger.configure(level: previous) end)

      # The client uploads its own lines...
      client_log =
        capture_log(fn ->
          ClientLogs.ingest(%{
            "session" => %{"client_session_id" => sid, "platform" => "android"},
            "entries" => [
              %{
                "seq" => 1,
                "level" => "error",
                "category" => "auth",
                "message" => "Refresh failed"
              }
            ]
          })
        end)

      # ...and a server line logged while handling a request from the same
      # client carries the same id, because the plug stamped it.
      server_log =
        capture_log(fn ->
          conn
          |> put_req_header("x-gamend-session", sid)
          |> get("/api/v1/health")
          |> then(fn conn ->
            # Logged from the request process, after the plug ran.
            assert conn.assigns[:client_session_id] == sid
            conn
          end)

          Logger.metadata(client_session: sid)
          Logger.info("lobby join rejected")
        end)

      assert client_log =~ sid
      assert client_log =~ "Refresh failed"
      assert server_log =~ "lobby join rejected"

      # One search over the merged stream returns both halves.
      assert Enum.all?([client_log, server_log], &String.contains?(&1, sid))
    end

    test "an absent header leaves metadata untouched", %{conn: conn} do
      conn = get(conn, "/api/v1/health")
      refute Map.has_key?(conn.assigns, :client_session_id)
    end

    test "a hostile header is dropped rather than stamped", %{conn: conn} do
      conn =
        conn
        |> put_req_header("x-gamend-session", "abcdefgh user=admin")
        |> get("/api/v1/health")

      refute Map.has_key?(conn.assigns, :client_session_id)
    end
  end
end
