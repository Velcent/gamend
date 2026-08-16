defmodule GamendWeb.Api.V1.Admin.AnalyticsController do
  use GamendWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Gamend.Analytics
  alias OpenApiSpex.Schema

  tags(["Admin – Analytics"])

  @rate %Schema{
    type: :number,
    format: :float,
    nullable: true,
    description: "0.0–1.0, or null when there is no cohort / denominator yet"
  }

  @summary_schema %Schema{
    type: :object,
    description: "Activity and retention as of a UTC day",
    properties: %{
      day: %Schema{type: :string, format: :date},
      dau: %Schema{type: :integer},
      wau: %Schema{type: :integer},
      mau: %Schema{type: :integer},
      stickiness: @rate,
      new_users_7d: %Schema{type: :integer},
      new_users_30d: %Schema{type: :integer},
      d1: @rate,
      d7: @rate,
      d30: @rate,
      payers_30d: %Schema{type: :integer},
      conversion_30d: @rate
    }
  }

  @daily_schema %Schema{
    type: :object,
    properties: %{
      days: %Schema{type: :integer},
      series: %Schema{
        type: :array,
        description: "Oldest first",
        items: %Schema{
          type: :object,
          properties: %{
            day: %Schema{type: :string, format: :date},
            active: %Schema{type: :integer},
            new_users: %Schema{type: :integer},
            d1: @rate,
            d7: @rate,
            d30: @rate
          }
        }
      }
    }
  }

  @error_schema %Schema{type: :object, properties: %{error: %Schema{type: :string}}}

  operation(:show,
    operation_id: "admin_get_analytics_summary",
    summary: "DAU / WAU / MAU, D1 / D7 / D30 and payer conversion (admin)",
    description:
      "Same numbers as the /admin/analytics page. Days are UTC. Retention is pooled " <>
        "over the sign-up cohorts of the last 60 days that have reached each horizon.",
    security: [%{"authorization" => []}],
    responses: [
      ok: {"Summary", "application/json", @summary_schema},
      unauthorized: {"Not authenticated", "application/json", @error_schema},
      forbidden: {"Admin required", "application/json", @error_schema}
    ]
  )

  def show(conn, _params), do: json(conn, Analytics.summary())

  operation(:daily,
    operation_id: "admin_get_analytics_daily",
    summary: "Per-day active / new users and cohort retention (admin)",
    security: [%{"authorization" => []}],
    parameters: [
      days: [
        in: :query,
        schema: %Schema{type: :integer, minimum: 1, maximum: 365, default: 30},
        description: "How many UTC days back, ending today"
      ]
    ],
    responses: [
      ok: {"Series", "application/json", @daily_schema},
      unauthorized: {"Not authenticated", "application/json", @error_schema},
      forbidden: {"Admin required", "application/json", @error_schema}
    ]
  )

  def daily(conn, params) do
    days = parse_days(params["days"], 30)
    json(conn, %{days: days, series: Analytics.daily_series(days)})
  end

  operation(:snapshot,
    operation_id: "admin_get_analytics_snapshot",
    summary: "Live counters: players, lobbies, parties, quests, matchmaking, tournaments (admin)",
    description:
      "The same composition the public /api/v1/stats serves when public stats are enabled; " <>
        "always available to admins.",
    security: [%{"authorization" => []}],
    responses: [
      ok: {"Snapshot", "application/json", %Schema{type: :object}},
      unauthorized: {"Not authenticated", "application/json", @error_schema},
      forbidden: {"Admin required", "application/json", @error_schema}
    ]
  )

  def snapshot(conn, _params), do: json(conn, Analytics.snapshot())

  @economy_schema %Schema{
    type: :object,
    properties: %{
      days: %Schema{type: :integer},
      totals: %Schema{
        type: :array,
        description: "Per currency + ledger reason over the window, largest |net| first",
        items: %Schema{
          type: :object,
          properties: %{
            currency: %Schema{type: :string},
            reason: %Schema{type: :string},
            granted: %Schema{type: :integer},
            spent: %Schema{type: :integer},
            net: %Schema{type: :integer},
            entries: %Schema{type: :integer}
          }
        }
      },
      flow: %Schema{
        type: :array,
        description: "Same, per UTC day, newest first",
        items: %Schema{
          type: :object,
          properties: %{
            day: %Schema{type: :string, format: :date},
            currency: %Schema{type: :string},
            reason: %Schema{type: :string},
            granted: %Schema{type: :integer},
            spent: %Schema{type: :integer},
            entries: %Schema{type: :integer}
          }
        }
      }
    }
  }

  operation(:economy,
    operation_id: "admin_get_analytics_economy",
    summary: "Currency granted / spent per day per ledger reason (admin)",
    security: [%{"authorization" => []}],
    parameters: [
      days: [
        in: :query,
        schema: %Schema{type: :integer, minimum: 1, maximum: 365, default: 7}
      ],
      currency: [
        in: :query,
        schema: %Schema{type: :string},
        description: "Only this wallet currency (e.g. coins)"
      ]
    ],
    responses: [
      ok: {"Economy flow", "application/json", @economy_schema},
      unauthorized: {"Not authenticated", "application/json", @error_schema},
      forbidden: {"Admin required", "application/json", @error_schema}
    ]
  )

  def economy(conn, params) do
    days = parse_days(params["days"], 7)
    opts = if c = blank_to_nil(params["currency"]), do: [currency: c], else: []

    json(conn, %{
      days: days,
      totals: Analytics.economy_totals(days, opts),
      flow: Analytics.economy_flow(days, opts)
    })
  end

  @counts_schema %Schema{
    type: :object,
    properties: %{
      key: %Schema{type: :string},
      days: %Schema{type: :integer},
      totals: %Schema{
        type: :array,
        items: %Schema{
          type: :object,
          properties: %{key: %Schema{type: :string}, total: %Schema{type: :integer}}
        }
      },
      series: %Schema{
        type: :object,
        description: "key → { \"YYYY-MM-DD\" → count }",
        additionalProperties: %Schema{
          type: :object,
          additionalProperties: %Schema{type: :integer}
        }
      }
    }
  }

  operation(:counts,
    operation_id: "admin_get_analytics_counts",
    summary: "Daily counters by key or prefix (admin)",
    description:
      "Game-defined counters written with Gamend.Analytics.count/3, e.g. level.finished. " <>
        "End key with * for a prefix family (level.*).",
    security: [%{"authorization" => []}],
    parameters: [
      key: [in: :query, schema: %Schema{type: :string, default: "*"}, required: false],
      days: [
        in: :query,
        schema: %Schema{type: :integer, minimum: 1, maximum: 365, default: 7}
      ]
    ],
    responses: [
      ok: {"Counters", "application/json", @counts_schema},
      unauthorized: {"Not authenticated", "application/json", @error_schema},
      forbidden: {"Admin required", "application/json", @error_schema}
    ]
  )

  def counts(conn, params) do
    days = parse_days(params["days"], 7)
    key = blank_to_nil(params["key"]) || "*"
    series = Analytics.counts(key, days)

    json(conn, %{
      key: key,
      days: days,
      totals: Enum.map(Analytics.count_totals(key, days), fn {k, n} -> %{key: k, total: n} end),
      series:
        Map.new(series, fn {k, by_day} ->
          {k, Map.new(by_day, fn {day, n} -> {Date.to_iso8601(day), n} end)}
        end)
    })
  end

  defp parse_days(nil, default), do: default

  defp parse_days(value, default) when is_binary(value) do
    case Integer.parse(value) do
      {n, ""} when n >= 1 and n <= 365 -> n
      _ -> default
    end
  end

  defp parse_days(value, _default) when is_integer(value) and value >= 1 and value <= 365,
    do: value

  defp parse_days(_, default), do: default

  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(""), do: nil
  defp blank_to_nil(v) when is_binary(v), do: String.trim(v)
  defp blank_to_nil(_), do: nil
end
