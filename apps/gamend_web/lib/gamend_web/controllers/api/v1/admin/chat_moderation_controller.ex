defmodule GamendWeb.Api.V1.Admin.ChatModerationController do
  @moduledoc """
  Admin API for chat moderation: the report queue, mutes and the word filter.

  Parity with the admin console — everything the moderation pages can click is
  callable from a script. Global mutes live only here and on the admin UI (the
  player-facing routes are scoped to a lobby, group or party).
  """
  use GamendWeb, :controller
  use OpenApiSpex.ControllerSpecs

  import GamendWeb.Helpers.ParamParser

  alias Gamend.Accounts.Scope
  alias Gamend.Accounts.User
  alias Gamend.Chat.Moderation
  alias Gamend.Chat.Report
  alias Gamend.Chat.Reports
  alias OpenApiSpex.Schema

  tags(["Admin – Chat"])

  @error_schema %Schema{
    type: :object,
    properties: %{error: %Schema{type: :string}}
  }

  @meta_schema %Schema{
    type: :object,
    properties: %{
      page: %Schema{type: :integer},
      page_size: %Schema{type: :integer},
      count: %Schema{type: :integer},
      total_count: %Schema{type: :integer},
      total_pages: %Schema{type: :integer},
      has_more: %Schema{type: :boolean}
    }
  }

  @report_schema %Schema{
    type: :object,
    properties: %{
      id: %Schema{type: :string, format: :uuid},
      reporter_id: %Schema{type: :string, description: "Empty when the word filter filed it"},
      reporter_name: %Schema{type: :string},
      reported_user_id: %Schema{type: :string, format: :uuid},
      reported_user_name: %Schema{type: :string},
      message_id: %Schema{type: :string},
      content_snapshot: %Schema{type: :string},
      reason: %Schema{type: :string},
      status: %Schema{type: :string, enum: ["open", "reviewing", "actioned", "dismissed"]},
      resolved_by: %Schema{type: :string},
      resolved_by_name: %Schema{type: :string},
      resolution_note: %Schema{type: :string},
      resolved_at: %Schema{type: :string, format: :"date-time", nullable: true},
      inserted_at: %Schema{type: :string, format: :"date-time"},
      updated_at: %Schema{type: :string, format: :"date-time"}
    }
  }

  @mute_schema %Schema{
    type: :object,
    properties: %{
      id: %Schema{type: :string, format: :uuid},
      user_id: %Schema{type: :string, format: :uuid},
      user_name: %Schema{type: :string},
      scope: %Schema{type: :string, enum: ["global", "lobby", "group", "party"]},
      scope_ref_id: %Schema{type: :string, description: "Empty for a global mute"},
      expires_at: %Schema{type: :string, format: :"date-time", nullable: true},
      reason: %Schema{type: :string},
      muted_by: %Schema{type: :string},
      muted_by_name: %Schema{type: :string},
      inserted_at: %Schema{type: :string, format: :"date-time"},
      updated_at: %Schema{type: :string, format: :"date-time"}
    }
  }

  @filter_word_schema %Schema{
    type: :object,
    properties: %{
      id: %Schema{type: :string, format: :uuid},
      word: %Schema{type: :string},
      severity: %Schema{type: :string, enum: ["block", "mask", "flag"]},
      match_mode: %Schema{type: :string, enum: ["substring", "exact"]},
      lang: %Schema{type: :string, description: "Bundled-list provenance, empty when hand-added"},
      inserted_at: %Schema{type: :string, format: :"date-time"},
      updated_at: %Schema{type: :string, format: :"date-time"}
    }
  }

  # ---------------------------------------------------------------------------
  # Reports
  # ---------------------------------------------------------------------------

  operation(:list_reports,
    operation_id: "admin_list_chat_reports",
    summary: "List chat reports (admin)",
    description: "The moderation queue, newest first. Filter by status or by the users involved.",
    security: [%{"authorization" => []}],
    parameters: [
      status: [
        in: :query,
        schema: %Schema{type: :string, enum: ["open", "reviewing", "actioned", "dismissed"]}
      ],
      reported_user_id: [in: :query, schema: %Schema{type: :string, format: :uuid}],
      reporter_id: [in: :query, schema: %Schema{type: :string, format: :uuid}],
      page: [in: :query, schema: %Schema{type: :integer, default: 1}],
      page_size: [in: :query, schema: %Schema{type: :integer, default: 25}]
    ],
    responses: [
      ok:
        {"Reports", "application/json",
         %Schema{
           type: :object,
           properties: %{
             data: %Schema{type: :array, items: @report_schema},
             meta: @meta_schema
           }
         }},
      bad_request: {"Invalid id", "application/json", @error_schema}
    ]
  )

  def list_reports(conn, params) do
    case id_filters(params, ["reported_user_id", "reporter_id"]) do
      :error ->
        invalid_id(conn)

      {:ok, filters} ->
        filters = maybe_put_string_filter(filters, "status", params["status"])
        {page, page_size} = GamendWeb.Pagination.params(params)

        reports = Reports.list_reports(filters, page: page, page_size: page_size)
        total_count = Reports.count_reports(filters)

        json(conn, %{
          data: Enum.map(reports, &serialize_report/1),
          meta: GamendWeb.Pagination.meta(page, page_size, length(reports), total_count)
        })
    end
  end

  operation(:resolve_report,
    operation_id: "admin_resolve_chat_report",
    summary: "Resolve a chat report (admin)",
    description:
      "Sets the report's status and records the calling admin as its resolver. " <>
        "Muting the reported player or deleting the message are separate calls.",
    security: [%{"authorization" => []}],
    parameters: [
      id: [in: :path, schema: %Schema{type: :string, format: :uuid}, required: true]
    ],
    request_body:
      {"Resolution", "application/json",
       %Schema{
         type: :object,
         required: [:status],
         properties: %{
           status: %Schema{
             type: :string,
             enum: ["open", "reviewing", "actioned", "dismissed"]
           },
           note: %Schema{type: :string, description: "Moderator note, not shown to players"}
         }
       }},
    responses: [
      ok:
        {"Resolved", "application/json",
         %Schema{type: :object, properties: %{data: @report_schema}}},
      bad_request: {"Invalid id", "application/json", @error_schema},
      not_found: {"Not found", "application/json", @error_schema},
      unprocessable_entity: {"Invalid status", "application/json", @error_schema}
    ]
  )

  def resolve_report(conn, %{"id" => id} = params) do
    status = params["status"]

    case {parse_id(id), status in Report.statuses()} do
      {nil, _valid_status} ->
        invalid_id(conn)

      {_report_id, false} ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: "invalid_status"})

      {report_id, true} ->
        attrs = %{"note" => params["note"], "resolved_by" => admin_id(conn)}

        case Reports.resolve_report(report_id, status, attrs) do
          {:ok, report} -> json(conn, %{data: serialize_report(report)})
          {:error, :not_found} -> not_found(conn)
          {:error, error} -> write_error(conn, error)
        end
    end
  end

  operation(:delete_report,
    operation_id: "admin_delete_chat_report",
    summary: "Delete a chat report (admin)",
    description: "Removes the report row itself. Resolving is usually what you want instead.",
    security: [%{"authorization" => []}],
    parameters: [
      id: [in: :path, schema: %Schema{type: :string, format: :uuid}, required: true]
    ],
    responses: [
      ok: {"Deleted", "application/json", %Schema{type: :object}},
      bad_request: {"Invalid id", "application/json", @error_schema},
      not_found: {"Not found", "application/json", @error_schema}
    ]
  )

  def delete_report(conn, %{"id" => id}) do
    with_record(conn, id, &Reports.get_report/1, fn report ->
      case Reports.delete_report(report) do
        {:ok, _report} -> json(conn, %{ok: true})
        {:error, error} -> write_error(conn, error)
      end
    end)
  end

  # ---------------------------------------------------------------------------
  # Mutes
  # ---------------------------------------------------------------------------

  operation(:list_mutes,
    operation_id: "admin_list_chat_mutes",
    summary: "List chat mutes (admin)",
    description: "Every mute, newest first. Pass `active=true` to hide expired ones.",
    security: [%{"authorization" => []}],
    parameters: [
      user_id: [in: :query, schema: %Schema{type: :string, format: :uuid}],
      scope: [
        in: :query,
        schema: %Schema{type: :string, enum: ["global", "lobby", "group", "party"]}
      ],
      scope_ref_id: [in: :query, schema: %Schema{type: :string, format: :uuid}],
      active: [in: :query, schema: %Schema{type: :boolean}],
      page: [in: :query, schema: %Schema{type: :integer, default: 1}],
      page_size: [in: :query, schema: %Schema{type: :integer, default: 25}]
    ],
    responses: [
      ok:
        {"Mutes", "application/json",
         %Schema{
           type: :object,
           properties: %{
             data: %Schema{type: :array, items: @mute_schema},
             meta: @meta_schema
           }
         }},
      bad_request: {"Invalid id", "application/json", @error_schema}
    ]
  )

  def list_mutes(conn, params) do
    case id_filters(params, ["user_id", "scope_ref_id"]) do
      :error ->
        invalid_id(conn)

      {:ok, filters} ->
        filters =
          filters
          |> maybe_put_string_filter("scope", params["scope"])
          |> maybe_put_bool_filter("active", params["active"])

        {page, page_size} = GamendWeb.Pagination.params(params)

        mutes = Moderation.list_mutes(filters, page: page, page_size: page_size)
        total_count = Moderation.count_mutes(filters)

        json(conn, %{
          data: Enum.map(mutes, &serialize_mute/1),
          meta: GamendWeb.Pagination.meta(page, page_size, length(mutes), total_count)
        })
    end
  end

  operation(:create_mute,
    operation_id: "admin_create_chat_mute",
    summary: "Mute a player (admin)",
    description:
      "Silences a player. `global` covers every chat including friend DMs and is " <>
        "admin-only; the scoped variants take the lobby, group or party id in " <>
        "`scope_ref_id`. Re-muting an already-muted player replaces the mute.",
    security: [%{"authorization" => []}],
    request_body:
      {"Mute", "application/json",
       %Schema{
         type: :object,
         required: [:user_id],
         properties: %{
           user_id: %Schema{type: :string, format: :uuid, description: "Player to mute"},
           scope: %Schema{
             type: :string,
             enum: ["global", "lobby", "group", "party"],
             default: "global"
           },
           scope_ref_id: %Schema{
             type: :string,
             format: :uuid,
             description: "Lobby, group or party id. Omit for a global mute."
           },
           expires_at: %Schema{
             type: :string,
             format: :"date-time",
             nullable: true,
             description: "When the mute lifts. Omit for a permanent mute."
           },
           reason: %Schema{type: :string}
         }
       }},
    responses: [
      ok:
        {"Muted", "application/json", %Schema{type: :object, properties: %{data: @mute_schema}}},
      bad_request: {"Invalid id", "application/json", @error_schema},
      unprocessable_entity: {"Invalid mute", "application/json", @error_schema}
    ]
  )

  def create_mute(conn, params) do
    case {parse_id(params["user_id"]), param_id(params["scope_ref_id"])} do
      {nil, _scope_ref} ->
        invalid_id(conn)

      {_user_id, :error} ->
        invalid_id(conn)

      {user_id, {:ok, scope_ref_id}} ->
        attrs = %{
          "expires_at" => params["expires_at"],
          "reason" => params["reason"],
          "muted_by" => admin_id(conn)
        }

        case Moderation.mute_user(user_id, params["scope"] || "global", scope_ref_id, attrs) do
          {:ok, mute} -> json(conn, %{data: serialize_mute(mute)})
          {:error, error} -> write_error(conn, error)
        end
    end
  end

  operation(:delete_mute,
    operation_id: "admin_delete_chat_mute",
    summary: "Lift a mute (admin)",
    security: [%{"authorization" => []}],
    parameters: [
      id: [in: :path, schema: %Schema{type: :string, format: :uuid}, required: true]
    ],
    responses: [
      ok: {"Unmuted", "application/json", %Schema{type: :object}},
      bad_request: {"Invalid id", "application/json", @error_schema},
      not_found: {"Not found", "application/json", @error_schema}
    ]
  )

  def delete_mute(conn, %{"id" => id}) do
    with_record(conn, id, &Moderation.get_mute/1, fn mute ->
      {:ok, count} = Moderation.unmute_user(mute.user_id, mute.scope, mute.scope_ref_id)
      json(conn, %{ok: true, removed: count})
    end)
  end

  # ---------------------------------------------------------------------------
  # Word filter
  # ---------------------------------------------------------------------------

  operation(:list_filter_words,
    operation_id: "admin_list_chat_filter_words",
    summary: "List blocklist words (admin)",
    description:
      "The chat word blocklist, plus the languages with a bundled list available " <>
        "to import. Matching is language-agnostic; `lang` is provenance only.",
    security: [%{"authorization" => []}],
    parameters: [
      word: [in: :query, schema: %Schema{type: :string}, description: "Substring match"],
      severity: [in: :query, schema: %Schema{type: :string, enum: ["block", "mask", "flag"]}],
      lang: [in: :query, schema: %Schema{type: :string}],
      page: [in: :query, schema: %Schema{type: :integer, default: 1}],
      page_size: [in: :query, schema: %Schema{type: :integer, default: 25}]
    ],
    responses: [
      ok:
        {"Filter words", "application/json",
         %Schema{
           type: :object,
           properties: %{
             data: %Schema{type: :array, items: @filter_word_schema},
             languages: %Schema{type: :array, items: %Schema{type: :string}},
             meta: @meta_schema
           }
         }}
    ]
  )

  def list_filter_words(conn, params) do
    filters =
      %{}
      |> maybe_put_string_filter("word", params["word"])
      |> maybe_put_string_filter("severity", params["severity"])
      |> maybe_put_string_filter("lang", params["lang"])

    {page, page_size} = GamendWeb.Pagination.params(params)

    words = Moderation.list_filter_words(filters, page: page, page_size: page_size)
    total_count = Moderation.count_filter_words(filters)

    json(conn, %{
      data: Enum.map(words, &serialize_filter_word/1),
      languages: Moderation.bundled_languages(),
      meta: GamendWeb.Pagination.meta(page, page_size, length(words), total_count)
    })
  end

  operation(:create_filter_word,
    operation_id: "admin_create_chat_filter_word",
    summary: "Add a blocklist word (admin)",
    description:
      "The word is normalized (lower-cased, leetspeak folded) before it is stored, " <>
        "so it matches the same way the runtime filter does.",
    security: [%{"authorization" => []}],
    request_body:
      {"Filter word", "application/json",
       %Schema{
         type: :object,
         required: [:word],
         properties: %{
           word: %Schema{type: :string},
           severity: %Schema{
             type: :string,
             enum: ["block", "mask", "flag"],
             default: "block",
             description: "block rejects, mask stars out the hit, flag files a report"
           },
           match_mode: %Schema{
             type: :string,
             enum: ["substring", "exact"],
             default: "substring"
           },
           lang: %Schema{type: :string}
         }
       }},
    responses: [
      ok:
        {"Created", "application/json",
         %Schema{type: :object, properties: %{data: @filter_word_schema}}},
      unprocessable_entity: {"Invalid word or cap reached", "application/json", @error_schema}
    ]
  )

  def create_filter_word(conn, params) do
    attrs = %{
      "word" => params["word"],
      "severity" => params["severity"] || "block",
      "match_mode" => params["match_mode"] || "substring",
      "lang" => params["lang"]
    }

    case Moderation.create_filter_word(attrs) do
      {:ok, word} -> json(conn, %{data: serialize_filter_word(word)})
      {:error, error} -> write_error(conn, error)
    end
  end

  operation(:update_filter_word,
    operation_id: "admin_update_chat_filter_word",
    summary: "Update a blocklist word (admin)",
    security: [%{"authorization" => []}],
    parameters: [
      id: [in: :path, schema: %Schema{type: :string, format: :uuid}, required: true]
    ],
    request_body:
      {"Filter word", "application/json",
       %Schema{
         type: :object,
         properties: %{
           word: %Schema{type: :string},
           severity: %Schema{type: :string, enum: ["block", "mask", "flag"]},
           match_mode: %Schema{type: :string, enum: ["substring", "exact"]},
           lang: %Schema{type: :string}
         }
       }},
    responses: [
      ok:
        {"Updated", "application/json",
         %Schema{type: :object, properties: %{data: @filter_word_schema}}},
      bad_request: {"Invalid id", "application/json", @error_schema},
      not_found: {"Not found", "application/json", @error_schema},
      unprocessable_entity: {"Invalid word", "application/json", @error_schema}
    ]
  )

  def update_filter_word(conn, %{"id" => id} = params) do
    with_record(conn, id, &Moderation.get_filter_word/1, fn word ->
      attrs = Map.take(params, ["word", "severity", "match_mode", "lang"])

      case Moderation.update_filter_word(word, attrs) do
        {:ok, updated} -> json(conn, %{data: serialize_filter_word(updated)})
        {:error, error} -> write_error(conn, error)
      end
    end)
  end

  operation(:delete_filter_word,
    operation_id: "admin_delete_chat_filter_word",
    summary: "Remove a blocklist word (admin)",
    security: [%{"authorization" => []}],
    parameters: [
      id: [in: :path, schema: %Schema{type: :string, format: :uuid}, required: true]
    ],
    responses: [
      ok: {"Deleted", "application/json", %Schema{type: :object}},
      bad_request: {"Invalid id", "application/json", @error_schema},
      not_found: {"Not found", "application/json", @error_schema}
    ]
  )

  def delete_filter_word(conn, %{"id" => id}) do
    with_record(conn, id, &Moderation.get_filter_word/1, fn word ->
      case Moderation.delete_filter_word(word) do
        {:ok, _word} -> json(conn, %{ok: true})
        {:error, error} -> write_error(conn, error)
      end
    end)
  end

  operation(:import_filter_words,
    operation_id: "admin_import_chat_filter_words",
    summary: "Import a bundled word list (admin)",
    description:
      "Inserts the words bundled at `priv/chat_filter/<lang>.txt` at the chosen " <>
        "severity. Duplicates are skipped and `max_chat_filter_words` still applies. " <>
        "The importable languages are listed by the filter-word index.",
    security: [%{"authorization" => []}],
    request_body:
      {"Import", "application/json",
       %Schema{
         type: :object,
         required: [:lang],
         properties: %{
           lang: %Schema{type: :string, description: "Bundled list to import, e.g. \"en\""},
           severity: %Schema{
             type: :string,
             enum: ["block", "mask", "flag"],
             default: "block"
           }
         }
       }},
    responses: [
      ok:
        {"Imported", "application/json",
         %Schema{
           type: :object,
           properties: %{ok: %Schema{type: :boolean}, imported: %Schema{type: :integer}}
         }},
      unprocessable_entity: {"Unknown language or cap reached", "application/json", @error_schema}
    ]
  )

  def import_filter_words(conn, params) do
    severity = if is_binary(params["severity"]), do: params["severity"], else: "block"

    case params["lang"] do
      lang when is_binary(lang) ->
        case Moderation.import_bundled_list(lang, severity) do
          {:ok, count} -> json(conn, %{ok: true, imported: count})
          {:error, error} -> write_error(conn, error)
        end

      _lang ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: "unknown_language"})
    end
  end

  operation(:delete_filter_words_by_lang,
    operation_id: "admin_delete_chat_filter_words_by_lang",
    summary: "Remove an imported word list (admin)",
    description:
      "Deletes every blocklist entry tagged with the given language — the bulk " <>
        "undo for an import. Hand-added words have no language tag and are untouched.",
    security: [%{"authorization" => []}],
    parameters: [
      lang: [
        in: :query,
        required: true,
        schema: %Schema{type: :string},
        description: "Language tag to remove, e.g. \"en\""
      ]
    ],
    responses: [
      ok:
        {"Removed", "application/json",
         %Schema{
           type: :object,
           properties: %{ok: %Schema{type: :boolean}, removed: %Schema{type: :integer}}
         }},
      bad_request: {"Missing lang", "application/json", @error_schema}
    ]
  )

  def delete_filter_words_by_lang(conn, params) do
    case params["lang"] do
      lang when is_binary(lang) and lang != "" ->
        json(conn, %{ok: true, removed: Moderation.delete_filter_words_by_lang(lang)})

      _lang ->
        conn |> put_status(:bad_request) |> json(%{error: "lang_required"})
    end
  end

  operation(:test_phrase,
    operation_id: "admin_test_chat_phrase",
    summary: "Test a phrase against the filter (admin)",
    description:
      "Runs the phrase through the live blocklist and reports every hit plus what " <>
        "the chat pipeline would do with it: `block`, `mask`, `flag` or `allow`.",
    security: [%{"authorization" => []}],
    request_body:
      {"Phrase", "application/json",
       %Schema{
         type: :object,
         required: [:phrase],
         properties: %{phrase: %Schema{type: :string}}
       }},
    responses: [
      ok:
        {"Result", "application/json",
         %Schema{
           type: :object,
           properties: %{
             data: %Schema{
               type: :object,
               properties: %{
                 phrase: %Schema{type: :string},
                 action: %Schema{
                   type: :string,
                   enum: ["block", "mask", "flag", "allow"]
                 },
                 content: %Schema{
                   type: :string,
                   description: "What would be stored; empty when blocked"
                 },
                 flagged_words: %Schema{type: :array, items: %Schema{type: :string}},
                 hits: %Schema{
                   type: :array,
                   items: %Schema{
                     type: :object,
                     properties: %{
                       word: %Schema{type: :string},
                       severity: %Schema{type: :string},
                       match_mode: %Schema{type: :string}
                     }
                   }
                 }
               }
             }
           }
         }}
    ]
  )

  def test_phrase(conn, params) do
    phrase = if is_binary(params["phrase"]), do: params["phrase"], else: ""

    hits =
      phrase
      |> Moderation.hits()
      |> Enum.map(fn {word, severity, match_mode} ->
        %{word: word, severity: severity, match_mode: match_mode}
      end)

    json(conn, %{data: Map.merge(%{phrase: phrase, hits: hits}, outcome(phrase))})
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp outcome(phrase) do
    case Moderation.check_content(phrase) do
      {:error, :blocked_content} ->
        %{action: "block", content: "", flagged_words: []}

      {:ok, content, flagged} ->
        %{action: action(phrase, content, flagged), content: content, flagged_words: flagged}
    end
  end

  defp action(phrase, content, flagged) do
    cond do
      content != phrase -> "mask"
      flagged != [] -> "flag"
      true -> "allow"
    end
  end

  defp serialize_report(report) do
    %{
      id: report.id,
      reporter_id: report.reporter_id || "",
      reporter_name: display_name(report, :reporter),
      reported_user_id: report.reported_user_id,
      reported_user_name: display_name(report, :reported_user),
      message_id: report.message_id || "",
      content_snapshot: report.content_snapshot || "",
      reason: report.reason || "",
      status: report.status || "open",
      resolved_by: report.resolved_by || "",
      resolved_by_name: display_name(report, :resolved_by_user),
      resolution_note: report.resolution_note || "",
      resolved_at: report.resolved_at,
      inserted_at: report.inserted_at,
      updated_at: report.updated_at
    }
  end

  defp serialize_mute(mute) do
    %{
      id: mute.id,
      user_id: mute.user_id,
      user_name: display_name(mute, :user),
      scope: mute.scope || "global",
      scope_ref_id: mute.scope_ref_id || "",
      expires_at: mute.expires_at,
      reason: mute.reason || "",
      muted_by: mute.muted_by || "",
      muted_by_name: display_name(mute, :muted_by_user),
      inserted_at: mute.inserted_at,
      updated_at: mute.updated_at
    }
  end

  defp serialize_filter_word(word) do
    %{
      id: word.id,
      word: word.word,
      severity: word.severity,
      match_mode: word.match_mode,
      lang: word.lang || "",
      inserted_at: word.inserted_at,
      updated_at: word.updated_at
    }
  end

  defp display_name(struct, field) do
    case Map.get(struct, field) do
      %{display_name: name} when is_binary(name) -> name
      _assoc -> ""
    end
  end

  defp admin_id(conn) do
    case Scope.user(conn.assigns[:current_scope]) do
      %User{id: id} -> id
      _ -> nil
    end
  end

  # An id-typed column raises on a non-UUID query param, so filters are cast up
  # front rather than handed to the context.
  defp id_filters(params, keys) do
    Enum.reduce_while(keys, {:ok, %{}}, fn key, {:ok, filters} ->
      case param_id(params[key]) do
        {:ok, nil} -> {:cont, {:ok, filters}}
        {:ok, id} -> {:cont, {:ok, Map.put(filters, key, id)}}
        :error -> {:halt, :error}
      end
    end)
  end

  defp param_id(nil), do: {:ok, nil}
  defp param_id(""), do: {:ok, nil}

  defp param_id(value) do
    case parse_id(value) do
      nil -> :error
      id -> {:ok, id}
    end
  end

  defp with_record(conn, id, fetch, fun) do
    case parse_id(id) do
      nil ->
        invalid_id(conn)

      record_id ->
        case fetch.(record_id) do
          nil -> not_found(conn)
          record -> fun.(record)
        end
    end
  end

  defp invalid_id(conn), do: conn |> put_status(:bad_request) |> json(%{error: "invalid_id"})

  defp not_found(conn), do: conn |> put_status(:not_found) |> json(%{error: "not_found"})

  defp write_error(conn, %Ecto.Changeset{} = changeset) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{error: "invalid", details: changeset_errors(changeset)})
  end

  defp write_error(conn, reason) do
    conn |> put_status(:unprocessable_entity) |> json(%{error: to_string(reason)})
  end

  defp changeset_errors(%Ecto.Changeset{} = changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
