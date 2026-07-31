defmodule GamendWeb.ChannelCase do
  @moduledoc """
  This module defines the test case to be used by
  channel tests that require socket support.

  It sets up the database sandbox and imports the
  conveniences from `Phoenix.ChannelTest` for testing channels.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      # Use the channel test helpers provided by Phoenix
      import Phoenix.ChannelTest

      # The default endpoint for testing
      @endpoint GamendWeb.Endpoint

      import GamendWeb.ChannelCase
    end
  end

  setup tags do
    Gamend.DataCase.setup_sandbox(tags)
    :ok
  end
end
