defmodule GamendWeb.PageMeta do
  @moduledoc """
  Helpers for the host module behind `GamendWeb.Plugs.PageMeta`.

  Every host answers "what is this page about" with its own copy, but the
  mechanics around that copy — normalising the path it is keyed by, stripping
  markdown out of it, cutting it to what a search engine shows, and turning a
  breadcrumb trail into `BreadcrumbList` markup — are the same everywhere.
  """

  alias GamendWeb.HostLayouts

  @description_limit 160

  @doc "The lookup form of `path`: no trailing slash, `/` for the root."
  @spec normalize(String.t()) :: String.t()
  def normalize(path) do
    case String.trim_trailing(path, "/") do
      "" -> "/"
      trimmed -> trimmed
    end
  end

  @doc "An absolute URL for `path`."
  @spec url(String.t()) :: String.t()
  def url(path) do
    base = String.trim_trailing(GamendWeb.endpoint().url(), "/")
    if String.starts_with?(path, "/"), do: base <> path, else: base <> "/" <> path
  end

  @doc "An absolute URL for `path` under the locale being rendered."
  @spec locale_url(String.t()) :: String.t()
  def locale_url(path) do
    path
    |> HostLayouts.localized_href(HostLayouts.current_locale())
    |> url()
  end

  @doc """
  `text` as the plain prose a `<meta name="description">` takes.

  Descriptions are drawn from markdown — a post's excerpt, a guide's opening
  paragraph — where links and emphasis would otherwise reach the snippet as
  their own source characters.
  """
  @spec plain_text(String.t() | nil) :: String.t() | nil
  def plain_text(nil), do: nil

  def plain_text(text) do
    text
    |> String.replace(~r/\[([^\]]*)\]\([^)]*\)/, "\\1")
    |> String.replace(~r/[*_`#]+/, "")
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end

  @doc """
  `text` cut to `max` characters at a word boundary.

  Defaults to the ~160 characters Google shows before it truncates.
  """
  @spec truncate(String.t() | nil, pos_integer()) :: String.t() | nil
  def truncate(text, max \\ @description_limit)
  def truncate(nil, _max), do: nil

  def truncate(text, max) do
    if String.length(text) <= max do
      text
    else
      text
      |> String.slice(0, max)
      |> String.replace(~r/\s+\S*$/, "")
      |> Kernel.<>("…")
    end
  end

  @doc """
  `trail` as a schema.org `BreadcrumbList`, or `nil` when it has no ancestry.

  Built from the trail the layout renders, so the visible crumbs and the markup
  cannot disagree. Crumb URLs are locale-prefixed to match the page's canonical
  — a French page whose trail points at English URLs describes a different page.
  """
  @spec breadcrumb_list([{String.t(), String.t() | nil}], String.t()) :: map() | nil
  def breadcrumb_list(trail, current_path) when length(trail) > 1 do
    items =
      trail
      |> Enum.with_index(1)
      |> Enum.map(fn {{name, path}, position} ->
        %{
          "@type" => "ListItem",
          "position" => position,
          "name" => name,
          "item" => locale_url(path || current_path)
        }
      end)

    %{
      "@context" => "https://schema.org",
      "@type" => "BreadcrumbList",
      "itemListElement" => items
    }
  end

  def breadcrumb_list(_trail, _current_path), do: nil
end
