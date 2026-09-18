defmodule GamendWeb.Schemas.ErrorResponse do
  @moduledoc """
  Error response schema: every non-2xx JSON body. `errors` is the per-field
  changeset detail `GamendWeb.ChangesetErrors` writes (R12); `reason` is the
  extra word a hook rejection carries.
  """
  require OpenApiSpex
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "ErrorResponse",
    description: "Error response",
    type: :object,
    properties: %{
      error: %Schema{
        type: :string,
        description: "snake_case reason, or a message",
        example: "not_found"
      },
      reason: %Schema{type: :string, description: "Detail from a rejecting hook"},
      errors: %Schema{
        type: :object,
        description: "Per-field validation messages, already translated",
        additionalProperties: %Schema{type: :array, items: %Schema{type: :string}}
      }
    },
    required: [:error]
  })
end
