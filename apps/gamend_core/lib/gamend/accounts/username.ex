defmodule Gamend.Accounts.Username do
  @moduledoc """
  The username handle's rules, in one place for the changeset and the
  generator.

  A handle is Unicode: letters and digits of any script, each letter carrying
  at most three combining marks, joined by non-consecutive `.` `_` `-` and
  starting and ending on a letter or digit. It is stored NFKC-normalized and
  lowercased, so the fullwidth `ｄｒａｇｏｓ`, the ligature `ﬁ` and the
  precomposed/decomposed forms of `ș` each land on one spelling and the
  unique index sees them as the same name.

  Against impersonation, which a Unicode handle opens, it applies two clauses
  of UTS #39 (Unicode Security Mechanisms), the standard browsers apply to
  international domain names:

    * **Section 5.2, "Highly Restrictive" script mixing.** One script, or
      Latin with Chinese, Japanese or Korean (Latin + Han + Hiragana +
      Katakana; Latin + Han + Bopomofo; Latin + Han + Hangul). `王wang` and
      `yamada太郎` pass. `pаypal` with a Cyrillic `а` renders as `paypal` and
      is refused, as is any mix of Latin, Cyrillic and Greek, which share
      dozens of identical letters. Digits and separators belong to no script.
    * **Section 5.4, combining marks.** Decomposed, never the same mark twice
      in a row nor more than four in a row (`café` with the accent typed
      twice renders as `café`); the stored form also caps three per letter.
      That stops stacked-mark "zalgo" text while allowing Vietnamese (`ệ` is
      two).

  Nothing else: a CJK letter that resembles a Latin one (`丨` for `l`, `ㅇ`
  for `o`) is no more confusable than `1` and `0`, which any ASCII handle
  holds. Format-control characters (zero-width joiners, direction overrides)
  are not letters, so the format refuses them.

  `GAMEND_LIMITS_USERNAME_ASCII_ONLY=true` keeps handles to `a-z`, `0-9` and
  the separators, the GitHub and Discord model, after the same normalization
  (`ＷＡＮＧ` is still `wang`); the generator then transliterates or picks a
  word.
  """

  @max_marks 3

  @format ~r/^[\p{L}\p{Nd}]\p{M}{0,#{@max_marks}}(?:[._-]?[\p{L}\p{Nd}]\p{M}{0,#{@max_marks}})*$/u

  @scripts ~w(Latin Greek Cyrillic Armenian Hebrew Arabic Syriac Thaana Devanagari
              Bengali Gurmukhi Gujarati Oriya Tamil Telugu Kannada Malayalam Sinhala
              Thai Lao Tibetan Myanmar Georgian Hangul Ethiopic Khmer Mongolian
              Hiragana Katakana Bopomofo Han)
  @script_patterns Enum.map(@scripts, &{&1, Regex.compile!("^\\p{#{&1}}$", "u")})

  # UTS #39 "Highly Restrictive": the mixes a single handle may use.
  @mixes [
    MapSet.new(~w(Latin Han Hiragana Katakana)),
    MapSet.new(~w(Latin Han Bopomofo)),
    MapSet.new(~w(Latin Han Hangul))
  ]

  # UTS #39 5.4, on the decomposed form (NFC hides the second acute of `é́`):
  # the same nonspacing mark twice in a row, or more than four in a row.
  @mark_run ~r/([\p{Mn}\p{Me}])\1|[\p{Mn}\p{Me}]{5,}/u

  @ascii ~r/^[a-z0-9._-]+$/

  @doc "The spelling a handle is stored and looked up under."
  @spec normalize(String.t()) :: String.t()
  def normalize(username) when is_binary(username) do
    username
    |> String.normalize(:nfkc)
    |> String.downcase()
    |> String.normalize(:nfc)
  end

  @doc "The format regex (letters, digits, marks, separators)."
  @spec format() :: Regex.t()
  def format, do: @format

  @doc """
  The ASCII-only, script and mark rules (see moduledoc) for a NORMALIZED
  handle: `:ok`, or `{:error, message}` for the changeset.
  """
  @spec check_scripts(String.t()) :: :ok | {:error, String.t()}
  def check_scripts(username) when is_binary(username) do
    cond do
      Gamend.Limits.get(:username_ascii_only) and not String.match?(username, @ascii) ->
        {:error, "only a-z, 0-9 and . _ - separators"}

      not allowed_mix?(username) ->
        {:error, "can only mix Latin letters with Chinese, Japanese or Korean"}

      Regex.match?(@mark_run, String.normalize(username, :nfd)) ->
        {:error, "repeats or stacks combining marks"}

      true ->
        :ok
    end
  end

  @doc "Format, length and script rules together, for a normalized handle."
  @spec valid?(String.t()) :: boolean()
  def valid?(username) when is_binary(username) do
    length = String.length(username)

    length >= Gamend.Limits.get(:min_username) and length <= Gamend.Limits.get(:max_username) and
      String.match?(username, @format) and check_scripts(username) == :ok
  end

  def valid?(_), do: false

  defp allowed_mix?(username) do
    scripts =
      for <<cp::utf8 <- username>>,
          char = <<cp::utf8>>,
          String.match?(char, ~r/^\p{L}$/u),
          into: MapSet.new(),
          do: script(char)

    MapSet.size(scripts) <= 1 or Enum.any?(@mixes, &MapSet.subset?(scripts, &1))
  end

  # A letter outside every listed script falls in one :other bucket: it can
  # never pair with a listed script, and a name wholly in one rare script
  # (Cherokee, Tifinagh) still passes.
  defp script(char) do
    Enum.find_value(@script_patterns, :other, fn {name, re} ->
      if String.match?(char, re), do: name
    end)
  end
end
