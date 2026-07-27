defmodule GameServerWeb.Api.V1.StorageController do
  @moduledoc """
  Receives local uploads and serves stored objects.

  For the S3 backend clients upload straight to the bucket via the presigned URL
  and these endpoints are unused; for the local backend the upload ticket points
  `PUT /storage/upload` here.

  ## Why the key is signed

  The key decides both where the object lands and, on the way back out, what
  extension it carries. Deriving it from the query string made it
  client-controlled: an authenticated user could PUT `avatars/<own_id>/x.html`
  and have it served back from our own origin as `text/html`. So the key comes
  from a token `GameServerWeb.Uploads` signed when it issued the ticket, and
  `?key=` is only ever a cross-check. Authorization happened at ticket time,
  which is also what lets non-avatar prefixes (entity icons) upload here at all.
  """

  use GameServerWeb, :controller

  alias GameServer.Storage
  alias GameServerWeb.Uploads

  # Content types this route will name in a response. Everything else is served
  # as an opaque download.
  @servable_types ~w(image/png image/jpeg image/webp image/gif)

  @doc "PUT /storage/upload?key=...&token=... — authenticated raw-body upload (local backend)."
  def upload(conn, %{"token" => token} = params) do
    content_type = request_content_type(conn)
    max = GameServer.Limits.get(:max_upload_bytes)

    with {:ok, key} <- verify_token(token, params["key"]),
         {:ok, body, conn} <- read_full_body(conn, max),
         :ok <- Storage.validate_upload(content_type, byte_size(body)),
         :ok <- verify_magic_bytes(body, content_type),
         :ok <- check_owner_quota(key, byte_size(body)),
         {:ok, ^key} <- Storage.put(key, body, content_type: content_type) do
      json(conn, %{ok: true, key: key})
    else
      {:error, :forbidden} ->
        conn |> put_status(:forbidden) |> json(%{error: "forbidden"})

      {:error, :content_mismatch} ->
        conn |> put_status(:unsupported_media_type) |> json(%{error: "content_mismatch"})

      {:error, :too_large} ->
        conn |> put_status(:request_entity_too_large) |> json(%{error: "too_large"})

      {:error, :quota_exceeded} ->
        conn |> put_status(:insufficient_storage) |> json(%{error: "quota_exceeded"})

      {:error, :unsupported_content_type} ->
        conn |> put_status(:unsupported_media_type) |> json(%{error: "unsupported_content_type"})

      _ ->
        conn |> put_status(:bad_request) |> json(%{error: "upload_failed"})
    end
  end

  def upload(conn, _), do: conn |> put_status(:bad_request) |> json(%{error: "missing_token"})

  @doc "GET /storage/*key — serve a stored object (local backend)."
  def show(conn, %{"key" => segments}) do
    key = Enum.join(segments, "/")

    case Storage.get(key) do
      {:ok, data} ->
        etag = etag_for(data)

        conn =
          conn
          |> put_resp_header("cache-control", Storage.cache_control(key))
          |> put_resp_header("etag", etag)

        if if_none_match_hit?(conn, etag) do
          send_resp(conn, 304, "")
        else
          conn
          |> put_resp_header("x-content-type-options", "nosniff")
          |> serve_type(key)
          |> send_resp(200, data)
        end

      {:error, _} ->
        conn |> put_status(:not_found) |> json(%{error: "not_found"})
    end
  end

  # Strong ETag over the bytes. Lets revalidated (mutable) objects return a cheap
  # 304; immutable-cached objects (avatars) rarely revalidate at all.
  defp etag_for(data), do: ~s("#{:crypto.hash(:md5, data) |> Base.encode16(case: :lower)}")

  defp if_none_match_hit?(conn, etag) do
    case get_req_header(conn, "if-none-match") do
      [value | _] -> etag in String.split(value, ~r/\s*,\s*/)
      [] -> false
    end
  end

  # Belt and braces for objects already on disk from before keys were signed, and
  # for anything a future caller writes server-side: this route hands attacker-
  # supplied bytes back from our own origin, so it may only ever label them as an
  # image. Anything else downloads instead of rendering.
  defp serve_type(conn, key) do
    type = MIME.from_path(key)

    if type in @servable_types do
      put_resp_content_type(conn, type)
    else
      conn
      |> put_resp_header("content-disposition", "attachment")
      |> put_resp_content_type("application/octet-stream", nil)
    end
  end

  # Every ticket mints a fresh random key, and only a confirmed one is ever
  # linked to a row - so a client that requests tickets in a loop and uploads to
  # each leaves orphans behind. Cap what one owner can hold under its prefix.
  defp check_owner_quota(key, incoming) do
    %{bytes: used} = Storage.usage(prefix: Path.dirname(key) <> "/")

    if used + incoming > GameServer.Limits.get(:max_upload_bytes_per_owner),
      do: {:error, :quota_exceeded},
      else: :ok
  end

  defp verify_token(token, requested_key) do
    case Phoenix.Token.verify(GameServerWeb.Endpoint, Uploads.token_salt(), token,
           max_age: Uploads.token_max_age()
         ) do
      {:ok, key} when requested_key in [nil, key] -> {:ok, key}
      {:ok, _mismatched} -> {:error, :forbidden}
      {:error, _} -> {:error, :forbidden}
    end
  end

  # The declared content type is just a header. Check the bytes actually start
  # like the image they claim to be, so the stored object can never be a
  # different format wearing an image's extension.
  defp verify_magic_bytes(body, content_type) do
    if Storage.sniff_content_type(body) == content_type,
      do: :ok,
      else: {:error, :content_mismatch}
  end

  defp request_content_type(conn) do
    case get_req_header(conn, "content-type") do
      [ct | _] -> ct |> String.split(";") |> hd() |> String.trim()
      [] -> ""
    end
  end

  # Reads one byte past the cap so an oversized body is detected without buffering
  # the whole thing. Image bodies pass the endpoint parser unparsed (`pass: */*`).
  defp read_full_body(conn, max) do
    case read_body(conn, length: max + 1) do
      {:ok, body, conn} when byte_size(body) <= max -> {:ok, body, conn}
      {:ok, _body, _conn} -> {:error, :too_large}
      {:more, _partial, _conn} -> {:error, :too_large}
      {:error, _} = err -> err
    end
  end
end
