defmodule GamendWeb.SearchIndex.Default do
  @moduledoc """
  What the palette holds on a host that has not configured a provider: the
  theme's own navigation links.

  Small, but not a placeholder. The nav is where a host declares its pages,
  and on a phone those pages sit two taps deep inside a hamburger — so
  flattening them into one searchable list is worth having on its own, and it
  costs a host nothing to get.
  """

  @behaviour GamendWeb.SearchIndex.Provider

  alias GamendWeb.SearchIndex

  @impl true
  def entries(context), do: SearchIndex.navigation_entries(context)
end
