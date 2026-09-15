defmodule GamendHost.HostLayoutTranslations do
  @moduledoc false

  use Gettext, backend: GamendHost.Gettext

  def messages do
    [
      gettext_noop("Leaderboards"),
      gettext_noop("Quests"),
      gettext_noop("Groups"),
      gettext_noop("Loading..."),
      gettext_noop("Dismiss"),
      gettext_noop("Log in"),
      gettext_noop("Register"),
      gettext_noop("Account"),
      gettext_noop("Notifications"),
      gettext_noop("Chat"),
      gettext_noop("Admin"),
      gettext_noop("Log out"),

      # The search palette. Core renders these through
      # `HostLayouts.translate/1`, which is a runtime `Gettext.gettext/2`
      # against this backend — a function call, not the macro, so extraction
      # never sees them at their own call site. They have to be named here or
      # the palette is in English in every locale.
      gettext_noop("Search"),
      gettext_noop("No results."),
      gettext_noop("Close")
    ]
  end
end
