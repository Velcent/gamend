# What does writing a hook in GDScript cost against writing it in Elixir?
#
#     mix run bench/hook_bench.exs
#
# The numbers this produces are recorded in docs/specs/gdscript-plugins.md.
# `heap_bench.exs` measures the heap primitives; this measures whole hooks.
#
# Four things here are deliberate, and each of them was a wrong answer first:
#
#   * **The reference heap is cleared between calls.** Every hook runs in its
#     own Task, so its heap holds one call's collections and dies with it. Run
#     a long loop in one process instead and the process dictionary grows to
#     thousands of entries, at which point `Process.put` with a new key goes
#     from ~150ns to ~1us. That artifact produced the "14x reference mode"
#     figure this file replaced, and it is easy to walk back into.
#   * **The two candidates are interleaved inside each round**, not measured
#     one after the other, so a thermal step or a busy core lands on both.
#     Without this, rows disagreed with each other by 3x and read as findings.
#   * **Median of five**, warm-up discarded. Single runs on a laptop are
#     worthless at this resolution.
#   * **The Elixir column is what a person would actually write**, not a
#     transliteration of the generated code -- the question is what choosing
#     GDScript costs. Where the gap is the idiom rather than the compiler
#     (`xs.append()` in a loop is O(n) per append) it gets its own row.

alias Gamend.GDScript

compile = fn source, label, opts ->
  module = "Bench#{label}#{Keyword.get(opts, :suffix, "")}"
  elixir = GDScript.compile_string(source, module, [file: "bench.gd"] ++ opts)
  [{mod, _binary}] = Code.compile_string(elixir, "bench.gd")
  mod
end

# The loop runs in a process of its own: `:erlang.erase()` is how each
# iteration gets the fresh heap a hook Task gets, and running it here would
# wipe the dictionary Mix itself is using.
loop = fn n, fun ->
  task =
    Task.async(fn ->
      :timer.tc(fn ->
        Enum.each(1..n, fn _ ->
          fun.()
          :erlang.erase()
        end)
      end)
    end)

  {us, _} = Task.await(task, :infinity)
  us * 1000 / n
end

median = fn samples -> samples |> Enum.sort() |> Enum.at(div(length(samples), 2)) end

compare = fn n, a, b ->
  loop.(n, a)
  loop.(n, b)

  {as, bs} =
    Enum.reduce(1..5, {[], []}, fn _, {as, bs} ->
      {[loop.(n, a) | as], [loop.(n, b) | bs]}
    end)

  {median.(as), median.(bs)}
end

# What the loop and the erase cost on their own, which every row pays.
{floor_ns, _} = compare.(200_000, fn -> :ok end, fn -> :ok end)
n = 200_000
over = fn t -> max(t - floor_ns, 0.0) end

row = fn label, {elixir, gd}, note ->
  ratio = if over.(elixir) > 5, do: "#{Float.round(over.(gd) / over.(elixir), 1)}x", else: "-"

  IO.puts(
    String.pad_trailing(label, 28) <>
      String.pad_leading("#{round(over.(elixir))}", 9) <>
      String.pad_leading("#{round(over.(gd))}", 9) <>
      String.pad_leading(ratio, 8) <> "   " <> note
  )
end

header = fn ->
  IO.puts(
    String.pad_trailing("", 28) <>
      String.pad_leading("elixir", 9) <> String.pad_leading("gdscript", 9)
  )

  IO.puts(String.duplicate("-", 74))
end

# --------------------------------------------------------------------------

sources = %{
  "Bonus" => """
  func f(level, streak):
  \tvar b = 100
  \tif streak > 5:
  \t\tb += 50
  \tif level > 10:
  \t\tb = b * 2
  \treturn clamp(b, 0, 500)
  """,
  "Describe" => """
  func f(user):
  \tvar name = user["username"]
  \tif name == null:
  \t\treturn "anonymous"
  \tif user["level"] > 10:
  \t\treturn name + " (veteran)"
  \treturn name
  """,
  "Greet" => """
  func f(user, gold):
  \treturn "Welcome, " + user["username"] + "! You start with " + str(gold) + " gold."
  """,
  "Rewards" => """
  func f(n):
  \tvar xs = []
  \tfor i in range(n):
  \t\txs.append(i * 2)
  \treturn xs
  """,
  "Register" => """
  func f(user):
  \tvar gold = 100
  \tif user["metadata"] != null:
  \t\tgold += 50
  \tvar items = []
  \tfor i in range(3):
  \t\titems.append({"sku": "starter", "qty": i + 1})
  \tvar tier = "bronze"
  \tif gold > 120:
  \t\ttier = "silver"
  \treturn {"gold": gold, "items": items, "tier": tier}
  """
}

