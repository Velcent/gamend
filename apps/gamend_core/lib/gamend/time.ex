defmodule Gamend.Time do
  @moduledoc """
  The server's wall clock, in milliseconds since the epoch, for sending to
  clients.

  Wall clock and not monotonic because the value leaves the machine: a client
  compares it against its own. Durations measured *inside* the server keep using
  `System.monotonic_time/1`; never mix the two.
  """

  @spec now_ms() :: integer()
  def now_ms, do: System.system_time(:millisecond)
end
