defmodule GamendWeb.LogFiltersTest do
  @moduledoc """
  The filter has to be narrow. Dropping every `:tls_alert` would also silence
  `handshake_failure` / `unknown_ca` / `certificate_expired`, which on a server
  that terminates TLS itself are how an expired or misconfigured certificate
  announces itself — the one TLS error that genuinely needs a human.
  """
  use ExUnit.Case, async: true

  alias GamendWeb.LogFilters

  defp terminate_report(reason) do
    %{
      level: :error,
      msg: {:report, %{label: {:gen_server, :terminate}, reason: reason, name: self()}}
    }
  end

  describe "peer-initiated alerts" do
    test "a user_canceled terminate report is dropped" do
      # The actual flood: Safari and iOS send this on navigation away, and
      # Thousand Island turns it into a non-shutdown stop reason.
      alert = {:tls_alert, {:user_canceled, ~c"TLS server: ... User Canceled\n"}}

      assert LogFilters.filter_tls_alert(terminate_report(alert), []) == :stop
    end

    test "close_notify is dropped too" do
      alert = {:tls_alert, {:close_notify, ~c"TLS server: ... Close Notify\n"}}

      assert LogFilters.filter_tls_alert(terminate_report(alert), []) == :stop
    end

    test "the alert is still recognised when wrapped in a shutdown tuple" do
      alert = {:shutdown, {:tls_alert, {:user_canceled, ~c"..."}}}

      assert LogFilters.filter_tls_alert(terminate_report(alert), []) == :stop
    end

    test "it is recognised inside a proc_lib crash report" do
      alert = {:tls_alert, {:user_canceled, ~c"..."}}

      event = %{
        level: :error,
        msg:
          {:report,
           %{
             label: {:proc_lib, :crash},
             report: [[error_info: {:exit, alert, []}], []]
           }}
      }

      assert LogFilters.filter_tls_alert(event, []) == :stop
    end
  end

  describe "alerts that mean something is wrong on our side" do
    for alert <- [:handshake_failure, :unknown_ca, :certificate_expired, :bad_certificate] do
      test "#{alert} survives the filter" do
        reason = {:tls_alert, {unquote(alert), ~c"TLS server: ..."}}

        assert LogFilters.filter_tls_alert(terminate_report(reason), []) == :ignore
      end
    end
  end

  describe "everything else" do
    test "an ordinary crash is untouched" do
      report = terminate_report({:badmatch, nil})

      assert LogFilters.filter_tls_alert(report, []) == :ignore
    end

    test "a plain log message is untouched" do
      assert LogFilters.filter_tls_alert(%{level: :info, msg: {:string, ~c"hello"}}, []) ==
               :ignore
    end

    test "a report with no reason at all is untouched" do
      event = %{level: :error, msg: {:report, %{label: {:gen_server, :terminate}}}}

      assert LogFilters.filter_tls_alert(event, []) == :ignore
    end
  end

  describe "install/0" do
    test "is idempotent, so a supervisor restart cannot stack duplicates" do
      on_exit(&LogFilters.uninstall/0)

      assert LogFilters.install() == :ok
      assert LogFilters.install() == :ok
    end
  end
end
