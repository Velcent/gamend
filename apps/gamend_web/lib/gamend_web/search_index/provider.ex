defmodule GamendWeb.SearchIndex.Provider do
  @moduledoc """
  What a host puts in the site search palette.

  The palette itself is core's: the header button, the dialog, the keyboard
  handling and the ranking are the same on every host. What differs is what
  there is to find, and that arrives here — one call per palette open, per
  locale, per reader.

      config :gamend_web, :search_provider, MyHost.Search

  Unset, `GamendWeb.SearchIndex.Default` supplies the theme's own navigation
  links, so a host that configures nothing still gets a working palette.
  `false` turns the feature off: no button, no dialog, and the index route
  404s.

  ## Entries

  An entry is a place to go:

      %{
        title: "Spanish",                 # required, what the row says
        href: "/vocabulary/spanish",      # required, where it goes
        group: "Vocabulary",              # optional, the heading it sits under
        subtitle: "Word lists by category",
        keywords: ["Español", "es_es"],   # optional, matched but not shown
        scope: nil
      }

  Titles, subtitles and group labels are the reader's words: translate them in
  the provider, where the host's own gettext backend is in scope. `href` is a
  clean path (`/guide/hangman`); core adds the locale prefix.

  ## Query actions

  An entry whose `href` contains `{q}` is not a destination but a search: the
  palette substitutes what the reader typed and offers it below the page hits.
  That is how a word query reaches a search that needs to know *which*
  language — the palette cannot search 4,000 words per language pair, but it
  can hand the word to the page that can.

  Which ones are offered is decided by `scope`:

    * `scope: "es_es"` — offered when `"es_es"` is one of the reader's current
      scopes (see `c:scopes/1` and `data-gamend-search-scopes`), or when one of
      the entry's `keywords` is a whole word in the query. In the second case
      that word is taken out of `{q}`, so `casa spanish` searches for `casa`.
    * `scope: nil` — the fallback, offered only when no scoped action matched.
      Usually a page that asks which language first.
  """

  @typedoc "One row in the palette."
  @type entry :: %{
          required(:title) => String.t(),
          required(:href) => String.t(),
          optional(:group) => String.t() | nil,
          optional(:subtitle) => String.t() | nil,
          optional(:keywords) => [String.t()],
          optional(:scope) => String.t() | nil
        }

  @typedoc """
  Who is asking.

  `scope` is the current `Gamend.Accounts.Scope` (nil when signed out) so a
  provider can hide what the reader cannot open; `locale` is already
  normalised and is the locale gettext is set to for the call.
  """
  @type context :: %{
          required(:scope) => map() | nil,
          required(:locale) => String.t(),
          optional(:scopes) => [String.t()]
        }

  @doc "Everything worth finding, in the order it should be offered."
  @callback entries(context()) :: [entry()]

  @doc """
  Rows for a query the index cannot answer from what it already holds.

  The index is everything worth offering before anyone types — a few hundred
  destinations, small enough to filter in the browser. Some things are too
  many to send: this site has around four thousand words per language pair
  and fifty languages, and the answer to "casa" depends on which of them the
  reader means.

  So this is asked per query, debounced, with `scopes` carrying what the
  reader is most likely to mean, most likely first (see `c:scopes/1`). Rows
  come back in the same shape as an index entry and are shown under the ones
  the browser matched locally.

  Optional. A provider without it gets a palette that searches its index and
  nothing else, which is the whole feature for most hosts.
  """
  @callback search(query :: String.t(), context()) :: [entry()]

  @doc """
  Scopes the server knows about, most relevant first.

  Merged after the ones the page published in `data-gamend-search-scopes`, so
  a signed-in reader's saved language is offered on a page that has none of
  its own. Optional: a provider with no notion of scope leaves it out.
  """
  @callback scopes(context()) :: [String.t()]

  @optional_callbacks scopes: 1, search: 2
end
