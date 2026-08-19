defmodule GamendWeb.Plugs.ClientSession do
  @moduledoc """
  Stamps the caller's client session id into `Logger` metadata for the rest of
  the request.

  This is what makes client and server logs one timeline rather than two. The
  game sends `x-gamend-session` on every request; from here on, every server
  line logged while handling it carries the same id that the client's own
  uploaded lines carry (see `Gamend.ClientLogs`), so one search returns both
  halves of a failure — what the client thought it asked for, and what the
  server actually did.

  Without it the join is by timestamp and user id, which is guesswork the
  moment a player has two devices, or the failure is a client that never got
  far enough to authenticate.

  ## Trust

  The header is unauthenticated and self-asserted. That is fine for what it is
  used for: a correlation label on the server's own log lines, never an
  identity and never an authorization input. The durable side — the
  `client_sessions` row — is owner-bound on write and does not consult this.
  The id is length-capped and stripped of anything outside the character set a
  generated id uses, so a hostile value cannot forge extra logfmt fields into a
  log line or blow up its size.

  Placed in the endpoint before the router so LiveView mounts, channel joins
  over the long-poll transport, and error rendering all inherit it.
  """

  @behaviour Plug

  @header "x-gamend-session"
  @max_bytes 128
  # Hex, dashes and underscores: everything a UUID or a prefixed random id
  # needs, and nothing that could inject `key=value` into a log line.
  @allowed ~r/^[A-Za-z0-9_-]+$/

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    case session_id(conn) do
      nil -> conn
      id -> stamp(conn, id)
    end
  end

  @doc """
  Validate a self-asserted session id, returning it or `nil`.

  Public so the socket path applies the same rules as the HTTP one — a second
  copy of the character set is a second thing to forget to update.
  """
  @spec sanitize(term()) :: String.t() | nil
  def sanitize(value), do: validate(value)

  @doc """
  Stamp a session id onto the calling process's `Logger` metadata.

  Channels each run in their own process, and metadata is per-process and not
  inherited, so a channel that wants its lines correlated calls this in `join/3`
  rather than relying on the socket's connect having done it.
  """
  @spec put_metadata(term()) :: :ok
  def put_metadata(value) do
    case validate(value) do
      nil -> :ok
      id -> Logger.metadata(client_session: id)
    end
  end

  defp stamp(conn, id) do
    Logger.metadata(client_session: id)
    Plug.Conn.assign(conn, :client_session_id, id)
  end

  defp session_id(conn) do
    conn
    |> Plug.Conn.get_req_header(@header)
    |> List.first()
    |> validate()
  end

  defp validate(value) when is_binary(value) do
    trimmed = String.trim(value)

    if byte_size(trimmed) in 8..@max_bytes and Regex.match?(@allowed, trimmed) do
      trimmed
    end
  end

  defp validate(_), do: nil
end
