defmodule GamendWeb.AdminLive.Shared do
  @moduledoc """
  Small pieces more than one admin LiveView needs.

  Each of these existed as an identical private function in two or three
  console pages. They are here rather than in `GamendWeb.CoreComponents`
  because none of them is part of the player-facing surface: a mute duration
  list and a country flag are admin furniture.
  """

  use Gettext, backend: GamendWeb.Gettext

  @doc """
  The mute/ban durations the console offers, as `{value, label}` pairs.

  Shared by the chat-mutes and chat-reports pages, which offered the same list
  and would have drifted the first time one of them gained an option.
  """
  @spec duration_options() :: [{String.t(), String.t()}]
  def duration_options do
    [
      {"10m", gettext("10 minutes")},
      {"1h", gettext("1 hour")},
      {"24h", gettext("24 hours")},
      {"7d", gettext("7 days")},
      {"permanent", gettext("Permanent")}
    ]
  end

  @doc """
  An ISO-3166 alpha-2 code as its flag emoji, or a globe when it is not one.

  The regional-indicator block sits at a fixed offset from `A`, so the two
  letters map straight onto it.
  """
  @spec country_flag(term()) :: String.t()
  def country_flag(code) when is_binary(code) and byte_size(code) == 2 do
    code
    |> String.upcase()
    |> String.to_charlist()
    |> Enum.map(fn char -> char - ?A + 0x1F1E6 end)
    |> List.to_string()
  rescue
    _ -> "🌐"
  end

  def country_flag(_code), do: "🌐"
end
