defmodule GamendWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :gamend_web

  @session_options [
    store: :cookie,
    key: "_gamend_key",
    signing_salt: "G8u1px36",
    same_site: "Lax",
    secure: Application.compile_env(:gamend_web, :session_secure, false)
  ]

  # timeout: the game client runs on requestAnimationFrame, which browsers
  # stop entirely for background tabs — heartbeats pause and the default 60s
  # would drop every alt-tabbed player. 5 minutes keeps the TCP-alive-but-
  # silent socket open across short tab switches; hard disconnects still
  # terminate immediately (this only defers reaping half-open connections).
  socket "/socket", GamendWeb.UserSocket,
    websocket: [log: false, compress: true, max_frame_size: 131_072, timeout: 300_000],
    longpoll: false

  socket "/live", Phoenix.LiveView.Socket,
    websocket: [connect_info: [:peer_data, session: @session_options], log: false, compress: true],
    longpoll: [connect_info: [session: @session_options], log: false]

  plug GamendWeb.Plugs.AcmeChallenge
  # After AcmeChallenge so certbot's HTTP-01 fetch is answered before any
  # redirect can touch it; before everything else so a plain-HTTP request
  # costs one 301 and nothing more.
  plug GamendWeb.Plugs.ForceSSL
  # After ForceSSL so a plain-HTTP request to an alias costs one redirect to
  # https on the canonical host rather than two hops.
  plug GamendWeb.Plugs.CanonicalHost
  plug GamendWeb.Plugs.IndexNowKey
  plug GamendWeb.Plugs.SecurityHeaders
  plug GamendWeb.Plugs.WellKnown
  plug GamendWeb.Plugs.GameHeaders
  plug :serve_game_static
  plug :serve_host_static
  plug :serve_asset_static
  plug :serve_bundled_static
  plug GamendWeb.HostContentStatic

  # Two separate guards, deliberately. `Phoenix.CodeReloader` ships with
  # :phoenix, but `Phoenix.LiveReloader` is a `only: :dev` dependency — and
  # Mix never loads `only:` deps OF a dependency. So when a host app compiles
  # this app as a dep, `ensure_loaded?(Phoenix.LiveReloader)` is false, and a
  # single combined guard silently dropped code reloading too: every change,
  # host or plugin, needed a full server restart to take effect.
  if code_reloading? do
    plug Phoenix.CodeReloader
    plug Phoenix.Ecto.CheckRepoStatus, otp_app: :gamend_web
  end

  # Browser auto-refresh is the part that genuinely needs the dev dependency.
  if code_reloading? and Code.ensure_loaded?(Phoenix.LiveReloader) and
       Code.ensure_loaded?(Phoenix.LiveReloader.Socket) do
    socket "/phoenix/live_reload/socket", Phoenix.LiveReloader.Socket
    plug Phoenix.LiveReloader
  end

  plug Phoenix.LiveDashboard.RequestLogger,
    param_key: "request_logger",
    cookie_key: "request_logger"

  plug Plug.RequestId
  plug GamendWeb.Plugs.RealIp
  plug GamendWeb.Plugs.GeoCountry
  plug GamendWeb.Plugs.IpBan
  plug GamendWeb.Plugs.RequestTimer

  plug Plug.Telemetry,
    event_prefix: [:phoenix, :endpoint],
    log: {__MODULE__, :access_log_level, []}

  plug Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    length: 1_048_576,
    body_reader: {GamendWeb.Plugs.RawBodyReader, :read_body, []},
    json_decoder: Phoenix.json_library()

  plug Plug.MethodOverride
  plug Plug.Head

  @compiled_session_opts Plug.Session.init(@session_options)
  plug :maybe_session

  defp maybe_session(%{path_info: ["api", "v1" | _]} = conn, _opts), do: conn
  defp maybe_session(conn, _opts), do: Plug.Session.call(conn, @compiled_session_opts)

  plug GamendWeb.Plugs.LocalePath
  plug GamendWeb.Plugs.DynamicCors
  plug GamendWeb.Plugs.RateLimiter
  plug :dispatch_router

  @access_log_pt_key {__MODULE__, :access_log_level}

  def access_log_level(_conn) do
    case :persistent_term.get(@access_log_pt_key, :not_set) do
      :not_set ->
        level =
          case Application.get_env(:gamend_web, __MODULE__)[:access_log] do
            level when level in [:debug, :info, :warning, :error] -> level
            false -> false
            _ -> :debug
          end

        :persistent_term.put(@access_log_pt_key, level)
        level

      cached ->
        cached
    end
  end

  # Files third parties fetch at a bare, un-fingerprinted path. They must stay
  # changeable: `robots.txt` under a year-long `immutable` meant a crawl-rule
  # change could not reach a client that had cached it, and `.well-known`
  # carries app-association files with the same problem.
  @revalidating_static ~w(robots.txt .well-known)

  defp serve_host_static(conn, _opts) do
    paths = host_static_paths() -- ~w(game)

    Plug.Static.call(
      conn,
      configurable_static_opts(
        :host_static_opts,
        host_static_app(),
        paths -- @revalidating_static
      )
    )
    |> case do
      %{halted: true} = halted ->
        halted

      passed ->
        Plug.Static.call(
          passed,
          configurable_static_opts(
            :revalidating_static_opts,
            host_static_app(),
            paths -- (paths -- @revalidating_static)
          )
        )
    end
  end

  defp serve_game_static(conn, _opts) do
    Plug.Static.call(
      conn,
      configurable_static_opts(:game_static_opts, host_static_app(), ~w(game))
    )
  end

  defp serve_asset_static(conn, _opts) do
    Plug.Static.call(
      conn,
      configurable_static_opts(:asset_static_opts, asset_static_app(), ~w(assets))
    )
  end

  # Bundled reference assets: shipped with the web app, requested without a
  # digest, and cached for a year by the `static_cache_control/1` catch-all.
  defp serve_bundled_static(conn, _opts) do
    Plug.Static.call(
      conn,
      configurable_static_opts(:bundled_static_opts, :gamend_web, ~w(fonts flags))
    )
  end

  defp dispatch_router(conn, _opts) do
    router = Application.get_env(:gamend_web, :router, GamendWeb.Router)
    router.call(conn, router.init([]))
  end

  defp configurable_static_opts(kind, from, only) do
    key = {__MODULE__, kind, from, only, gzip_static?(), brotli_static?()}

    case :persistent_term.get(key, :not_set) do
      :not_set ->
        opts =
          Plug.Static.init(
            at: "/",
            from: from,
            brotli: brotli_static?(),
            gzip: gzip_static?(),
            only: only,
            cache_control_for_etags: static_cache_control(kind),
            cache_control_for_vsn_requests: static_vsn_cache_control(kind),
            headers: static_headers(kind)
          )

        :persistent_term.put(key, opts)
        opts

      opts ->
        opts
    end
  end

  # Extra response headers per static kind. The game build needs
  # cross-origin isolation (COOP/COEP) when exported with thread support —
  # SharedArrayBuffer is gated on it — so hosts opt in via config, e.g.
  # config :gamend_web, :game_static_headers, %{"cross-origin-opener-policy" => ...}.
  defp static_headers(:game_static_opts) do
    Application.get_env(:gamend_web, :game_static_headers, %{})
  end

  defp static_headers(_kind), do: %{}

  defp static_cache_control(:revalidating_static_opts) do
    Application.get_env(
      :gamend_web,
      :revalidating_static_cache_control,
      "public, max-age=0, must-revalidate"
    )
  end

  defp static_cache_control(:game_static_opts) do
    Application.get_env(
      :gamend_web,
      :game_static_cache_control,
      "public, max-age=0, must-revalidate"
    )
  end

  defp static_cache_control(_kind) do
    Application.get_env(
      :gamend_web,
      :static_cache_control,
      "public, max-age=31536000, immutable"
    )
  end

  # A `?vsn=` request names one exact revision of a file, so it can be cached
  # forever whatever the plain URL's policy is — that is the whole point of the
  # parameter, and Plug.Static's own default.
  #
  # The revalidating kinds exist because Godot's export reuses filenames across
  # builds (`index.png`, `index.wasm`, `index.pck`), so a bare URL must be
  # rechecked or a deploy strands players on the previous build. Pinning vsn
  # requests to that same policy removed the only escape hatch: every asset paid
  # a round-trip on every load — measured at ~286 ms for a 304 carrying no
  # bytes — with no way for a caller to say "I want exactly this revision".
  defp static_vsn_cache_control(kind) do
    Application.get_env(
      :gamend_web,
      :"#{kind}_vsn_cache_control",
      Application.get_env(
        :gamend_web,
        :static_vsn_cache_control,
        "public, max-age=31536000, immutable"
      )
    )
  end

  defp host_static_app do
    Application.get_env(:gamend_web, :host_static_app, :gamend_web)
  end

  defp asset_static_app do
    Application.get_env(:gamend_web, :asset_static_app, host_static_app())
  end

  defp host_static_paths do
    Application.get_env(
      :gamend_web,
      :host_static_paths,
      ~w(images game favicon.ico robots.txt .well-known theme.css)
    )
  end

  defp gzip_static? do
    Application.get_env(:gamend_web, :gzip_static, false)
  end

  defp brotli_static? do
    Application.get_env(:gamend_web, :brotli_static, false)
  end
end
