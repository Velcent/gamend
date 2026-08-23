# Is a process-dictionary heap slow enough to rule out reference semantics for
# GDScript Arrays and Dictionaries? Measure, don't guess.
#
#     elixir bench/heap_bench.exs
#
# The numbers this produced are recorded in docs/specs/gdscript-plugins.md under
# "Reference semantics -- buildable after all". The `append via store` row is
# deliberately unfair to the heap -- it grows one list across every iteration --
# and is kept because the mistake is instructive; the fair comparison is the
# 1000-element build loop below it.
defmodule Heap do
  def new(value) do
    ref = make_ref()
    Process.put(ref, value)
    {:gd_ref, ref}
  end

  def load({:gd_ref, ref}), do: Process.get(ref)
  def load(value), do: value

  def store({:gd_ref, ref}, fun), do: Process.put(ref, fun.(Process.get(ref)))

  # Deep-box: every list/map becomes a ref. Structs and vectors are left alone.
  def box(list) when is_list(list), do: new(Enum.map(list, &box/1))
  def box(%_{} = struct), do: struct
  def box(map) when is_map(map), do: new(Map.new(map, fn {k, v} -> {k, box(v)} end))
  def box(other), do: other

  def deref({:gd_ref, ref}), do: deref(Process.get(ref))
  def deref(list) when is_list(list), do: Enum.map(list, &deref/1)
  def deref(%_{} = struct), do: struct
  def deref(map) when is_map(map), do: Map.new(map, fn {k, v} -> {k, deref(v)} end)
  def deref(other), do: other
end

bench = fn label, n, fun ->
  {us, _} = :timer.tc(fn -> Enum.each(1..n, fn _ -> fun.() end) end)
  IO.puts(String.pad_trailing(label, 44) <> "#{Float.round(us * 1000 / n, 1)} ns/op")
end

n = 1_000_000
list = Enum.to_list(1..100)
map = Map.new(1..100, &{"k#{&1}", &1})
rl = Heap.new(list)
rm = Heap.new(map)

IO.puts("--- per-access overhead (1M iterations each) ---")
bench.("Enum.at(list, 50)        value", n, fn -> Enum.at(list, 50) end)
bench.("Enum.at(load(ref), 50)   heap", n, fn -> Enum.at(Heap.load(rl), 50) end)
bench.("Map.get(map, k)          value", n, fn -> Map.get(map, "k50") end)
bench.("Map.get(load(ref), k)    heap", n, fn -> Map.get(Heap.load(rm), "k50") end)
bench.("length(list)             value", n, fn -> length(list) end)
bench.("length(load(ref))        heap", n, fn -> length(Heap.load(rl)) end)
bench.("append (list ++ [x])     value", 100_000, fn -> list ++ [1] end)
bench.("append via store         heap", 100_000, fn -> Heap.store(rl, &(&1 ++ [1])) end)

IO.puts("\n--- the realistic shape: build a 1000-element array in a loop ---")
{us_v, _} = :timer.tc(fn -> Enum.reduce(1..1000, [], fn i, acc -> acc ++ [i] end) end)

{us_h, _} =
  :timer.tc(fn ->
    r = Heap.new([])
    Enum.each(1..1000, fn i -> Heap.store(r, &(&1 ++ [i])) end)
    Heap.load(r)
  end)

IO.puts("value rebind loop: #{us_v} us    heap store loop: #{us_h} us")

IO.puts("\n--- boundary cost: boxing a hook payload in and out ---")
user = %{id: "u1", username: "x", metadata: %{"ref" => "abc", "tags" => ["a", "b"]}}
purchase = %{user_id: "u1", items: Enum.map(1..20, &%{"sku" => "s#{&1}", "qty" => &1})}
bench.("box(user) + deref", 100_000, fn -> user |> Heap.box() |> Heap.deref() end)

bench.("box(purchase, 20 items) + deref", 100_000, fn ->
  purchase |> Heap.box() |> Heap.deref()
end)

big = Enum.map(1..10_000, &%{"id" => &1, "meta" => %{"n" => &1}})
{us, _} = :timer.tc(fn -> big |> Heap.box() |> Heap.deref() end)
IO.puts(String.pad_trailing("box(10k records) + deref, once", 44) <> "#{div(us, 1000)} ms")

IO.puts("\n--- semantics check: does aliasing actually work? ---")
a = Heap.new([1, 2])
b = a
Heap.store(b, &(&1 ++ [3]))
IO.inspect(Heap.load(a), label: "var b = a; b.append(3); a")

add = fn xs -> Heap.store(xs, &(&1 ++ ["gold"])) end
rewards = Heap.new([])
add.(rewards)
IO.inspect(Heap.load(rewards), label: "add_reward(rewards); rewards")

d = Heap.box(%{"items" => []})
Heap.store(Map.get(Heap.load(d), "items"), &(&1 ++ [1]))
IO.inspect(Heap.deref(d), label: "d[\"items\"].append(1); d")
