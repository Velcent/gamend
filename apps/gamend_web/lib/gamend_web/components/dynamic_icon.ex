defmodule GamendWeb.Components.DynamicIcon do
  @moduledoc """
  A tiny runtime SVG loader for hero-style icons stored under
  `priv/static/heroicons/`.

  Usage:

      <.dynamic_icon name={"hero-book-open"} class="w-5 h-5" />

  Behavior:
  - Loads the raw SVG at runtime from priv/static/heroicons/<name>.svg
  - Caches successful reads in `:persistent_term` (read-only, no owner)
  - Falls back to the compiled `<.icon>` component when the SVG file is
    missing or when the requested name is considered unsafe
  """

  use Phoenix.Component

  # Forgiving whitelist: only letters, numbers, dash and underscore
  @safe_re ~r/^[a-zA-Z0-9_\-]+$/

  attr :name, :string, required: true
  attr :class, :string, default: ""

  def dynamic_icon(assigns) do
    name = assigns.name || ""

    if safe_name?(name) do
      svg = cached_svg_for(name)

      if svg do
        assigns = assign(assigns, :svg, svg)

        ~H"""
        {Phoenix.HTML.raw(@svg)}
        """
      else
        # fallback to the compiled icon markup when available (span + classes)
        ~H"""
        <span class={[@name, @class]} />
        """
      end
    else
      # unsafe name -> render an empty placeholder
      ~H"""
      <svg class={@class} aria-hidden="true"></svg>
      """
    end
  end

  defp safe_name?(name) when is_binary(name) do
    String.trim(name) != "" && Regex.match?(@safe_re, name)
  end

  # Was an ETS table created lazily by whichever REQUEST process happened to
  # render an icon first. An ETS table dies with its owner, so the cache was
  # destroyed by the end of that request: every later render re-read every icon
  # from disk, and a process that saw the table exist then had it vanish before
  # its lookup crashed with "the table identifier does not refer to an existing
  # ETS table". `:persistent_term` has no owner and outlives every process.
  # Icons are immutable and few, so each one is written exactly once.
  defp cached_svg_for(name) do
    case :persistent_term.get(cache_key(name), :missing) do
      :missing ->
        case read_svg_from_priv(name) do
          nil ->
            nil

          svg ->
            # Writes trigger a global GC scan, which is why this is only ever
            # reached once per icon per boot.
            :persistent_term.put(cache_key(name), svg)
            svg
        end

      svg ->
        svg
    end
  end

  defp cache_key(name), do: {__MODULE__, name}

  defp read_svg_from_priv(name) do
    # Map name like 'hero-book-open' to a file path under priv/static/heroicons
    path = Path.join(:code.priv_dir(:gamend_web), "static/heroicons/#{name}.svg")

    case File.read(path) do
      {:ok, content} when is_binary(content) -> content
      _ -> nil
    end
  end
end