defmodule ByHand do
  def bonus(level, streak) do
    b = 100
    b = if streak > 5, do: b + 50, else: b
    b = if level > 10, do: b * 2, else: b
    b |> max(0) |> min(500)
  end

  def describe(user) do
    case user["username"] do
      nil -> "anonymous"
      name -> if user["level"] > 10, do: name <> " (veteran)", else: name
    end
  end

  def greet(user, gold) do
    "Welcome, " <> user["username"] <> "! You start with " <> to_string(gold) <> " gold."
  end

  def rewards(n), do: Enum.map(0..(n - 1), &(&1 * 2))

  # The algorithm the compiler emits for `xs.append(...)` in a loop, so the
  # list-building rows separate the transpiler from the idiom.
  def rewards_appending(n), do: Enum.reduce(0..(n - 1), [], fn i, acc -> acc ++ [i * 2] end)

  def register(user) do
    gold = if user["metadata"] != nil, do: 150, else: 100
    items = Enum.map(1..3, &%{"sku" => "starter", "qty" => &1})
    tier = if gold > 120, do: "silver", else: "bronze"
    %{"gold" => gold, "items" => items, "tier" => tier}
  end
end

mods = Map.new(sources, fn {label, source} -> {label, compile.(source, label, [])} end)

user = %{
  "username" => "dragos",
  "level" => 12,
  "metadata" => %{"ref" => "abc", "tags" => ["a", "b"]}
}

IO.puts("""

ns per hook call, median of 5 (#{Float.round(floor_ns, 1)} ns of loop overhead removed)

`value` is a script that never mutates a collection: no references, no
boundary walk. `ref` is a script that does, and the mode is decided per
plugin -- one `d[k] = v` anywhere puts every script in the plugin in it.
""")

header.()

row.(
  "bonus(level, streak)",
  compare.(n, fn -> ByHand.bonus(12, 7) end, fn -> mods["Bonus"].f(12, 7) end),
  "value"
)

row.(
  "describe(user)",
  compare.(n, fn -> ByHand.describe(user) end, fn -> mods["Describe"].f(user) end),
  "value"
)

row.(
  "greet(user, gold)",
  compare.(n, fn -> ByHand.greet(user, 100) end, fn -> mods["Greet"].f(user, 100) end),
  "value"
)

row.(
  "register(user)",
  compare.(n, fn -> ByHand.register(user) end, fn -> mods["Register"].f(user) end),
  "ref"
)

IO.puts("""

what reference mode itself costs: the same read-only hook, compiled both ways
""")

header.()

value_only = compile.(sources["Describe"], "Describe", suffix: "V", ref_mode?: false)
ref_forced = compile.(sources["Describe"], "Describe", suffix: "R", ref_mode?: true)

row.(
  "describe(user)",
  compare.(n, fn -> value_only.f(user) end, fn -> ref_forced.f(user) end),
  "value -> ref"
)

big = Map.merge(user, Map.new(1..50, &{"k#{&1}", %{"n" => &1, "tags" => ["a", "b"]}}))

row.(
  "describe(50-key payload)",
  compare.(20_000, fn -> value_only.f(big) end, fn -> ref_forced.f(big) end),
  "the boundary walk"
)

IO.puts("""

where reference mode's cost actually is: one heap slot per collection created
""")

header.()

put_n = fn count ->
  fn -> Enum.each(1..count, fn i -> Process.put(make_ref(), i) end) end
end

for count <- [1, 4, 8] do
  row.(
    "#{count} collection(s) created",
    compare.(n, fn -> :ok end, put_n.(count)),
    "#{count} x Process.put, new key"
  )
end

IO.puts("""

building an Array in a loop -- `xs.append(v)` copies the list every time
""")

header.()

for size <- [10, 100, 1000] do
  calls = if size >= 1000, do: 2_000, else: 20_000

  row.(
    "rewards(#{size})",
    compare.(calls, fn -> ByHand.rewards(size) end, fn -> mods["Rewards"].f(size) end),
    "vs Enum.map"
  )

  row.(
    "  same algorithm by hand",
    compare.(calls, fn -> ByHand.rewards_appending(size) end, fn -> mods["Rewards"].f(size) end),
    "vs acc ++ [x]"
  )
end

# --------------------------------------------------------------------------

per_call = fn n2, fun ->
  run = fn -> Enum.each(1..n2, fn _ -> Task.await(Task.async(fun), :infinity) end) end
  run.()
  median.(Enum.map(1..5, fn _ -> elem(:timer.tc(run), 0) * 1000 / n2 end))
end

IO.puts("""

and the scale it all sits in: a hook runs in its own Task
""")

IO.puts(
  String.pad_trailing("  empty Task", 32) <> "#{round(per_call.(20_000, fn -> :ok end))} ns"
)

IO.puts(
  String.pad_trailing("  register(user), by hand", 32) <>
    "#{round(per_call.(20_000, fn -> ByHand.register(user) end))} ns"
)

IO.puts(
  String.pad_trailing("  register(user), gdscript", 32) <>
    "#{round(per_call.(20_000, fn -> mods["Register"].f(user) end))} ns"
)

IO.puts("")
