defmodule Gamend.Chat.Moderation.Normalizer do
  @moduledoc """
  Canonical form for chat filter matching.

  Blocklist entries and incoming messages both go through `normalize/1`, so a
  word stored as `"idiot"` still matches `"ïd１0T"` and `"iiiidiot"`. The
  transform is deliberately lossy and identical on both sides — it is a
  matching key, never something to show a player.

  Steps, in order: lower-case; decompose and drop diacritics; drop zero-width
  and soft-hyphen characters; map common leetspeak substitutions; drop
  everything that is not a letter, digit or space; collapse runs of a repeated
  character to one; collapse runs of whitespace to one.

  Known gap: letters spaced out individually (`"i d i o t"`) survive as separate
  tokens and do not match. Catching those means matching across word boundaries,
  which turns benign phrases into hits far more often than it catches evasion.
  """

  # Zero-width space/non-joiner/joiner, BOM and soft hyphen — invisible
  # characters pasted between letters purely to defeat matching.
  @invisible ~r/[\x{200B}-\x{200D}\x{FEFF}\x{00AD}]/u
  @combining_marks ~r/\p{Mn}/u
  @disallowed ~r/[^\p{L}\p{N} ]/u
  @whitespace ~r/\s+/u

  @leet %{
    "@" => "a",
    "4" => "a",
    "8" => "b",
    "(" => "c",
    "3" => "e",
    "6" => "g",
    "1" => "i",
    "!" => "i",
    "|" => "i",
    "0" => "o",
    "$" => "s",
    "5" => "s",
    "7" => "t",
    "+" => "t",
    "2" => "z"
  }

  @doc """
  Reduce `text` to its matching key. Returns `""` for anything that is not a
  binary, so changesets and the hot path never have to special-case nil.
  """
  @spec normalize(term()) :: String.t()
  def normalize(text) when is_binary(text) do
    text
    |> String.downcase()
    |> :unicode.characters_to_nfd_binary()
    |> String.replace(@combining_marks, "")
    |> String.replace(@invisible, "")
    |> replace_leet()
    |> String.replace(@disallowed, "")
    |> collapse_repeats()
    |> String.replace(@whitespace, " ")
    |> String.trim()
  end

  def normalize(_text), do: ""

  defp replace_leet(text) do
    text
    |> String.graphemes()
    |> Enum.map_join(&Map.get(@leet, &1, &1))
  end

  defp collapse_repeats(text) do
    text
    |> String.graphemes()
    |> Enum.reduce([], fn
      char, [char | _] = acc -> acc
      char, acc -> [char | acc]
    end)
    |> Enum.reverse()
    |> Enum.join()
  end
end
