defmodule Gamend.GDScript.Registry do
  @moduledoc """
  What every script in a plugin exposes to the others.

  Godot makes a script globally reachable by declaring `class_name Foo`, and
  any other script then calls `Foo.method()` without importing anything. That
  is the mechanism here too: the compiler parses every `scripts/*.gd` first,
  records the ones that name themselves, and resolves cross-script calls
  against that record -- so a typo or a wrong argument count is still a compile
  error, across files as well as within one.

  Reference mode is decided for the whole plugin rather than per file. A
  reference passed from one script to another has to stay a reference, and it
  can: they run in the same hook process, so the heap is shared. Cross-script
  calls go straight to the private body and skip the boundary entirely, which
  is why the boxing cost is still paid once per hook invocation rather than
  once per call.
  """

  @type entry :: %{module: String.t(), functions: MapSet.t({String.t(), non_neg_integer()})}
  @type t :: %{optional(String.t()) => entry()}

  @doc "Build the registry from parsed scripts: `[{module, statements}]`."
  @spec build([{String.t(), [tuple()]}]) :: t()
  def build(scripts) do
    for {module, statements} <- scripts,
        name = class_name(statements),
        into: %{},
        do: {name, %{module: module, functions: functions(statements)}}
  end

  @doc "True when any script mutates in place or declares a class."
  @spec ref_mode?([{String.t(), [tuple()]}], (list() -> boolean())) :: boolean()
  def ref_mode?(scripts, mutates?) do
    Enum.any?(scripts, fn {_module, statements} ->
      Enum.any?(statements, &match?({:class, _, _, _, _}, &1)) or
        Enum.any?(statements, fn
          {:func, _name, _params, body, _line} -> mutates?.(body)
          _statement -> false
        end)
    end)
  end

  defp class_name(statements) do
    Enum.find_value(statements, fn
      {:class_name, name, _line} -> name
      _statement -> nil
    end)
  end

  defp functions(statements) do
    for {:func, name, params, _body, _line} <- statements,
        into: MapSet.new(),
        do: {name, length(params)}
  end
end
