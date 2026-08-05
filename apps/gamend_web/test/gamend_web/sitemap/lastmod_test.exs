defmodule GamendWeb.Sitemap.LastmodTest do
  use ExUnit.Case, async: true

  alias GamendWeb.Sitemap.Lastmod

  @today ~D[2026-08-05]
  @earlier ~D[2026-07-01]

  defp entry(key, content, opts \\ []) do
    base = %{key: key, content: content}

    case Keyword.get(opts, :seed_date) do
      nil -> base
      seed -> Map.put(base, :seed_date, seed)
    end
  end

  describe "hash/1" do
    test "is stable for identical content" do
      assert Lastmod.hash(["apple", "pear"]) == Lastmod.hash(["apple", "pear"])
    end

    test "distinguishes regroupings of the same characters" do
      refute Lastmod.hash(["ab", "c"]) == Lastmod.hash(["a", "bc"])
    end

    test "ignores line-ending and trailing-whitespace churn" do
      assert Lastmod.hash(["a\r\nb"]) == Lastmod.hash(["a\nb"])
      assert Lastmod.hash(["  word  "]) == Lastmod.hash(["word"])
    end

    test "order is content" do
      refute Lastmod.hash(["a", "b"]) == Lastmod.hash(["b", "a"])
    end
  end

  describe "stamp/3" do
    test "an unchanged page keeps its stored date" do
      {first, _} = Lastmod.stamp(%{}, [entry("food", ["apple"])], @earlier)
      {second, changed} = Lastmod.stamp(first, [entry("food", ["apple"])], @today)

      assert Lastmod.date(second, "food") == "2026-07-01"
      assert changed == []
    end

    test "a changed page takes today and is reported" do
      {first, _} = Lastmod.stamp(%{}, [entry("food", ["apple"])], @earlier)
      {second, changed} = Lastmod.stamp(first, [entry("food", ["apple", "pear"])], @today)

      assert Lastmod.date(second, "food") == "2026-08-05"
      assert changed == ["food"]
    end

    test "reformatting the source does not move the date" do
      {first, _} = Lastmod.stamp(%{}, [entry("food", ["apple\nsecond"])], @earlier)
      {second, changed} = Lastmod.stamp(first, [entry("food", ["apple\r\nsecond  "])], @today)

      assert Lastmod.date(second, "food") == "2026-07-01"
      assert changed == []
    end

    test "a new page without a seed takes today, and is not reported as changed" do
      {manifest, changed} = Lastmod.stamp(%{}, [entry("food", ["apple"])], @today)

      assert Lastmod.date(manifest, "food") == "2026-08-05"
      assert changed == [], "a first sighting is not a change"
    end

    test "a seed date bootstraps a new page instead of claiming today" do
      entries = [entry("food", ["apple"], seed_date: "2026-01-09")]
      {manifest, changed} = Lastmod.stamp(%{}, entries, @today)

      assert Lastmod.date(manifest, "food") == "2026-01-09"
      assert changed == []
    end

    test "the seed is ignored once the page is known" do
      {first, _} = Lastmod.stamp(%{}, [entry("food", ["apple"])], @earlier)

      {second, _} =
        Lastmod.stamp(first, [entry("food", ["apple"], seed_date: "1999-01-01")], @today)

      assert Lastmod.date(second, "food") == "2026-07-01"
    end

    test "a page that no longer exists drops out" do
      {first, _} = Lastmod.stamp(%{}, [entry("food", ["a"]), entry("home", ["b"])], @earlier)
      {second, _} = Lastmod.stamp(first, [entry("food", ["a"])], @today)

      assert Map.keys(second) == ["food"]
    end
  end

  describe "latest/2" do
    test "is the newest date among the keys" do
      entries = [
        entry("a", ["1"], seed_date: "2026-01-01"),
        entry("b", ["2"], seed_date: "2026-05-05")
      ]

      {manifest, _} = Lastmod.stamp(%{}, entries, @today)

      assert Lastmod.latest(manifest, ["a", "b"]) == "2026-05-05"
    end

    test "is nil when nothing is known" do
      assert Lastmod.latest(%{}, ["a"]) == nil
      assert Lastmod.latest(%{}, []) == nil
    end
  end

  describe "load/1 and save/2" do
    @tag :tmp_dir
    test "round-trips", %{tmp_dir: dir} do
      path = Path.join(dir, "nested/manifest.json")
      {manifest, _} = Lastmod.stamp(%{}, [entry("food", ["apple"])], @today)

      assert :ok = Lastmod.save(path, manifest)
      assert Lastmod.load(path) == manifest
    end

    @tag :tmp_dir
    test "output is sorted and stable across runs", %{tmp_dir: dir} do
      path = Path.join(dir, "m.json")
      entries = [entry("z", ["1"]), entry("a", ["2"]), entry("m", ["3"])]
      {manifest, _} = Lastmod.stamp(%{}, entries, @today)
      :ok = Lastmod.save(path, manifest)

      body = File.read!(path)
      assert ["a", "m", "z"] == Regex.scan(~r/^  "(\w+)":/m, body) |> Enum.map(&List.last/1)
      assert body == Lastmod.encode(Lastmod.load(path))
    end

    test "a missing file is an empty manifest, not an error" do
      assert Lastmod.load("/nonexistent/nope.json") == %{}
    end

    @tag :tmp_dir
    test "a corrupt file is an empty manifest", %{tmp_dir: dir} do
      path = Path.join(dir, "bad.json")
      File.write!(path, "{not json")

      assert Lastmod.load(path) == %{}
    end
  end
end
