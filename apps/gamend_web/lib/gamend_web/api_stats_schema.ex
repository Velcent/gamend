defmodule GamendWeb.ApiStatsSchema do
  @moduledoc """
  The OpenAPI response shape shared by every `/<resource>/stats` endpoint.

  All of them answer the same way — a flat object of integer counters under
  `data` — so the schema is built from a field list rather than restated in
  each controller.
  """

  alias OpenApiSpex.Schema

  @doc """
  A `{description, "application/json", schema}` ok-response for the given
  counter fields.

  Nested object fields (a `by_state` map, say) are declared by passing
  `{name, %Schema{}}` instead of a bare atom.
  """
  @spec response(String.t(), [atom() | {atom(), Schema.t()}]) ::
          {String.t(), String.t(), Schema.t()}
  def response(description, fields) when is_list(fields) do
    properties =
      Map.new(fields, fn
        {name, %Schema{} = schema} -> {name, schema}
        name when is_atom(name) -> {name, %Schema{type: :integer}}
      end)

    {description, "application/json",
     %Schema{
       type: :object,
       properties: %{data: %Schema{type: :object, properties: properties}}
     }}
  end
end
