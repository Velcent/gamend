defmodule Gamend.Push.FCMDispatcher do
  @moduledoc """
  Pigeon dispatcher for FCM. Configured by `host_runtime.exs` from the
  `PUSH_FCM_*` env vars; started by `Gamend.Push.Supervisor` only when
  that config exists.
  """
  use Pigeon.Dispatcher, otp_app: :gamend_core
end
