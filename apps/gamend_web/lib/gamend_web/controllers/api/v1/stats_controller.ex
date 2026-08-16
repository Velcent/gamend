defmodule GamendWeb.Api.V1.StatsController do
  @moduledoc """
  `GET /api/v1/stats` — every public counter in one response, from
  `Gamend.Analytics.snapshot/0`. The per-resource `/<resource>/stats`
  endpoints keep working and read the same cached composition; this one saves
  a client six requests. Gated by `:public_stats` like the others.
  """
  use GamendWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Gamend.Analytics
  alias OpenApiSpex.Schema

  tags(["Stats"])

  @counters %Schema{type: :object, additionalProperties: %Schema{type: :integer}}

  operation(:show,
    operation_id: "get_stats",
    summary: "All public server counters in one call",
    description:
      "Players, activity (DAU / WAU / MAU, new users), lobbies, parties, quests, " <>
        "signaling, matchmaking queue and tournaments. Cached for a minute server-side.",
    responses: [
      ok:
        {"Snapshot", "application/json",
         %Schema{
           type: :object,
           properties: %{
             data: %Schema{
               type: :object,
               properties: %{
                 players: @counters,
                 activity: @counters,
                 lobbies: %Schema{type: :object},
                 parties: @counters,
                 quests: @counters,
                 signaling: @counters,
                 matchmaking: %Schema{type: :object},
                 tournaments: %Schema{type: :object}
               }
             }
           }
         }}
    ]
  )

  def show(conn, _params), do: json(conn, %{data: Analytics.snapshot()})
end
