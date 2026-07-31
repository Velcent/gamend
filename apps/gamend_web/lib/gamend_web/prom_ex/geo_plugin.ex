defmodule GamendWeb.PromEx.GeoPlugin do
  @moduledoc """
  Custom PromEx plugin that exports geo-traffic Prometheus metrics.

  Tracks:

  - `gamend_geo_requests_total` — counter, tagged by `country`
    (ISO 3166-1 alpha-2 code, or "XX" for unknown).

  The telemetry event `[:gamend, :geo, :request]` is emitted by
  `GamendWeb.Plugs.GeoCountry` on every HTTP request.
  """

  use PromEx.Plugin

  @impl true
  def event_metrics(_opts) do
    [
      Event.build(
        :gamend_geo_request_metrics,
        [
          counter(
            [:gamend, :geo, :requests, :total],
            event_name: [:gamend, :geo, :request],
            measurement: :count,
            description: "Total HTTP requests by country code.",
            tags: [:country]
          )
        ]
      )
    ]
  end
end
