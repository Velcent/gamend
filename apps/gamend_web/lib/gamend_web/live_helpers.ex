defmodule GamendWeb.LiveHelpers do
  @moduledoc """
  Shared helpers for LiveViews.
  """

  use Gettext, backend: GamendWeb.Gettext

  alias Gamend.Captcha

  # ── Pagination ──────────────────────────────────────────────────────────
  #
  # Eighteen LiveViews each wrote their own prev/next/page-size handlers, and
  # the copies had drifted into bugs: eleven parsed the size with
  # `String.to_integer/1`, so a non-numeric value crashed the page and any
  # number bypassed `Gamend.Limits`; six never clamped "next", so it paged past
  # the end into empty results; one clamped to `total_pages` without a floor, so
  # an empty list put the reader on page 0. These do the arithmetic once. Each
  # page still reloads its own way, so they return the socket rather than doing
  # the reload.

  @doc "See `GamendWeb.Pagination.total_pages/2`."
  defdelegate total_pages(total_count, page_size), to: GamendWeb.Pagination

  @doc """
  Steps back one page, never below the first.

  `key` is the assign holding the page number, for a view that pages more than
  one list.
  """
  @spec prev_page(Phoenix.LiveView.Socket.t(), atom()) :: Phoenix.LiveView.Socket.t()
  def prev_page(socket, key \\ :page) do
    Phoenix.Component.assign(socket, key, max(socket.assigns[key] - 1, 1))
  end

  @doc """
  Steps forward one page — no further than the last, when the view knows how
  many there are, and never onto page 0 when there are none.

  The total is read from `total_key`, which defaults to the page key's partner
  by the convention every view here follows: `:page` pairs with `:total_pages`,
  `:records_page` with `:records_total_pages`. Deriving it matters: a fixed
  `:total_pages` default would clamp a view's *second* list against its first
  list's total.
  """
  @spec next_page(Phoenix.LiveView.Socket.t(), atom(), atom() | nil) ::
          Phoenix.LiveView.Socket.t()
  def next_page(socket, key \\ :page, total_key \\ nil) do
    total_key = total_key || total_key_for(key)
    page = socket.assigns[key] + 1

    page =
      case socket.assigns[total_key] do
        total when is_integer(total) -> min(page, max(total, 1))
        _unknown -> page
      end

    Phoenix.Component.assign(socket, key, page)
  end

  defp total_key_for(:page), do: :total_pages

  # An atom no view has ever created cannot name an assign the socket holds, so
  # a view that pages without tracking a total simply has none: unbounded.
  defp total_key_for(key) do
    key
    |> Atom.to_string()
    |> String.replace_suffix("_page", "_total_pages")
    |> String.to_existing_atom()
  rescue
    ArgumentError -> nil
  end

  @doc """
  Applies a requested page size and returns to the first page.

  The raw value is whatever the form sent. It is parsed and clamped by
  `Gamend.Limits.clamp_page_size/2`, so a malformed value keeps the current size
  instead of crashing the view, and no value exceeds the configured maximum.
  `:min` raises the floor for a layout that needs a minimum (a card grid).
  `:size_key` and `:page_key` name the assigns, for a view paging more than one
  list (`:lobbies_page_size` and `:lobbies_page`, say).
  """
  @spec put_page_size(Phoenix.LiveView.Socket.t(), term(), keyword()) ::
          Phoenix.LiveView.Socket.t()
  def put_page_size(socket, raw, opts \\ []) do
    size_key = Keyword.get(opts, :size_key, :page_size)

    size =
      raw
      |> Gamend.Limits.clamp_page_size(socket.assigns[size_key] || 25)
      |> max(Keyword.get(opts, :min, 1))

    socket
    |> Phoenix.Component.assign(size_key, size)
    |> Phoenix.Component.assign(Keyword.get(opts, :page_key, :page), 1)
  end

  @doc """
  Extract the client IP from a LiveView socket's `connect_info`.

  Falls back to `"unknown"` when the socket has no peer data (e.g. during
  the initial static render or in tests).
  """
  def client_ip(socket) do
    case Phoenix.LiveView.get_connect_info(socket, :peer_data) do
      %{address: addr} -> addr |> :inet.ntoa() |> to_string()
      _ -> "unknown"
    end
  end

  @doc """
  Check a rate limit bucket for the given IP.

  Bucket types:
    - `:auth` — 30 requests per 60 seconds (matches the HTTP auth bucket)
    - `:general` — 1200 requests per 60 seconds

  Returns `:ok` or `{:error, retry_after_ms}`.
  """
  def check_rate_limit(ip, bucket_type \\ :general)

  def check_rate_limit("unknown", _bucket_type), do: :ok

  def check_rate_limit(ip, :auth) do
    {limit, window} = auth_limits()
    do_check("lv_auth:#{ip}", window, limit)
  end

  def check_rate_limit(ip, :general) do
    {limit, window} = general_limits()
    do_check("lv_general:#{ip}", window, limit)
  end

  defp do_check(key, window_ms, limit) do
    case GamendWeb.RateLimit.hit(key, window_ms, limit) do
      {:allow, _count} -> :ok
      {:deny, retry_after} -> {:error, retry_after}
    end
  end

  defp auth_limits do
    {setting(:auth_limit), setting(:auth_window_ms)}
  end

  defp general_limits do
    {setting(:general_limit), setting(:general_window_ms)}
  end

  defp setting(key), do: Gamend.Settings.get(GamendWeb.Plugs.RateLimiter, key)

  @doc """
  Verify the captcha token carried by a `phx-submit`'s params.

  Returns `:ok` — including whenever the captcha is disabled, so a call site
  needs no `enabled?/0` branch of its own — or `{:error, socket}` with the
  failure already handled: a flash explaining which way it failed, and a reset
  pushed to the widget. The reset is not optional. A token Cloudflare rejected
  is spent, so without it the form would resubmit the same dead token forever
  and the player could never recover without a reload.

  Pair it with `<.captcha>` in the form (see `GamendWeb.CoreComponents`),
  and read `:client_ip` off the socket, which both auth LiveViews assign at
  mount.
  """
  @spec check_captcha(Phoenix.LiveView.Socket.t(), map()) ::
          :ok | {:error, Phoenix.LiveView.Socket.t()}
  def check_captcha(socket, params) when is_map(params) do
    case Captcha.verify(params["cf-turnstile-response"], socket.assigns[:client_ip]) do
      :ok ->
        :ok

      {:error, reason} ->
        {:error,
         socket
         |> Phoenix.LiveView.put_flash(:error, captcha_error(reason))
         |> Phoenix.LiveView.push_event("captcha:reset", %{})}
    end
  end

  defp captcha_error(:missing), do: gettext("Please complete the captcha.")

  # Split from :missing so a player who did complete it is not told to do the
  # thing they just did.
  defp captcha_error(:invalid), do: gettext("Captcha check failed. Please try again.")

  defp captcha_error(:unavailable),
    do: gettext("Could not reach the captcha service. Please try again.")

  @doc """
  Put a standard success flash on a LiveView socket.
  """
  def put_success(socket, message), do: Phoenix.LiveView.put_flash(socket, :info, message)

  @doc """
  Put a standard error flash on a LiveView socket.
  """
  def put_failure(socket, message), do: Phoenix.LiveView.put_flash(socket, :error, message)

  @doc """
  Format a common `Failed: reason` message for LiveViews.
  """
  def failure_message(prefix, reason), do: prefix <> ": " <> inspect(reason)

  @doc """
  How a LiveView names a user it may only hold as a loaded struct, a serialized
  map, or a bare id. Never an email address.

  A struct or an id goes through `Gamend.Accounts.display_name/1`. A serialized
  map (string or atom keys) has no struct to hand over, so its fields are read
  directly by the same rule: display name, else username.

  This used to end at `"User <id>"` — the one fallback
  `Gamend.Accounts.display_label/1` documents as wrong, because it reads like a
  name while telling the reader nothing. An unresolvable user is `""` now.
  """
  def public_user_name(nil), do: ""
  def public_user_name(%Gamend.Accounts.User{} = user), do: Gamend.Accounts.display_name(user)
  def public_user_name(%{display_name: name}) when is_binary(name) and name != "", do: name
  def public_user_name(%{"display_name" => name}) when is_binary(name) and name != "", do: name
  def public_user_name(%{username: name}) when is_binary(name) and name != "", do: name
  def public_user_name(%{"username" => name}) when is_binary(name) and name != "", do: name
  def public_user_name(%{id: id}) when is_binary(id), do: Gamend.Accounts.display_name(id)
  def public_user_name(%{"id" => id}) when is_binary(id), do: Gamend.Accounts.display_name(id)
  def public_user_name(%{user_id: id}) when is_binary(id), do: Gamend.Accounts.display_name(id)

  def public_user_name(%{"user_id" => id}) when is_binary(id),
    do: Gamend.Accounts.display_name(id)

  def public_user_name(id) when is_binary(id), do: Gamend.Accounts.display_name(id)
  def public_user_name(_), do: ""

  @doc """
  Return the public `@username` handle for a user, or `nil` when the user has
  none (renders as empty in HEEx, so callers can interpolate it directly).
  """
  def public_user_handle(%{username: name}) when is_binary(name) and name != "", do: "@" <> name

  def public_user_handle(%{"username" => name}) when is_binary(name) and name != "",
    do: "@" <> name

  def public_user_handle(_), do: nil
end
