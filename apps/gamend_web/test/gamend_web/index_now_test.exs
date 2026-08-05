defmodule GamendWeb.IndexNowTest do
  use ExUnit.Case, async: false

  alias GamendWeb.IndexNow

  setup do
    original = Application.get_env(:gamend_web, GamendWeb.IndexNow)
    on_exit(fn -> Application.put_env(:gamend_web, GamendWeb.IndexNow, original || []) end)
    :ok
  end

  defp configure(opts) do
    Application.put_env(:gamend_web, GamendWeb.IndexNow, opts)
  end

  describe "valid_key?/1" do
    test "accepts 8 to 128 hex characters" do
      assert IndexNow.valid_key?(String.duplicate("a", 8))
      assert IndexNow.valid_key?(String.duplicate("F0", 64))
      assert IndexNow.valid_key?("2f7c1a9b")
    end

    test "rejects anything else" do
      refute IndexNow.valid_key?(String.duplicate("a", 7))
      refute IndexNow.valid_key?(String.duplicate("a", 129))
      refute IndexNow.valid_key?("not-hex-at-all")
      refute IndexNow.valid_key?("2f7c1a9b!")
      refute IndexNow.valid_key?("")
      refute IndexNow.valid_key?(nil)
    end
  end

  describe "key/0 and key_path/0" do
    test "are nil when unconfigured" do
      configure(enabled: false)

      assert IndexNow.key() == nil
      assert IndexNow.key_path() == nil
    end

    test "a malformed key is treated as absent rather than sent" do
      configure(enabled: true, key: "nope")

      assert IndexNow.key() == nil
      assert IndexNow.key_path() == nil
      refute IndexNow.enabled?()
    end

    test "a valid key yields the served path" do
      configure(enabled: true, key: "2f7c1a9b")

      assert IndexNow.key() == "2f7c1a9b"
      assert IndexNow.key_path() == "/2f7c1a9b.txt"
      assert IndexNow.enabled?()
    end
  end

  describe "submit/1" do
    test "an empty list is a no-op even when disabled" do
      configure(enabled: false)

      assert IndexNow.submit([]) == :ok
    end

    test "refuses when disabled, without a network call" do
      configure(enabled: false, key: "2f7c1a9b")

      assert IndexNow.submit(["https://example.com/a"]) == {:error, :disabled}
    end

    test "distinguishes a missing key from a malformed one" do
      configure(enabled: true)
      assert IndexNow.submit(["https://example.com/a"]) == {:error, :no_key}

      configure(enabled: true, key: "zzz")
      assert IndexNow.submit(["https://example.com/a"]) == {:error, :invalid_key}
    end
  end
end
