defmodule GamendWeb.Plugs.FeatureGate do
  @moduledoc """
  Plug that gates routes behind a `GamendWeb.Features` flag.

  ## Usage

      plug GamendWeb.Plugs.FeatureGate, feature: :openapi

  When the feature is off, requests are rejected with `404 Not Found` — the
  route reads as nonexistent rather than forbidden, so a disabled endpoint
  leaks nothing about what the deployment runs.
  """

  alias GamendWeb.Features

  @behaviour Plug

  @impl true
  def init(opts), do: %{feature: Keyword.fetch!(opts, :feature)}

  @impl true
  def call(conn, %{feature: feature}) do
    if Features.enabled?(feature) do
      conn
    else
      # A switched-off feature has to look exactly like a page that does not
      # exist — same status, same page — or the difference tells a visitor
      # which features merely happen to be disabled.
      GamendWeb.ErrorResponse.not_found(conn)
    end
  end

  @doc "Whether the feature is enabled. Delegates to `GamendWeb.Features`."
  @spec enabled?(atom()) :: boolean()
  defdelegate enabled?(feature), to: Features
end
