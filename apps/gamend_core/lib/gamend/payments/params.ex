defmodule Gamend.Payments.Params do
  @moduledoc """
  Shape-wrangling shared by `Gamend.Payments` and its provider adapters.

  Every provider receives a JSON body from somewhere outside — Apple's signed
  notifications, Google's RTDN envelopes, Steam's form responses — and each one
  needed the same four things: string-keyed maps, an epoch-millis timestamp as
  an ISO-8601 string, a positive integer with a fallback, and a required
  non-empty string.

  So each one had them. `normalize_params/1` and its `normalize_nested/1`
  existed verbatim in four modules (Apple twice, once in `Apple.JWS`),
  `millis_to_iso8601/1` and `parse_positive_int/2` in two, `required_binary/2`
  in two. None of the copies had drifted yet, which is the only reason this is
  a tidy-up rather than a bug hunt.
  """

  @doc """
  Recursively string-keys a map, so a body that arrived as atoms and one that
  arrived as JSON can be read the same way.
  """
  @spec normalize(term()) :: term()
  defdelegate normalize(attrs), to: Gamend.Parse, as: :string_keys_deep

  @doc "An integer, or an integer written as a string. See `Gamend.Parse.integer/1`."
  @spec parse_int(term()) :: integer() | nil
  defdelegate parse_int(value), to: Gamend.Parse, as: :integer

  @doc "A positive integer, or `default` when the value is missing or not one."
  @spec parse_positive_int(term(), integer()) :: integer()
  def parse_positive_int(value, default) do
    case parse_int(value) do
      int when is_integer(int) and int > 0 -> int
      _ -> default
    end
  end

  @doc "Epoch milliseconds as an ISO-8601 string; `nil` when it is not one."
  @spec millis_to_iso8601(term()) :: String.t() | nil
  def millis_to_iso8601(nil), do: nil

  def millis_to_iso8601(value) do
    with int when is_integer(int) <- parse_int(value),
         {:ok, datetime} <- DateTime.from_unix(int, :millisecond) do
      DateTime.to_iso8601(datetime)
    else
      _ -> nil
    end
  end

  @doc """
  Fetches `key` as a non-empty string, or `{:error, :missing_<key>}`.
  """
  @spec required_binary(map(), String.t()) :: {:ok, String.t()} | {:error, atom()}
  def required_binary(map, key) do
    case map[key] do
      value when is_binary(value) and value != "" -> {:ok, value}
      _ -> {:error, String.to_atom("missing_#{key}")}
    end
  end

  @doc ~S"""
  Turns the literal `\n` sequences a PEM key picks up when it travels through an
  environment variable back into real newlines.
  """
  @spec normalize_private_key(String.t()) :: String.t()
  def normalize_private_key(value), do: String.replace(value, "\\n", "\n")
end
