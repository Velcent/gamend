defmodule GamendWeb.LogFilter do
  @moduledoc """
  A host-supplied rule for dropping log events.

  `GamendWeb.LogFilters` knows about the noise every Gamend server produces —
  peer TLS alerts, dead sockets — because they come from the endpoint core
  owns. Noise from a *host's* own code is the host's to describe, and a host
  should not have to patch core to silence it.

      # config/config.exs
      config :gamend_web, :log_filters, [GamendHost.LogFilters]

      defmodule GamendHost.LogFilters do
        @behaviour GamendWeb.LogFilter

        @impl true
        def drop?(%{msg: {:string, message}}),
          do: to_string(message) =~ "some known, harmless noise"

        def drop?(_event), do: false
      end

  ## Writing one

  The argument is a raw `:logger` event, not a formatted string — a map with
  `:level`, `:msg` and `:meta`. `:msg` is one of `{:string, chardata}`,
  `{format, args}` or `{:report, map_or_keyword}`, so match on the shape you
  expect and fall through to `false` for everything else.

  Two rules, both because this runs *inside* the logging pipeline:

    * **Never log from `drop?/1`.** Emitting a log event while handling one
      recurses.
    * **Be total.** A raise is caught and treated as "do not drop", so a broken
      filter loses its own noise rather than the whole log. It cannot be
      reported, per the previous rule.

  It also runs on every event on every process, so keep it to pattern matching
  and comparisons — no ETS lookups, no message passing, no regexes over large
  binaries.
  """

  @doc """
  Whether this event should be dropped.

  Return `false` for anything not recognised — the event then continues to the
  remaining filters and handlers.
  """
  @callback drop?(:logger.log_event()) :: boolean()
end
