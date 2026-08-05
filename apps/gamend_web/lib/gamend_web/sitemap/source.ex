defmodule GamendWeb.Sitemap.Source do
  @moduledoc """
  The host's answer to "which pages exist, and what is on them".

  Core owns the dating machinery (`GamendWeb.Sitemap.Lastmod`) but has no idea
  what a host's pages are made of — one host's page is a blog post, another's
  is a slice of a dictionary. The host implements this behaviour; the mix task
  and the change notifier both drive it through here.

  Configure the implementation and where its manifest lives:

      config :gamend_web, GamendWeb.Sitemap,
        source: GamendHost.Sitemap.Source,
        manifest: "priv/sitemap_lastmod.json"

  ## Implementing it

  `c:entries/0` returns one entry per page whose date should be tracked. The
  `:content` is what a visitor reads, parsed — the words, the labels, the
  values — not the bytes of whatever file it was loaded from. That distinction
  is the whole point: it is what makes a re-export or a line-ending change
  invisible to the date.

  Do not include a locale in the key. A page and its translations share one
  date, because they share one source of truth; emitting 30 keys per page
  would multiply the manifest by 30 to store the same date 30 times.
  """

  alias GamendWeb.Sitemap.Lastmod

  @doc """
  Every page to track, keyed by a stable identifier.

  The key is the manifest key and outlives URLs, so prefer something derived
  from the content's identity (`"vocabulary/polish/food"`) over the current
  path. Renaming a route should not reset every date.
  """
  @callback entries() :: [Lastmod.entry()]

  @doc """
  Every public URL a key is visible at — all of its locale variants.

  Only needed to notify search engines of changes; `mix gamend.sitemap.lastmod
  --notify` maps the keys that moved through this and submits the result to
  `GamendWeb.IndexNow`. Routing belongs to the host, so the mapping does too.
  """
  @callback urls(key :: String.t()) :: [String.t()]

  @optional_callbacks urls: 1

  @doc """
  URLs for the keys that changed, via the source's `c:urls/1`.

  An empty list when the source does not implement it — there is nothing
  sensible to guess, and submitting wrong URLs is worse than submitting none.
  """
  @spec urls_for([String.t()]) :: [String.t()]
  def urls_for(keys) do
    module = source()

    if module && function_exported?(module, :urls, 1) do
      Enum.flat_map(keys, &module.urls/1)
    else
      []
    end
  end

  @doc "The configured source module, or nil when the host tracks no dates."
  @spec source() :: module() | nil
  def source, do: config()[:source]

  @doc """
  Path to the manifest.

  The manifest belongs to the host, not to core, so a relative path resolves
  against the working directory — the project root under Mix and the release
  root otherwise — rather than against any application's `priv/`. Hosts whose
  runtime working directory is not the checkout should configure an absolute
  path.
  """
  @spec manifest_path() :: Path.t()
  def manifest_path do
    path = config()[:manifest] || "priv/sitemap_lastmod.json"

    if Path.type(path) == :absolute, do: path, else: Path.expand(path, File.cwd!())
  end

  @doc """
  The manifest, cached in `:persistent_term` and re-read when the file changes.

  Sitemap requests are rare and the manifest is large — 9,000 pages is well
  over a megabyte of JSON — so decoding it per request would be the most
  expensive thing a sitemap does. Caching on mtime keeps that to one decode,
  while still picking up a restamped manifest without a restart, which matters
  when the file is bind-mounted rather than baked into the image.
  """
  @spec manifest() :: Lastmod.manifest()
  def manifest do
    path = manifest_path()
    mtime = mtime(path)

    case :persistent_term.get({__MODULE__, :manifest}, nil) do
      {^mtime, manifest} ->
        manifest

      _ ->
        manifest = Lastmod.load(path)
        :persistent_term.put({__MODULE__, :manifest}, {mtime, manifest})
        manifest
    end
  end

  defp mtime(path) do
    case File.stat(path, time: :posix) do
      {:ok, %File.Stat{mtime: mtime, size: size}} -> {mtime, size}
      {:error, reason} -> reason
    end
  end

  defp config, do: Application.get_env(:gamend_web, GamendWeb.Sitemap, [])
end
