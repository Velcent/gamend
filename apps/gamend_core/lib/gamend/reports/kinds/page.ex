defmodule Gamend.Reports.Kinds.Page do
  @moduledoc """
  The built-in report kind: something on a page is broken or looks wrong.

  The subject is the page's path (query kept, fragment dropped), and the
  duplicates key is the path alone. A full URL is accepted and cut down to its
  path, so a reporter can paste the address bar; a URL on another site is
  kept as typed, since the report may well be about a link that leads there.
  """

  @behaviour Gamend.Reports.Kind

  @max_path 500

  @impl true
  def key, do: "page"

  @impl true
  def topics, do: []

  @impl true
  def max_attachments, do: 3

  @impl true
  def description_required?(_topic), do: true

  @impl true
  def ui, do: GamendWeb.Reports.PageKind

  @impl true
  def cast(params, _context) do
    path =
      params
      |> get_in(["subject", "path"])
      |> normalize()

    case path do
      nil ->
        {:ok, %{subject_ref: nil, subject: %{}, data: %{}}}

      path when byte_size(path) > @max_path ->
        {:error, :path_too_long}

      path ->
        {:ok, %{subject_ref: ref(path), subject: %{"path" => path}, data: %{}}}
    end
  end

  defp normalize(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      "/" <> _ = path -> strip_fragment(path)
      other -> from_url(other)
    end
  end

  defp normalize(_value), do: nil

  defp from_url(value) do
    case URI.parse(value) do
      %URI{scheme: scheme, path: path} = uri
      when scheme in ["http", "https"] and is_binary(path) ->
        if same_host?(uri), do: path <> query(uri), else: strip_fragment(value)

      _ ->
        strip_fragment(value)
    end
  end

  defp same_host?(%URI{host: host}) when is_binary(host) do
    case Application.get_env(:gamend_web, GamendWeb.Endpoint, [])[:url] do
      url when is_list(url) -> Keyword.get(url, :host) in [host, nil]
      _ -> true
    end
  end

  defp same_host?(_uri), do: false

  defp query(%URI{query: nil}), do: ""
  defp query(%URI{query: ""}), do: ""
  defp query(%URI{query: query}), do: "?" <> query

  defp strip_fragment(value), do: value |> String.split("#", parts: 2) |> hd()

  # The grouping key: the path without its query, capped to the column.
  defp ref(path) do
    path |> String.split("?", parts: 2) |> hd() |> String.slice(0, 255)
  end
end
