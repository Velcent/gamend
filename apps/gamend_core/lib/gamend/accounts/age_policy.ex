defmodule Gamend.Accounts.AgePolicy do
  @moduledoc """
  What a user's age permits.

  One module owns two things: deriving an account's bracket from the age fields
  on `users`, and saying what that bracket may do. Everything that gates on age
  asks here rather than re-deriving a threshold, because the thresholds are not
  a single number and getting them slightly different in two places is how a
  child ends up treated as an adult on one surface and not another.

  ## The brackets

    * `:adult` — 18 or over.
    * `:teen` — old enough for their country's digital-consent age, but under 18.
    * `:child` — under 13, **or** under their country's digital-consent age,
      whichever is higher. This is Epic's rule after the FTC action, and it is
      the one that survives contact with the EU: a 14-year-old is a teen in the
      US and a child in Romania, because Romania's Article 8 age is 16.
    * `:unknown` — no age answer. Treated as `:child`, with one exception.

  ## The exception: grandfathered accounts

  An account created before the age gate existed has `grandfathered_at` set and
  no age answer. Restricting those on deploy would take chat, purchasing and
  leaderboard identity away from every existing player at once, so they keep
  adult capability until they answer the prompt. `grandfathered_at` records
  a fact — this account predates the gate — rather than granting a permission,
  and answering clears it.

  This is a deliberate, dated decision with a real cost: a child already playing
  keeps an unrestricted account until they answer. See the migration.

  ## Which direction an age may move

  Down is free; up is not. A user may always lower their stated age, because
  that only ever increases protection. Raising it needs a stronger signal than
  the one that set it — a platform age bracket, a guardian's action, or a
  verified check — so the same session that answered "under 13" cannot simply
  answer again. Google's shipped behaviour is the reference: an under-13
  account's birthdate cannot be corrected by the user at all.

  Graduation is automatic and needs no signal: an account leaves `:child` on the
  first of its birth month, which is conservative by up to 30 days.
  """

  alias Gamend.Accounts.User

  @type class :: :unknown | :child | :teen | :adult

  @adult_age 18
  @coppa_age 13

  # GDPR Article 8 digital-consent age, by ISO-3166-1 alpha-2.
  #
  # Two traps, both of which most published tables get wrong:
  #
  #   * **Slovenia is 15**, not 16 — ZVOP-2, in force 26 January 2023. Tables
  #     written before that still say 16.
  #   * **Spain is 14 but volatile** — a draft Organic Law would raise it to 16.
  #     Re-check before relying on it.
  #
  # Norway, Iceland and Liechtenstein are deliberately absent: the research
  # could not verify them, and a guess here is worse than the default, which is
  # the highest threshold rather than the most convenient one.
  @digital_consent_ages %{
    # 13
    "BE" => 13,
    "DK" => 13,
    "EE" => 13,
    "FI" => 13,
    "LV" => 13,
    "MT" => 13,
    "PT" => 13,
    "SE" => 13,
    "GB" => 13,
    "US" => 13,
    # 14
    "AT" => 14,
    "BG" => 14,
    "CY" => 14,
    "IT" => 14,
    "LT" => 14,
    "ES" => 14,
    # 15
    "CZ" => 15,
    "FR" => 15,
    "GR" => 15,
    "SI" => 15,
    # 16
    "HR" => 16,
    "DE" => 16,
    "HU" => 16,
    "IE" => 16,
    "LU" => 16,
    "NL" => 16,
    "PL" => 16,
    "RO" => 16,
    "SK" => 16
  }

  # An unknown country gets the highest threshold in the table. Erring the other
  # way would mean a country we failed to list silently gets the weakest rule.
  @default_consent_age 16

  @doc """
  The digital-consent age for a country, defaulting to #{@default_consent_age}.
  """
  @spec digital_consent_age(String.t() | nil) :: pos_integer()
  def digital_consent_age(country) when is_binary(country) do
    Map.get(@digital_consent_ages, String.upcase(country), @default_consent_age)
  end

  def digital_consent_age(_country), do: @default_consent_age

  @doc "Every country whose threshold is known, for tests and admin display."
  @spec known_countries() :: [String.t()]
  def known_countries, do: Map.keys(@digital_consent_ages)

  @doc """
  Age in whole years from a birth year and month, on a given date.

  Rolls on the first of the birth month rather than an exact day, because the
  day is deliberately not stored. An account is therefore up to 30 days older
  than this says, never younger.
  """
  @spec age_in_years(integer(), integer(), Date.t()) :: integer()
  def age_in_years(birth_year, birth_month, %Date{} = on)
      when is_integer(birth_year) and is_integer(birth_month) do
    years = on.year - birth_year
    if on.month < birth_month, do: years - 1, else: years
  end

  @doc """
  The bracket an age falls in for a country.

  `child` is the higher of 13 and the country's Article 8 age, so the same age
  can be a teen in one country and a child in another.
  """
  @spec class_for_age(integer(), String.t() | nil) :: class()
  def class_for_age(age, country) when is_integer(age) do
    child_threshold = max(@coppa_age, digital_consent_age(country))

    cond do
      age < child_threshold -> :child
      age < @adult_age -> :teen
      true -> :adult
    end
  end

  @doc """
  The bracket for a user, as of `on` (defaults to today, UTC).

  Returns `:unknown` for an account with no age answer — which callers must
  treat as `:child` unless `grandfathered?/1` says otherwise. Use `policy/2`
  rather than reading this directly; it resolves that rule for you.
  """
  @spec classify(User.t(), Date.t() | nil) :: class()
  def classify(user, on \\ nil)

  def classify(%User{birth_year: year, birth_month: month} = user, on)
      when is_integer(year) and is_integer(month) do
    on = on || Date.utc_today()
    year |> age_in_years(month, on) |> class_for_age(user.age_country)
  end

  def classify(%User{}, _on), do: :unknown

  @doc """
  Whether this account predates the age gate and so keeps adult capability
  while its age is still unknown.

  Answering the age prompt clears `grandfathered_at`, at which point the answer
  governs and this returns false.
  """
  @spec grandfathered?(User.t()) :: boolean()
  def grandfathered?(%User{grandfathered_at: %DateTime{}, birth_year: nil}), do: true
  def grandfathered?(%User{}), do: false

  @doc """
  The effective bracket a caller should enforce.

  This is the one to call. It collapses the `:unknown` question: an account with
  no age answer is a `:child`, unless it predates the gate, in which case it is
  treated as an adult until it answers.
  """
  @spec effective_class(User.t(), Date.t() | nil) :: class()
  def effective_class(user, on \\ nil) do
    case classify(user, on) do
      :unknown -> if grandfathered?(user), do: :adult, else: :child
      class -> class
    end
  end

  defstruct class: :child,
            discoverable?: false,
            public_groups?: false,
            chat_default_on?: false,
            custom_display_name?: false,
            purchases?: false,
            leaderboard_identity: :pseudonym,
            timers_enforced?: false,
            third_party_egress?: false,
            avatar_upload?: false,
            map_presence_published?: false

  @type t :: %__MODULE__{}

  @doc """
  What a user may do.

  The defaults on the struct are the child defaults, so a field nobody
  remembered to set is closed rather than open — the same default-deny posture
  as `before_kv_get/2`.
  """
  @spec policy(User.t(), Date.t() | nil) :: t()
  def policy(%User{} = user, on \\ nil), do: user |> effective_class(on) |> policy_for()

  @doc "The policy for a bracket, without a user."
  @spec policy_for(class()) :: t()
  def policy_for(:adult) do
    %__MODULE__{
      class: :adult,
      discoverable?: true,
      public_groups?: true,
      chat_default_on?: true,
      custom_display_name?: true,
      purchases?: true,
      leaderboard_identity: :real_name,
      timers_enforced?: true,
      third_party_egress?: true,
      avatar_upload?: true,
      map_presence_published?: true
    }
  end

  # Teens are discoverable and may browse groups, but chat is **off by
  # default** — that is the FTC v Epic order's most-copied provision, charged as
  # an FTC Act unfairness violation independent of COPPA, which is why it
  # reaches 13-17 and not only under-13s. They opt in themselves; a child needs
  # an adult.
  def policy_for(:teen) do
    %__MODULE__{
      class: :teen,
      discoverable?: true,
      public_groups?: true,
      chat_default_on?: false,
      custom_display_name?: true,
      purchases?: true,
      leaderboard_identity: :real_name,
      timers_enforced?: true,
      third_party_egress?: false,
      avatar_upload?: false,
      map_presence_published?: true
    }
  end

  # `:unknown` shares the child policy deliberately. An account we know nothing
  # about is the one to be most careful with, not least.
  def policy_for(class) when class in [:child, :unknown] do
    %__MODULE__{class: class}
  end

  @doc """
  Whether a proposed age answer may replace the one already recorded.

  Lowering is always allowed. Raising needs a stronger signal than set the
  current answer, so a user cannot simply re-answer their way out of a
  restriction in the same session.
  """
  @spec may_change_age?(User.t(), integer(), integer(), String.t()) :: boolean()
  def may_change_age?(%User{birth_year: nil}, _year, _month, _method), do: true

  def may_change_age?(%User{} = user, year, month, method)
      when is_integer(year) and is_integer(month) and is_binary(method) do
    on = Date.utc_today()
    current = age_in_years(user.birth_year, user.birth_month, on)
    proposed = age_in_years(year, month, on)

    proposed <= current or stronger_signal?(method, user.age_method)
  end

  # Ordered weakest to strongest. A platform bracket beats self-declaration
  # because the platform asked under conditions we cannot reproduce; a verified
  # check beats everything.
  @signal_strength %{
    "self_declared" => 1,
    "platform_signal" => 2,
    "guardian_declared" => 3,
    "verified" => 4
  }

  @doc "Whether `method` is a stronger age signal than `current`."
  @spec stronger_signal?(String.t() | nil, String.t() | nil) :: boolean()
  def stronger_signal?(method, current) do
    Map.get(@signal_strength, method, 0) > Map.get(@signal_strength, current, 0)
  end

  @doc "Every age-collection method, strongest last."
  @spec methods() :: [String.t()]
  def methods, do: @signal_strength |> Enum.sort_by(&elem(&1, 1)) |> Enum.map(&elem(&1, 0))
end
