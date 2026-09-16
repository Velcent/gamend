defmodule GamendWeb.Api.V1.Admin.LeaderboardRecordController do
  use GamendWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Gamend.Leaderboards
  alias Gamend.Leaderboards.Record
  alias OpenApiSpex.Schema

  tags(["Admin – Leaderboards"])

  @error_schema %Schema{type: :object, properties: %{error: %Schema{type: :string}}}

  @record_schema %Schema{
    type: :object,
    properties: %{
      id: %Schema{type: :string, format: :uuid},
      leaderboard_id: %Schema{type: :string, format: :uuid},
      user_id: %Schema{type: :string, format: :uuid, nullable: true},
      label: %Schema{type: :string},
      score: %Schema{type: :integer},
      rank: %Schema{type: :integer, nullable: true},
      metadata: %Schema{type: :object},
      inserted_at: %Schema{type: :string, format: "date-time"},
      updated_at: %Schema{type: :string, format: "date-time"}
    }
  }

  operation(:create,
    operation_id: "admin_submit_leaderboard_score",
    summary: "Submit score (admin)",
    security: [%{"authorization" => []}],
    parameters: [
      id: [in: :path, schema: %Schema{type: :string, format: :uuid}, required: true]
    ],
    request_body: {
      "Score submission",
      "application/json",
      %Schema{
        type: :object,
        properties: %{
          user_id: %Schema{
            type: :string,
            format: :uuid,
            description: "User ID (for user-based records)"
          },
          label: %Schema{
            type: :string,
            description: "Label (for non-user records, e.g. \"English\")"
          },
          score: %Schema{type: :integer},
          metadata: %Schema{type: :object}
        },
        required: [:score]
      }
    },
    responses: [
      ok:
        {"Record", "application/json",
         %Schema{type: :object, properties: %{data: @record_schema}}},
      unauthorized: {"Not authenticated", "application/json", @error_schema},
      forbidden: {"Admin required", "application/json", @error_schema},
      unprocessable_entity: {"Validation failed", "application/json", %Schema{type: :object}},
      not_found: {"Not found", "application/json", @error_schema}
    ]
  )

  def create(conn, %{"id" => leaderboard_id, "label" => label, "score" => score} = params)
      when is_binary(label) and label != "" do
    with_score(conn, score, fn score ->
      leaderboard_id
      |> to_string()
      |> Leaderboards.submit_label_score(label, score, metadata(params))
      |> respond(conn)
    end)
  end

  def create(conn, %{"id" => leaderboard_id, "user_id" => user_id, "score" => score} = params) do
    with_score(conn, score, fn score ->
      leaderboard_id
      |> to_string()
      |> Leaderboards.submit_score(to_string(user_id), score, metadata(params))
      |> respond(conn)
    end)
  end

  # A score arrives as a JSON number or a form string. It was parsed with
  # `String.to_integer/1`, which raises on anything non-numeric — `"abc"`,
  # `"12abc"` — and a float matched no clause at all, so each answered 500.
  # Strict, so a partial number is rejected rather than stored as its prefix.
  defp with_score(conn, raw, fun) do
    case Gamend.Parse.integer(raw) do
      nil -> conn |> put_status(:bad_request) |> json(%{error: "invalid_score"})
      score -> fun.(score)
    end
  end

  defp metadata(params), do: Map.get(params, "metadata") || %{}

  # `submit_score/4` reports a missing board as `:leaderboard_not_found`, which
  # the old clauses did not match — so it fell through to the catch-all and
  # answered 400 instead of 404.
  defp respond({:ok, %Record{} = record}, conn), do: json(conn, %{data: record})

  defp respond({:error, reason}, conn)
       when reason in [:not_found, :leaderboard_not_found, :user_not_found],
       do: conn |> put_status(:not_found) |> json(%{error: to_string(reason)})

  defp respond({:error, %Ecto.Changeset{} = cs}, conn), do: unprocessable(conn, cs)

  defp respond({:error, reason}, conn),
    do: conn |> put_status(:bad_request) |> json(%{error: to_string(reason)})

  operation(:update,
    operation_id: "admin_update_leaderboard_record",
    summary: "Update leaderboard record (admin)",
    security: [%{"authorization" => []}],
    parameters: [
      id: [in: :path, schema: %Schema{type: :string, format: :uuid}, required: true],
      record_id: [in: :path, schema: %Schema{type: :string, format: :uuid}, required: true]
    ],
    request_body: {
      "Record patch",
      "application/json",
      %Schema{
        type: :object,
        properties: %{
          score: %Schema{type: :integer},
          metadata: %Schema{type: :object}
        }
      }
    },
    responses: [
      ok:
        {"Record", "application/json",
         %Schema{type: :object, properties: %{data: @record_schema}}},
      unauthorized: {"Not authenticated", "application/json", @error_schema},
      forbidden: {"Admin required", "application/json", @error_schema},
      not_found: {"Not found", "application/json", @error_schema},
      unprocessable_entity: {"Validation failed", "application/json", %Schema{type: :object}}
    ]
  )

  def update(conn, %{"record_id" => record_id} = params) do
    record_id = to_string(record_id)

    case get_record(record_id) do
      nil ->
        conn |> put_status(:not_found) |> json(%{error: "not_found"})

      record ->
        attrs = Map.drop(params, ["id", "record_id"])

        case Leaderboards.update_record(record, attrs) do
          {:ok, updated} ->
            json(conn, %{data: updated})

          {:error, %Ecto.Changeset{} = cs} ->
            unprocessable(conn, cs)
        end
    end
  end

  operation(:delete,
    operation_id: "admin_delete_leaderboard_record",
    summary: "Delete leaderboard record (admin)",
    security: [%{"authorization" => []}],
    parameters: [
      id: [in: :path, schema: %Schema{type: :string, format: :uuid}, required: true],
      record_id: [in: :path, schema: %Schema{type: :string, format: :uuid}, required: true]
    ],
    responses: [
      ok: {"Deleted", "application/json", %Schema{type: :object}},
      unauthorized: {"Not authenticated", "application/json", @error_schema},
      forbidden: {"Admin required", "application/json", @error_schema},
      not_found: {"Not found", "application/json", @error_schema}
    ]
  )

  def delete(conn, %{"record_id" => record_id}) do
    record_id = to_string(record_id)

    case get_record(record_id) do
      nil ->
        conn |> put_status(:not_found) |> json(%{error: "not_found"})

      record ->
        case Leaderboards.delete_record(record) do
          {:ok, _} ->
            json(conn, %{})

          {:error, %Ecto.Changeset{} = cs} ->
            unprocessable(conn, cs)
        end
    end
  end

  operation(:delete_user,
    operation_id: "admin_delete_leaderboard_user_record",
    summary: "Delete a user's record (admin)",
    security: [%{"authorization" => []}],
    parameters: [
      id: [in: :path, schema: %Schema{type: :string, format: :uuid}, required: true],
      user_id: [in: :path, schema: %Schema{type: :string, format: :uuid}, required: true]
    ],
    responses: [
      ok: {"Deleted", "application/json", %Schema{type: :object}},
      unauthorized: {"Not authenticated", "application/json", @error_schema},
      forbidden: {"Admin required", "application/json", @error_schema}
    ]
  )

  def delete_user(conn, %{"id" => leaderboard_id, "user_id" => user_id}) do
    leaderboard_id = to_string(leaderboard_id)
    user_id = to_string(user_id)

    _ = Leaderboards.delete_user_record(leaderboard_id, user_id)
    json(conn, %{})
  end

  defp get_record(id) do
    Leaderboards.get_record!(id)
  rescue
    Ecto.NoResultsError -> nil
  end
end
