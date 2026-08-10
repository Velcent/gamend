defmodule GamendWeb.LogFilters do
  @moduledoc """
  Primary `:logger` filters for crash reports that are noise, not defects.

  A **primary** filter (rather than a per-handler one) because these reports are
  worthless everywhere: console, file log and the admin Logs buffer alike.
  Filtering once at the source also keeps them from consuming the admin buffer,
  which is a fixed-size ring — a steady stream of noise evicts the real entries
  long before anyone reads them.

  ## The TLS client alerts

  When a client closes a TLS connection by sending a `user_canceled` alert
  (Safari and iOS do this routinely on navigation away), Erlang's `:ssl` sends
  the owning process `{:ssl_error, socket, {:tls_alert, {:user_canceled, _}}}`.
  Thousand Island turns that straight into `{:stop, reason, state}`:

      def handle_info({msg, raw_socket, reason}, {socket, state})
          when msg in [:tcp_error, :ssl_error] do
        {:stop, reason, {socket, state}}
      end

  The reason is neither `:normal` nor `:shutdown`, so OTP logs a full
  `gen_server terminate` crash report with the entire socket struct inlined —
  one per closing client. Note this path ignores Thousand Island's
  `silent_terminate_on_error` option, which only covers the *handler-return*
  error path, so there is no configuration knob that suppresses it.

  ## Why an allowlist rather than "drop all TLS alerts"

  Most TLS alerts are worth seeing. `handshake_failure`, `unknown_ca` and
  `certificate_expired` on a server that terminates TLS itself (this one binds
  443 directly — no proxy) are how a broken or expired certificate announces
  itself. Dropping every `:tls_alert` would silence the one class of TLS error
  that actually needs a human. Only alerts that mean "the peer went away" are
  listed.
  """

  @filter_id :drop_benign_tls_alerts

  # Alerts that only ever mean the client hung up. Everything else — anything
  # implicating our certificate or our TLS configuration — stays visible.
  @benign_alerts [:user_canceled, :close_notify, :closure_alert]

  @doc """
  Installs the filters. Idempotent: re-installing is a no-op, so a supervisor
  restart cannot stack duplicates.
  """
  def install do
    case :logger.add_primary_filter(@filter_id, {&__MODULE__.filter_tls_alert/2, []}) do
      :ok -> :ok
      {:error, {:already_exist, _}} -> :ok
      other -> other
    end
  end

  @doc false
  def uninstall do
    _ = :logger.remove_primary_filter(@filter_id)
    :ok
  end

  @doc """
  Drops crash reports whose exit reason is a peer-initiated TLS alert.

  Returns `:stop` to drop the event, or `:ignore` to leave it for the remaining
  filters and handlers — never the event itself, since this filter only ever
  rejects and must not short-circuit other filters by accepting.
  """
  def filter_tls_alert(event, _extra) do
    if benign_tls_alert?(reason(event)), do: :stop, else: :ignore
  end

  # `gen_server`/`gen_statem` terminate reports carry the reason as a map key.
  defp reason(%{msg: {:report, %{reason: reason}}}), do: reason

  # `proc_lib` crash reports nest it in a keyword-ish list of error info.
  defp reason(%{msg: {:report, %{report: [error_info | _]}}}) when is_list(error_info) do
    case :proplists.get_value(:error_info, error_info, nil) do
      {_kind, reason, _stack} -> reason
      _ -> nil
    end
  end

  defp reason(_event), do: nil

  defp benign_tls_alert?({:tls_alert, {alert, _description}}), do: alert in @benign_alerts

  # A stop reason can wrap the alert, e.g. `{:shutdown, {:tls_alert, ...}}`.
  defp benign_tls_alert?({:shutdown, inner}), do: benign_tls_alert?(inner)
  defp benign_tls_alert?(_reason), do: false
end
