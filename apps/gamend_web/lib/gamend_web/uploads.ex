defmodule GamendWeb.Uploads do
  @moduledoc """
  The two-step upload every icon and avatar endpoint shares.

  Bytes never pass through the app server. The client asks for a ticket, PUTs
  the file straight to storage, then tells the server which key it wrote:

      POST .../icon/upload_url   -> %{url: ..., key: ..., ...}
      PUT  <ticket.url>          (client -> storage, direct)
      POST .../icon              %{"key" => key}

  ## Why there is no single `POST /uploads`

  Authorization is a property of the *target*, not of uploading: only you may
  set your avatar, only a group admin may set that group's icon, only an admin
  may set a tournament's. A generic endpoint would have to take the target as a
  parameter and re-derive the same checks, so the route stays per-entity and
  only the mechanism is shared — that is what this module is.

  `confirm/5` is the load-bearing half, and on S3 it is the *only* half. A
  presigned PUT goes straight to the bucket, so none of the app-server checks
  run against it: the key (and therefore the extension) is server-chosen, but
  the bytes and their size are not, and ExAws does not sign the content type.
  Confirm is where an object becomes reachable from a row, so that is where it
  has to be proved: right prefix, within the size cap, and actually an image.
  """

  import Phoenix.Controller, only: [json: 2]
  import Plug.Conn, only: [put_status: 2]

  alias Gamend.Storage

  @doc """
  Issues a presigned upload ticket for `prefix/owner_id/<random><ext>`, after
  checking the declared content type is one the server accepts.
  """
  @spec ticket(Plug.Conn.t(), String.t(), String.t(), String.t(), String.t()) :: Plug.Conn.t()
  def ticket(conn, prefix, owner_id, stem, content_type) do
    case Storage.validate_upload(content_type, 0) do
      :ok ->
        key = Storage.build_key(prefix, owner_id, stem <> Storage.extension_for(content_type))
        {:ok, ticket} = Storage.presigned_upload(key, content_type: content_type)

        json(conn, sign_local_ticket(ticket, key))

      {:error, reason} ->
        error(conn, :bad_request, to_string(reason))
    end
  end

  @doc """
  Salt for the upload token. Public so the receiving controller verifies with
  the same one.
  """
  def token_salt, do: "storage upload"

  @doc "How long an upload ticket stays valid, in seconds."
  def token_max_age, do: 900

  # The local backend receives the upload on our own endpoint, so the key has to
  # travel signed: the receiver takes the key *from the token*, never from the
  # query string. Without that, `?key=` is client-controlled and an authenticated
  # user can choose their own extension — storing `x.html` under their avatar
  # folder and having it served back as text/html from our origin.
  #
  # S3 tickets point at the bucket and are already signed by the provider, so
  # they pass through untouched.
  defp sign_local_ticket(%{url: url} = ticket, key) do
    if String.contains?(url, "/storage/upload?") do
      token = Phoenix.Token.sign(GamendWeb.Endpoint, token_salt(), key)

      ticket
      |> Map.put(:url, url <> "&token=" <> URI.encode_www_form(token))
      |> Map.put(:token, token)
    else
      ticket
    end
  end

  @doc """
  Validates a client-supplied `key` against `prefix/owner_id/` and confirms the
  object exists, then calls `fun` with its public URL to persist.
  """
  @spec confirm(Plug.Conn.t(), String.t(), String.t(), term(), (String.t() -> Plug.Conn.t())) ::
          Plug.Conn.t()
  def confirm(conn, prefix, owner_id, key, fun) when is_binary(key) do
    if String.starts_with?(key, "#{prefix}/#{owner_id}/") do
      case verify_stored_object(key) do
        :ok -> fun.(Storage.url(key))
        {:error, :object_not_found} -> error(conn, :bad_request, "object_not_found")
        {:error, :too_large} -> error(conn, :request_entity_too_large, "too_large")
        {:error, :not_an_image} -> error(conn, :unsupported_media_type, "not_an_image")
      end
    else
      error(conn, :forbidden, "forbidden")
    end
  end

  def confirm(conn, _prefix, _owner_id, _key, _fun), do: error(conn, :bad_request, "missing_key")

  # Checks size before fetching, so an oversized object is rejected without
  # pulling it into memory. A rejected object is deleted rather than left to sit
  # in the bucket unreferenced.
  defp verify_stored_object(key) do
    max = Gamend.Limits.get(:max_upload_bytes)

    with {:ok, %{size: size}} when size <= max <- Storage.stat(key),
         {:ok, data} <- Storage.get(key),
         content_type when is_binary(content_type) <- Storage.sniff_content_type(data) do
      :ok
    else
      {:ok, %{size: _oversized}} -> reject(key, :too_large)
      nil -> reject(key, :not_an_image)
      {:error, _} -> {:error, :object_not_found}
    end
  end

  defp reject(key, reason) do
    _ = Storage.delete(key)
    {:error, reason}
  end

  @doc "The content type a client declared, as a string."
  @spec content_type(map()) :: String.t()
  def content_type(params), do: params["content_type"] || ""

  defp error(conn, status, message) do
    conn |> put_status(status) |> json(%{error: message})
  end
end
