# Generated from scripts/example_gdscript.gd by `mix gamend.gdscript.compile`. Do not edit.
#
# This is ordinary Elixir: it compiles to the same BEAM bytecode a
# hand-written plugin does, and stack traces point here.
defmodule Gamend.Modules.ExampleGdscript do
  @moduledoc "Generated from `scripts/example_gdscript.gd`."

  def after_user_register(user),
    do: gd_deref(gd_fn_after_user_register(gd_box(user)))

  def gd_fn_after_user_register(user) do
    bonus = Gamend.Modules.Rewards.gd_fn_starter_gold(gd_get(gd_load(user), :metadata))

    tier =
      if gd_truthy(gd_load(gd_get(gd_load(user), :metadata))), do: "referred", else: "standard"

    Gamend.Signals.emit("Gamend.Modules.ExampleGdscript", "player_joined", [
      gd_deref(gd_get(gd_load(user), :id)),
      gd_deref(tier)
    ])

    gd_box(
      Gamend.Economy.grant(
        gd_deref(gd_get(gd_load(user), :id)),
        "gold",
        gd_deref(bonus),
        gd_deref(
          reason: "gdscript_starter_kit",
          idempotency_key: gd_rebox(gd_add("gd_starter:", gd_load(gd_get(gd_load(user), :id))))
        )
      )
    )

    gd_box(
      Gamend.Notifications.admin_create_notification(
        gd_deref(gd_get(gd_load(user), :id)),
        gd_deref(gd_get(gd_load(user), :id)),
        gd_deref(
          gd_new(%{
            "title" => "Welcome!",
            "content" => gd_fn_greeting(gd_get(gd_load(user), :username), bonus),
            "metadata" => gd_new(%{"type" => "example_gdscript_welcome", "tier" => tier})
          })
        )
      )
    )
  end

  def after_user_logged_in(user),
    do: gd_deref(gd_fn_after_user_logged_in(gd_box(user)))

  def gd_fn_after_user_logged_in(user) do
    gd_box(
      Gamend.KV.put(
        "example_gdscript_last_login",
        gd_deref(gd_new(%{"username" => gd_get(gd_load(user), :username)}))
      )
    )
  end

  def greeting(name, gold),
    do: gd_fn_greeting(name, gold)

  def gd_fn_greeting(name, gold) do
    try do
      if gd_truthy(gd_deref(name) == "") do
        throw(
          {:gd_return,
           gd_rebox(
             gd_add(
               gd_load(
                 gd_rebox(
                   gd_add("Welcome! You start with ", gd_load(gd_str_all([gd_deref(gold)])))
                 )
               ),
               " gold."
             )
           )}
        )
      else
        nil
      end

      gd_rebox(
        gd_add(
          gd_load(
            gd_rebox(
              gd_add(
                gd_load(
                  gd_rebox(
                    gd_add(
                      gd_load(gd_rebox(gd_add("Welcome, ", gd_load(name)))),
                      "! You start with "
                    )
                  )
                ),
                gd_load(gd_str_all([gd_deref(gold)]))
              )
            )
          ),
          " gold."
        )
      )
    catch
      {:gd_return, value} -> value
    end
  end

  def notification_types,
    do: gd_deref(gd_fn_notification_types())

  def gd_fn_notification_types do
    gd_new(%{"example_gdscript_welcome" => "Sent to a new account by the GDScript example"})
  end

  def grant_bundle(user_id, items),
    do: gd_deref(gd_fn_grant_bundle(gd_box(user_id), gd_box(items)))

  def gd_fn_grant_bundle(user_id, items) do
    granted = 0

    granted =
      Enum.reduce_while(gd_load(items), granted, fn item, granted ->
        try do
          if gd_truthy(gd_deref(item) == "") do
            throw({:gd_continue, granted})
          else
            nil
          end

          if gd_truthy(granted >= 3) do
            throw({:gd_break, granted})
          else
            nil
          end

          gd_box(
            Gamend.Inventory.grant_item(
              gd_deref(user_id),
              gd_deref(item),
              1,
              gd_deref(reason: "gdscript_bundle")
            )
          )

          granted = gd_rebox(gd_add(gd_load(granted), 1))
          {:cont, granted}
        catch
          {:gd_break, gd_acc} -> {:halt, gd_acc}
          {:gd_continue, gd_acc} -> {:cont, gd_acc}
        end
      end)

    granted
  end

  def account_summary(user_id, kind),
    do: gd_deref(gd_fn_account_summary(gd_box(user_id), gd_box(kind)))

  def gd_fn_account_summary(user_id, kind) do
    gold =
      gd_spawn(fn ->
        gd_box(Gamend.Economy.balance(gd_deref(user_id), "gold"))
      end)

    gems =
      gd_spawn(fn ->
        gd_box(Gamend.Economy.balance(gd_deref(user_id), "gems"))
      end)

    _ = "standard"

    tier =
      case gd_deref(kind) do
        gd_match when gd_match in ["vip", "founder"] ->
          tier = "premium"
          tier

        "banned" ->
          tier = "restricted"
          tier

        other ->
          tier = gd_rebox(gd_add("standard:", gd_load(gd_str_all([gd_deref(other)]))))
          tier
      end

    gd_new(%{
      "tier" => tier,
      "gold" => gd_box(Task.await(gold, 30_000)),
      "gems" => gd_box(Task.await(gems, 30_000))
    })
  end

  def bump(counts, key),
    do: gd_deref(gd_fn_bump(gd_box(counts), gd_box(key)))

  def gd_fn_bump(counts, key) do
    if gd_truthy(gd_has(gd_load(counts), key)) do
      gd_store(counts, fn gd_c ->
        gd_put(gd_c, key, gd_rebox(gd_add(gd_load(gd_index(gd_load(counts), key, nil)), 1)))
      end)

      nil
    else
      gd_store(counts, fn gd_c -> gd_put(gd_c, key, 1) end)
      nil
    end
  end

  def tally_items(items),
    do: gd_deref(gd_fn_tally_items(gd_box(items)))

  def gd_fn_tally_items(items) do
    counts = gd_new(%{})

    Enum.reduce_while(gd_load(items), nil, fn item, nil ->
      try do
        if gd_truthy(gd_is_empty(gd_strip_edges(gd_load(item), true, true))) do
          throw({:gd_continue, nil})
        else
          nil
        end

        gd_fn_bump(counts, item)
        {:cont, nil}
      catch
        {:gd_break, gd_acc} -> {:halt, gd_acc}
        {:gd_continue, gd_acc} -> {:cont, gd_acc}
      end
    end)

    counts
  end

  def describe_reward(reward),
    do: gd_deref(gd_fn_describe_reward(gd_box(reward)))

  def gd_fn_describe_reward(reward) do
    try do
      case gd_deref(reward) do
        %{"kind" => "gold", "amount" => amount} = gd_match when map_size(gd_match) == 2 ->
          throw({:gd_return, gd_mod("%d gold", gd_deref(gd_new([amount])))})

        %{"kind" => "item"} ->
          throw({:gd_return, "an item"})

        [first | _] ->
          throw(
            {:gd_return,
             gd_rebox(gd_add("a bundle starting with ", gd_load(gd_str_all([gd_deref(first)]))))}
          )

        _ ->
          throw(
            {:gd_return,
             if(gd_truthy(gd_deref(reward) == nil),
               do: "nothing",
               else: gd_str_all([gd_deref(reward)])
             )}
          )
      end
    catch
      {:gd_return, value} -> value
    end
  end

  def rank_for(logins),
    do: gd_fn_rank_for(logins)

  def gd_fn_rank_for(logins) do
    if gd_truthy(logins > 100), do: 11, else: 0
  end

  def await_next_join,
    do: gd_deref(gd_fn_await_next_join())

  def gd_fn_await_next_join do
    Gamend.Signals.subscribe("Gamend.Modules.ExampleGdscript", "player_joined")

    gd_box(
      case Gamend.Signals.await("Gamend.Modules.ExampleGdscript", "player_joined") do
        {:ok, gd_payload} -> gd_payload
        _timeout -> nil
      end
    )
  end

  def reward_summary(kind, amount, bonus),
    do: gd_deref(gd_fn_reward_summary(gd_box(kind), gd_box(amount), gd_box(bonus)))

  def gd_fn_reward_summary(kind, amount, bonus) do
    r =
      if gd_truthy(gd_load(bonus)),
        do: gd_cls_BonusReward_new(kind, amount),
        else: gd_cls_Reward_new(kind, amount)

    gd_invoke(r, "bump", [1])
    gd_new([gd_invoke(r, "describe", []), gd_get(gd_load(r), :amount)])
  end

  defp gd_cls_BonusReward_new(k, a) do
    gd_self = gd_new(%{"__class__" => "BonusReward", "kind" => "gold", "amount" => 0})
    gd_cls_Reward__init(gd_self, k, a)
    gd_self
  end

  defp gd_cls_BonusReward_describe(gd_self) do
    gd_rebox(gd_add("bonus ", gd_load(gd_index(gd_load(gd_self), "kind", nil))))
  end

  defp gd_cls_Reward_new(k, a) do
    gd_self = gd_new(%{"__class__" => "Reward", "kind" => "gold", "amount" => 0})
    gd_cls_Reward__init(gd_self, k, a)
    gd_self
  end

  defp gd_cls_Reward__init(gd_self, k, a) do
    gd_store(gd_self, fn gd_c -> gd_put(gd_c, "kind", k) end)
    gd_store(gd_self, fn gd_c -> gd_put(gd_c, "amount", a) end)
  end

  defp gd_cls_Reward_bump(gd_self, by) do
    gd_store(gd_self, fn gd_c ->
      gd_put(
        gd_c,
        "amount",
        gd_rebox(gd_add(gd_load(gd_index(gd_load(gd_self), "amount", nil)), gd_load(by)))
      )
    end)
  end

  defp gd_cls_Reward_describe(gd_self) do
    gd_mod(
      "%s x%d",
      gd_deref(
        gd_new([
          gd_index(gd_load(gd_self), "kind", nil),
          gd_index(gd_load(gd_self), "amount", nil)
        ])
      )
    )
  end

  defp gd_invoke(gd_instance, gd_method, gd_args) do
    case {gd_index(gd_load(gd_instance), "__class__", nil), gd_method, length(gd_args)} do
      {"BonusReward", "_init", 2} ->
        gd_cls_Reward__init(gd_instance, Enum.at(gd_args, 0), Enum.at(gd_args, 1))

      {"BonusReward", "bump", 1} ->
        gd_cls_Reward_bump(gd_instance, Enum.at(gd_args, 0))

      {"BonusReward", "describe", 0} ->
        gd_cls_BonusReward_describe(gd_instance)

      {"Reward", "_init", 2} ->
        gd_cls_Reward__init(gd_instance, Enum.at(gd_args, 0), Enum.at(gd_args, 1))

      {"Reward", "bump", 1} ->
        gd_cls_Reward_bump(gd_instance, Enum.at(gd_args, 0))

      {"Reward", "describe", 0} ->
        gd_cls_Reward_describe(gd_instance)

      {gd_class, gd_name, gd_arity} ->
        raise ArgumentError,
              "no method #{gd_class}.#{gd_name}/#{gd_arity}"
    end
  end

  # `+` concatenates in GDScript when both sides are strings or arrays, and
  # adds value types component-wise.
  defp gd_add(left, right) do
    cond do
      is_binary(left) and is_binary(right) -> left <> right
      is_list(left) and is_list(right) -> left ++ right
      gd_vec?(left) and gd_vec?(right) -> Map.merge(left, right, fn _key, a, b -> a + b end)
      true -> left + right
    end
  end

  # The boundary in. gamend speaks plain terms; the script speaks
  # references. Structs and value types cross unchanged -- a struct is a
  # payload to read, not a Dictionary to mutate.
  defp gd_box(value) do
    cond do
      gd_ref?(value) -> value
      is_list(value) -> gd_new(Enum.map(value, &gd_box/1))
      is_struct(value) or gd_vec?(value) -> value
      is_map(value) -> gd_new(Map.new(value, fn {k, v} -> {k, gd_box(v)} end))
      is_tuple(value) -> value |> Tuple.to_list() |> Enum.map(&gd_box/1) |> List.to_tuple()
      true -> value
    end
  end

  defp gd_deref(value) do
    cond do
      gd_ref?(value) -> value |> gd_load() |> gd_deref()
      is_list(value) -> Enum.map(value, &gd_deref/1)
      is_struct(value) or gd_vec?(value) -> value
      is_map(value) -> Map.new(value, fn {k, v} -> {k, gd_deref(v)} end)
      is_tuple(value) -> value |> Tuple.to_list() |> Enum.map(&gd_deref/1) |> List.to_tuple()
      true -> value
    end
  end

  # `"%s scored %d" % [name, score]`.
  defp gd_format(format, args) do
    args = if is_list(args), do: args, else: [args]

    ~r/%[sdfx%]/
    |> Regex.split(format, include_captures: true)
    |> Enum.reduce({[], args}, &gd_format_part/2)
    |> elem(0)
    |> Enum.reverse()
    |> IO.iodata_to_binary()
  end

  defp gd_format_part(part, {acc, rest}) do
    cond do
      part == "%%" -> {["%" | acc], rest}
      String.starts_with?(part, "%") and rest == [] -> {[part | acc], []}
      String.starts_with?(part, "%") -> {[gd_format_one(part, hd(rest)) | acc], tl(rest)}
      true -> {[part | acc], rest}
    end
  end

  defp gd_format_one(spec, value) do
    case spec do
      "%d" -> gd_str(gd_to_int(value))
      "%f" -> gd_str(gd_to_float(value))
      # Godot prints hex lowercase; `Integer.to_string/2` prints it upper.
      "%x" -> value |> gd_to_int() |> Integer.to_string(16) |> String.downcase()
      _string -> gd_str(value)
    end
  end

  # Field access works on a struct, an atom-keyed map and a string-keyed
  # Dictionary, because GDScript's `.` reads all three.
  defp gd_get(container, key) do
    if is_map(container) do
      case Map.fetch(container, key) do
        {:ok, value} -> value
        :error -> Map.get(container, Atom.to_string(key))
      end
    else
      nil
    end
  end

  # `Dictionary.has` tests a key, `Array.has` a value, `String.contains` a
  # substring. Nested collections compare by reference, not by contents.
  defp gd_has(container, value) do
    cond do
      is_map(container) -> Map.has_key?(container, value)
      is_binary(container) -> String.contains?(container, value)
      is_list(container) -> Enum.member?(container, value)
      true -> false
    end
  end

  # `arr[0]` is Enum.at on a list -- Elixir's Access raises there -- and a
  # plain lookup on a Dictionary, whose keys may be strings or atoms.
  defp gd_index(container, key, default) do
    cond do
      is_list(container) and is_integer(key) ->
        Enum.at(container, key, default)

      is_map(container) ->
        case Map.fetch(container, key) do
          {:ok, value} -> value
          :error -> Map.get(container, to_string(key), default)
        end

      true ->
        default
    end
  end

  defp gd_is_empty(value), do: gd_size(value) == 0

  defp gd_load(value) do
    case value do
      {:gd_ref, ref} -> Process.get(ref)
      other -> other
    end
  end

  defp gd_mod(left, right) do
    cond do
      is_binary(left) -> gd_format(left, right)
      is_integer(left) and is_integer(right) -> rem(left, right)
      true -> :math.fmod(left, right)
    end
  end

  # Arrays and Dictionaries are mutable and compared by identity in GDScript,
  # so they live in the hook process's own dictionary and a script holds
  # references to them. Every hook and RPC already runs in its own Task, so
  # the heap is scoped to one call and dies with it -- there is nothing to
  # free, and no other hook can see it.
  defp gd_new(value) do
    ref = make_ref()
    Process.put(ref, value)
    {:gd_ref, ref}
  end

  # `Integer.parse/1` and `Float.parse/1` answer `{number, rest}` or `:error`.
  defp gd_parsed(result, fallback) do
    case result do
      {number, _rest} -> number
      _error -> fallback
    end
  end

  defp gd_put(container, key, value) do
    cond do
      is_list(container) and is_integer(key) -> List.replace_at(container, key, value)
      is_map(container) -> Map.put(container, key, value)
      true -> container
    end
  end

  # `+` on Arrays produces a new Array, which has to be a reference too.
  defp gd_rebox(value) do
    cond do
      gd_ref?(value) -> value
      is_list(value) -> gd_new(value)
      is_struct(value) or gd_vec?(value) -> value
      is_map(value) -> gd_new(value)
      true -> value
    end
  end

  defp gd_ref?(value), do: match?({:gd_ref, _}, value)

  defp gd_size(value) do
    cond do
      is_binary(value) -> String.length(value)
      gd_vec?(value) -> gd_vec_length(value)
      is_map(value) -> map_size(value)
      is_list(value) -> length(value)
      true -> 0
    end
  end

  # A spawned lambda runs in another process with another heap, so it gets a
  # snapshot of this one and hands plain terms back. Mutations inside it do
  # not travel home -- see the guide.
  defp gd_spawn(fun) do
    snapshot = for {key, value} <- Process.get(), is_reference(key), do: {key, value}

    Task.async(fn ->
      Enum.each(snapshot, fn {key, value} -> Process.put(key, value) end)
      gd_deref(fun.())
    end)
  end

  defp gd_store(value, fun) do
    case value do
      {:gd_ref, ref} ->
        Process.put(ref, fun.(Process.get(ref)))
        nil

      _other ->
        raise ArgumentError,
              "cannot modify this value in place: it is not an Array or Dictionary"
    end
  end

  # Godot's `str()`: Arrays and Dictionaries print as themselves, and null
  # prints as `<null>`. `to_string/1` gets both wrong.
  defp gd_str(value) do
    cond do
      is_binary(value) -> value
      is_nil(value) -> "<null>"
      is_list(value) -> "[" <> Enum.map_join(value, ", ", &gd_str/1) <> "]"
      is_struct(value) -> inspect(value)
      is_map(value) -> "{" <> Enum.map_join(value, ", ", &gd_str_pair/1) <> "}"
      is_number(value) or is_atom(value) -> to_string(value)
      true -> inspect(value)
    end
  end

  defp gd_str_pair({key, value}), do: "#{gd_str(key)}: #{gd_str(value)}"

  defp gd_str_all(values), do: gd_str_join(values, "")

  defp gd_str_join(values, separator), do: Enum.map_join(values, separator, &gd_str/1)

  defp gd_strip_edges(value, left, right) do
    cond do
      not is_binary(value) -> value
      left and right -> String.trim(value)
      left -> String.trim_leading(value)
      right -> String.trim_trailing(value)
      true -> value
    end
  end

  defp gd_to_float(value) do
    cond do
      is_number(value) -> value * 1.0
      is_binary(value) -> value |> Float.parse() |> gd_parsed(0.0)
      true -> 0.0
    end
  end

  # Godot returns 0 for anything unparseable rather than raising.
  defp gd_to_int(value) do
    cond do
      is_integer(value) -> value
      is_float(value) -> trunc(value)
      is_binary(value) -> value |> Integer.parse() |> gd_parsed(0)
      true -> 0
    end
  end

  # GDScript truthiness: 0, 0.0, "", [] and {} are falsy, unlike Elixir.
  defp gd_truthy(value) do
    cond do
      value == nil or value == false -> false
      is_number(value) -> value != 0
      is_binary(value) -> value != ""
      is_list(value) -> value != []
      is_map(value) -> map_size(value) > 0
      true -> true
    end
  end

  # A value type is a map keyed only by the component names, which is what
  # separates one from an ordinary Dictionary (string keys) at run time.
  defp gd_vec?(value) do
    is_map(value) and map_size(value) > 0 and
      Enum.all?(Map.keys(value), &(&1 in [:a, :b, :g, :r, :x, :y, :z]))
  end

  defp gd_vec_length(vector) do
    vector |> Map.values() |> Enum.reduce(0.0, fn v, acc -> acc + v * v end) |> :math.sqrt()
  end
end
