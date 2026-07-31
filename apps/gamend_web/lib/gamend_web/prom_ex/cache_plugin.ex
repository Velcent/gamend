defmodule GamendWeb.PromEx.CachePlugin do
  @moduledoc """
  Custom PromEx plugin exporting cache-effectiveness and overload metrics.

  Tracks:

  - `gamend_cache_reads_total` — counter tagged by `prefix` (first
    element of the cache key tuple) and `outcome` (`hit`/`miss`), from
    Nebulex `[:gamend, :cache, :command, :stop]` events (`:fetch` only).
  - `gamend_rate_limit_denies_total` — counter tagged by `scope`
    (`auth`/`general`/`ws`/…), emitted by `GamendWeb.RateLimit`.
  - `gamend_async_overload_total` — async tasks run inline because
    `Gamend.TaskSupervisor` was at capacity.
  """

  use PromEx.Plugin

  alias Gamend.Cache.Stats

  @impl true
  def event_metrics(_opts) do
    [
      Event.build(
        :gamend_cache_metrics,
        [
          counter(
            [:gamend, :cache, :reads, :total],
            event_name: [:gamend, :cache, :command, :stop],
            measurement: :duration,
            description: "Cache reads by key prefix and hit/miss outcome.",
            keep: fn metadata ->
              metadata.command == :fetch and Stats.classify_result(metadata.result) != :ignore
            end,
            tags: [:prefix, :outcome],
            tag_values: fn metadata ->
              %{
                prefix: metadata.args |> hd() |> Stats.key_prefix(),
                outcome: Stats.classify_result(metadata.result)
              }
            end
          ),
          counter(
            [:gamend, :rate_limit, :denies, :total],
            event_name: [:gamend, :rate_limit, :deny],
            measurement: :count,
            description: "Rate limiter denials by scope.",
            tags: [:scope]
          ),
          counter(
            [:gamend, :async, :overload, :total],
            event_name: [:gamend, :async, :overload],
            measurement: :count,
            description: "Async tasks executed inline because the task supervisor was full."
          )
        ]
      )
    ]
  end
end
