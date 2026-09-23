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

  Two rules exist only to stop impersonation, which a Unicode handle opens:

    * **One script per handle.** `pаypal` with a Cyrillic `а` renders as
      `paypal`. Mixing is refused, except Han with kana (Japanese) and Han
      with Hangul (Korean), where one name legitimately spans scripts. Digits
      and separators belong to no script.
    * **At most three combining marks per letter**, which stops stacked-mark
      "zalgo" text while allowing Vietnamese (`ệ` is two).

  Format-control characters (zero-width joiners, direction overrides) are not
  letters, so they are refused by the format alone.
  """

  @max_marks 3

  @format ~r/^[\p{L}\p{Nd}]\p{M}{0,#{@max_marks}}(?:[._-]?[\p{L}\p{Nd}]\p{M}{0,#{@max_marks}})*$/u

  @scripts ~w(Latin Greek Cyrillic Armenian Hebrew Arabic Syriac Thaana Devanagari
              Bengali Gurmukhi Gujarati Oriya Tamil Telugu Kannada Malayalam Sinhala
              Thai Lao Tibetan Myanmar Georgian Hangul Ethiopic Khmer Mongolian
              Hiragana Katakana Han)
  @script_patterns Enum.map(@scripts, &{&1, Regex.compile!("^\\p{#{&1}}$", "u")})

  @japanese MapSet.new(~w(Han Hiragana Katakana))
  @korean MapSet.new(~w(Han Hangul))

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

  @doc "Whether a NORMALIZED handle keeps to one script (see moduledoc)."
  @spec single_script?(String.t()) :: boolean()
  def single_script?(username) when is_binary(username) do
    scripts =
      for <<cp::utf8 <- username>>,
          char = <<cp::utf8>>,
          String.match?(char, ~r/^\p{L}$/u),
          into: MapSet.new(),
          do: script(char)

    MapSet.size(scripts) <= 1 or MapSet.subset?(scripts, @japanese) or
      MapSet.subset?(scripts, @korean)
  end

  @doc "Format, length and script rules together, for a normalized handle."
  @spec valid?(String.t()) :: boolean()
  def valid?(username) when is_binary(username) do
    length = String.length(username)

    length >= Gamend.Limits.get(:min_username) and length <= Gamend.Limits.get(:max_username) and
      String.match?(username, @format) and single_script?(username)
  end

  def valid?(_), do: false

  # A letter outside every listed script falls in one :other bucket: it can
  # never pair with a listed script, and a name wholly in one rare script
  # (Cherokee, Tifinagh) still passes.
  defp script(char) do
    Enum.find_value(@script_patterns, :other, fn {name, re} ->
      if String.match?(char, re), do: name
    end)
  end
end
