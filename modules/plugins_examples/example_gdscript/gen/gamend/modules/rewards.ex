# Generated from scripts/rewards.gd by `mix gamend.gdscript.compile`. Do not edit.
#
# This is ordinary Elixir: it compiles to the same BEAM bytecode a
# hand-written plugin does, and stack traces point here.
defmodule Gamend.Modules.Rewards do
  @moduledoc "Generated from `scripts/rewards.gd`."

  def starter_gold(referred),
    do: gd_fn_starter_gold(referred)

  def gd_fn_starter_gold(referred) do
    if gd_truthy(gd_load(referred)), do: gd_add(100, 50), else: 100
  end

  def describe(kind, amount),
    do: gd_deref(gd_fn_describe(gd_box(kind), gd_box(amount)))

  def gd_fn_describe(kind, amount) do
    gd_mod("%s x%d", gd_deref(gd_new([kind, amount])))
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

  defp gd_ref?(value), do: match?({:gd_ref, _}, value)

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
end
