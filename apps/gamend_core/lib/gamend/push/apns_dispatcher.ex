defmodule Gamend.Push.APNSDispatcher do
  @moduledoc """
  Pigeon dispatcher for APNs. Configured by `host_runtime.exs` from the
  `APNS_*` env vars; started by `Gamend.Push.Supervisor` only when that
  config exists.
  """
  use Pigeon.Dispatcher, otp_app: :gamend_core
end
