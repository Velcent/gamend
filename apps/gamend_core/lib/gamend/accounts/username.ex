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

  The rules against impersonation, which a Unicode handle opens, follow
  published standards rather than a list of our own:

    * **Scripts mix as UTS #39 "Highly Restrictive" allows** (Unicode Security
      Mechanisms, section 5.2): one script, or Latin with Chinese, Japanese or
      Korean (Latin + Han + Hiragana + Katakana; Latin + Han + Bopomofo;
      Latin + Han + Hangul). `王wang` and `yamada太郎` pass; `pаypal` with a
      Cyrillic `а` renders as `paypal` and is refused, as is Latin with
      Cyrillic or Greek, or Hangul with kana. Digits and separators belong to
      no script. Chromium applies the same profile to domain names.
    * **Chromium's lookalike patterns.** Mixing Latin with CJK lets `丨` pass
      for `l`, `一` for `-`, `〇` for `o`. `@lookalike` ports the patterns
      Chromium's IDN spoof checker (`idn_spoof_checker.cc`) refuses and a
      handle can hold, character lists and all: those ideographs and Bopomofo
      letters only next to Chinese or Japanese (`一刀` passes, `tom一号` does
      not), `ー` only after kana, look-alike `へ`/`ヘ` inside the other kana,
      and combining marks only where they belong.
    * **No lone Hangul jamo** (`ㅇ`, `ㅣ`). UTS #39 marks the standalone jamo
      Obsolete for identifiers; syllables (`이`) are unaffected.
    * **Combining marks** (UTS #39 section 5.4): decomposed, never the same
      mark twice in a row nor more than four in a row; the stored form also
      caps three per letter. That stops stacked-mark "zalgo" text while
      allowing Vietnamese (`ệ` is two).

  Format-control characters (zero-width joiners, direction overrides) are not
  letters, so they are refused by the format alone.
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

  # Chromium's IDN "dangerous patterns" (components/url_formatter/
  # spoof_checks/idn_spoof_checker.cc) that a handle can hold, with its
  # character lists. `\p{Han}` and the rest match Script_Extensions (PCRE2), as
  # ICU's `\p{scx=...}` does there. Input is normalized, so the Kangxi radicals
  # are already folded onto the ideographs listed.
  @cjk "\\p{Han}\\p{Hiragana}\\p{Katakana}\\p{Bopomofo}"
  @japanese "\\p{Han}\\p{Hiragana}\\p{Katakana}"
  @cjk_lookalikes "\\x{4E00}\\x{3127}\\x{4E28}\\x{4E5B}\\x{4E03}\\x{4E05}\\x{5341}\\x{3007}\\x{3112}" <>
                    "\\x{311A}\\x{311F}\\x{3128}\\x{3129}\\x{3108}\\x{31BA}\\x{31B3}\\x{5DE5}" <>
                    "\\x{31B2}\\x{8BA0}\\x{4E01}\\x{4E36}\\x{4E85}\\x{4E8C}\\x{4EA0}\\x{5196}\\x{5B80}\\x{5DDB}"
  @slash_lookalikes "\\x{30CE}\\x{30F3}\\x{30BD}\\x{30BE}\\x{4E36}\\x{4E40}\\x{4E41}\\x{4E3F}"
  @lookalike Regex.compile!(
               Enum.join(
                 [
                   # ノ ン ソ ゾ 丶 乀 乁 丿 read as `/` between non-Japanese
                   "[^#{@japanese}][#{@slash_lookalikes}][^#{@japanese}]",
                   # ヽ ヾ only after Katakana
                   "[^\\p{Katakana}][\\x{30FD}\\x{30FE}]|^[\\x{30FD}\\x{30FE}]",
                   # へ べ ぺ inside Katakana, ヘ ベ ペ inside Hiragana
                   "^\\p{Katakana}+[\\x{3078}-\\x{307A}]\\p{Katakana}+$",
                   "^\\p{Hiragana}+[\\x{30D8}-\\x{30DA}]\\p{Hiragana}+$",
                   # ー only after kana
                   "[^\\p{Hiragana}\\p{Katakana}]\\x{30FC}|^\\x{30FC}",
                   # 一 丨 〇 十 工 ㄧ ... next to anything but CJK
                   "[^#{@cjk}][#{@cjk_lookalikes}]|[#{@cjk_lookalikes}][^#{@cjk}]",
                   # combining diacritics only after Latin, Greek or Cyrillic
                   "[^\\p{Latin}\\p{Greek}\\p{Cyrillic}][\\x{0300}-\\x{0339}]",
                   "\\x{0131}[\\x{0300}-\\x{0339}]",
                   "[\\x{3099}\\x{309A}]",
                   "[ijl]\\x{0307}"
                 ],
                 "|"
               ),
               "u"
             )

  # Standalone jamo, which NFC leaves only when they do not form a syllable
  # (and which NFKC folds the compatibility jamo ㄱ-ㆎ onto): Obsolete in
  # UTS #39's IdentifierStatus.
  @lone_jamo ~r/[\x{1100}-\x{11FF}\x{A960}-\x{A97F}\x{D7B0}-\x{D7FF}]/u

  # UTS #39 5.4, on the decomposed form (NFC hides the second acute of `é́`):
  # the same nonspacing mark twice in a row, or more than four in a row.
  @mark_run ~r/([\p{Mn}\p{Me}])\1|[\p{Mn}\p{Me}]{5,}/u

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
  The script, lookalike, jamo and mark rules (see moduledoc) for a
  NORMALIZED handle: `:ok`, or `{:error, message}` for the changeset.
  """
  @spec check_scripts(String.t()) :: :ok | {:error, String.t()}
  def check_scripts(username) when is_binary(username) do
    cond do
      not allowed_mix?(username) ->
        {:error, "can only mix Latin letters with Chinese, Japanese or Korean"}

      Regex.match?(@lone_jamo, username) ->
        {:error, "has a lone Hangul letter; write whole syllables"}

      Regex.match?(@mark_run, String.normalize(username, :nfd)) ->
        {:error, "repeats or stacks combining marks"}

      Regex.match?(@lookalike, username) ->
        {:error, "has a character that can be mistaken for another here"}

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
