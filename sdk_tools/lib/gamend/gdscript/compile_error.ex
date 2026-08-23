defmodule Gamend.GDScript.CompileError do
  @moduledoc """
  Raised for anything the GDScript front end will not translate.

  Every unsupported construct is an error here, at compile time, with a file
  and line -- never a silent approximation that misbehaves at runtime. That is
  the whole safety story for a transpiled language: the subset is enforced by
  refusing, not by best effort.
  """

  defexception [:message, :file, :line]

  @impl true
  def message(%{message: message, file: file, line: line}) do
    "#{file}:#{line}: #{message}"
  end
end
