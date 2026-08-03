defmodule GamendWeb.Api.V1.HookController do
  use GamendWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Gamend.Accounts.Scope
  alias Gamend.Hooks.DynamicRpcs
  alias Gamend.Hooks.HookSchemas
  alias Gamend.Hooks.PluginManager
  require Logger

  operation(:index,
    operation_id: "list_hooks",
    summary: "List available hook functions",
    tags: ["Hooks"],
    security: [%{"authorization" => []}],
    responses: [
      ok: {"OK", "application/json", %OpenApiSpex.Schema{type: :object}}
    ]
  )

  def index(conn, _params) do
    static_functions =
      PluginManager.hook_modules()
      |> Enum.flat_map(fn {plugin_name, mod} ->
        Gamend.Hooks.exported_functions(mod)
        |> Enum.map(&Map.merge(&1, %{plugin: plugin_name, dynamic: false}))
      end)

    static_keys =
      static_functions
      |> Enum.map(&{Map.get(&1, :plugin), Map.get(&1, :name)})
      |> MapSet.new()

    dynamic_functions =
      DynamicRpcs.list_all()
      |> Enum.flat_map(fn {plugin_name, exports} ->
        Enum.map(exports, fn export ->
          args = Map.get(export.meta || %{}, :args) || Map.get(export.meta || %{}, "args")
          args_list = List.wrap(args)

          arg_names =
            Enum.map(args_list, fn a ->
              Map.get(a, :name) || Map.get(a, "name") || "arg"
            end)

          arity = length(arg_names)

          doc =
            Map.get(export.meta || %{}, :description) ||
              Map.get(export.meta || %{}, "description")

          signature = to_string(export.hook) <> "(" <> Enum.join(arg_names, ", ") <> ")"

          %{
            plugin: plugin_name,
            name: export.hook,
            dynamic: true,
            meta: export.meta,
            arities: [arity],
            signatures: [
              %{
                arity: arity,
                signature: signature,
                doc: doc,
                example_args: Jason.encode!(arg_names)
              }
            ]
          }
        end)
      end)
      |> Enum.reject(fn f -> MapSet.member?(static_keys, {f.plugin, f.name}) end)

    functions =
      (static_functions ++ dynamic_functions)
      |> Enum.sort_by(&{&1.plugin, &1.name})

    json(conn, %{data: functions})
  end

  @json_schema %OpenApiSpex.Schema{
    description: "JSON object with arbitrary properties",
    type: :object,
    additionalProperties: true
  }

  @call_ok_schema %OpenApiSpex.Schema{
    type: :object,
    properties: %{
      data: @json_schema
    }
  }

  operation(:invoke,
    operation_id: "call_hook",
    summary: "Invoke a hook function",
    tags: ["Hooks"],
    security: [%{"authorization" => []}],
    request_body:
      {"Call hook", "application/json",
       %OpenApiSpex.Schema{
         type: :object,
         properties: %{
           plugin: %OpenApiSpex.Schema{type: :string},
           fn: %OpenApiSpex.Schema{type: :string},
           args: %OpenApiSpex.Schema{type: :array, items: @json_schema}
         },
         required: [:plugin, :fn]
       }},
    responses: [
      ok: {"OK", "application/json", @call_ok_schema},
      bad_request:
        {"Bad Request", "application/json",
         %OpenApiSpex.Schema{
           type: :object,
           properties: %{error: %OpenApiSpex.Schema{type: :string}}
         }},
      unauthorized:
        {"Unauthorized", "application/json",
         %OpenApiSpex.Schema{
           type: :object,
           properties: %{error: %OpenApiSpex.Schema{type: :string}}
         }}
    ]
  )

  def invoke(conn, %{"plugin" => plugin, "fn" => fn_name} = params)
      when is_binary(plugin) and is_binary(fn_name) do
    user = Scope.user(conn.assigns.current_scope)
    args = Map.get(params, "args", [])

    args = if is_list(args), do: args, else: [args]

    max_count = Gamend.Limits.get(:max_hook_args_count)
    max_size = Gamend.Limits.get(:max_hook_args_size)

    args_too_many = length(args) > max_count

    args_too_large =
      case Jason.encode(args) do
        {:ok, encoded} -> byte_size(encoded) > max_size
        _ -> true
      end

    hook = hook_label(plugin, fn_name, length(args))

    cond do
      args_too_many ->
        log_rejected(hook, "too_many_args (#{length(args)} > #{max_count})")
        conn |> put_status(:bad_request) |> json(%{error: :too_many_args, max: max_count})

      args_too_large ->
        log_rejected(hook, "args_too_large (> #{max_size} bytes)")

        conn
        |> put_status(:request_entity_too_large)
        |> json(%{error: :args_too_large, max_bytes: max_size})

      reserved_hook_name?(fn_name) ->
        log_rejected(hook, "reserved_hook_name")

        conn
        |> put_status(:bad_request)
        |> json(%{error: :reserved_hook_name})

      true ->
        # Typed hooks (registered <FnName>Request/<FnName>Reply schemas) accept
        # a single JSON object argument and reply with a JSON map; untyped
        # hooks pass through unchanged.
        reply_to_hook_call(
          conn,
          HookSchemas.call(plugin, fn_name, {:list, args}, :map, caller: user),
          hook
        )
    end
  end

  def invoke(conn, _params) do
    log_rejected("(unparseable)", "invalid_request — missing or non-string plugin/fn")
    conn |> put_status(:bad_request) |> json(%{error: :invalid_request})
  end

  defp reply_to_hook_call(conn, result, hook) do
    case result do
      {:ok, res} ->
        json(conn, %{data: res})

      {:error, :not_implemented} ->
        # Almost always a version skew: the client calls a hook the deployed
        # plugin build does not export yet. Silent here, this cost an afternoon.
        log_rejected(hook, "not_implemented — plugin exports no such function/arity")
        conn |> put_status(:bad_request) |> json(%{error: :not_implemented})

      {:error, :not_found} ->
        log_rejected(hook, "plugin_not_found")
        conn |> put_status(:bad_request) |> json(%{error: :plugin_not_found})

      {:error, :missing_hooks_module} ->
        log_rejected(hook, "missing_hooks_module")
        conn |> put_status(:bad_request) |> json(%{error: :missing_hooks_module})

      {:error, :timeout} ->
        log_rejected(hook, "timeout")
        conn |> put_status(:bad_request) |> json(%{error: :timeout})

      {:error, reason} ->
        log_rejected(hook, inspect(reason))

        conn
        |> put_status(:bad_request)
        |> json(normalize_hook_error(reason))
    end
  end

  defp hook_label(plugin, fn_name, arity), do: "#{plugin}.#{fn_name}/#{arity}"

  # Every rejected hook call says which hook and why. Deliberately no argument
  # values: they carry user data, and the hook plus arity is what identifies the
  # problem. The client only ever sees "denied with a 400", so without this line
  # a rejection is invisible on both ends.
  defp log_rejected(hook, reason) do
    Logger.warning("hooks/call rejected: #{hook} — #{reason}")
  end

  defp reserved_hook_name?(fn_name) when is_binary(fn_name) do
    Gamend.Hooks.internal_hooks()
    |> Enum.any?(fn atom -> to_string(atom) == fn_name end)
  end

  defp normalize_hook_error({:function_clause, message}) when is_binary(message) do
    %{error: "function_clause", details: message}
  end

  defp normalize_hook_error({:exception, message}) when is_binary(message) do
    %{error: "exception", details: message}
  end

  defp normalize_hook_error({kind, reason}) when is_atom(kind) do
    %{error: Atom.to_string(kind), details: inspect(reason)}
  end

  defp normalize_hook_error(reason) when is_atom(reason) do
    %{error: Atom.to_string(reason)}
  end

  defp normalize_hook_error(reason) do
    %{error: "unexpected_error", details: inspect(reason)}
  end
end
