defmodule Gamend.ContentCollectionsTest do
  @moduledoc """
  Two guide collections in one app, which is what `GamendWeb.DocsLive` was
  split out to serve: Polyglot Pirates has a public player guide and an
  admin-only engineering set, and the whole point of two directories is that
  neither can leak into the other.

  Every assertion here is about the boundary — separate listings, separate
  caches, a hook that runs on one and not the other — plus the neighbour and
  category lookups both pages of the renderer need.
  """
  use ExUnit.Case, async: false

  alias Gamend.Content

  @root Path.join(System.tmp_dir!(), "gamend_content_collections_test")

  setup do
    File.rm_rf!(@root)

    write("alpha/_category.md", """
    ---
    title: Alpha
    icon: hero-flag
    color: text-sky-400
    ---
    """)

    write("alpha/10-first.md", """
    ---
    icon: hero-map
    ---
    # First

    An opening paragraph that is hard-wrapped
    across three source lines so the excerpt
    has something to join.
    """)

    write("alpha/20-second.md", "# Second\n\nCosts [coins:250] to unlock.\n")
    write("beta/30-third.md", "# Third\n\nThe last one.\n")

    write("private/10-secret.md", "# Secret\n\nThe formula is [coins:1].\n", "docs")

    Content.register_path(:guide,
      kind: :dir,
      candidates: [Path.join(@root, "guide")],
      post_render: {__MODULE__, :pillify}
    )

    Content.register_path(:docs, kind: :dir, candidates: [Path.join(@root, "docs")])
    Content.reload()

    on_exit(fn ->
      File.rm_rf!(@root)
      Content.reload()
    end)

    :ok
  end

  defp write(relative, body, collection \\ "guide") do
    path = Path.join([@root, collection, relative])
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, body)
  end

  @doc false
  def pillify(html), do: String.replace(html, "[coins:250]", "<b>250 coins</b>")

  describe "collections are separate" do
    test "each lists only its own guides" do
      assert Enum.map(Content.list_docs(:guide), & &1.slug) == ["first", "second", "third"]
      assert Enum.map(Content.list_docs(:docs), & &1.slug) == ["secret"]
    end

    test "a slug in one collection is not found in the other" do
      assert Content.get_doc(:guide, "first")
      refute Content.get_doc(:docs, "first")
      refute Content.get_doc(:guide, "secret")
    end

    test "the cache is keyed by collection, not by slug alone" do
      # Both collections have distinct slugs here on purpose, so a shared cache
      # key would show up as the *second* read returning the first's bytes.
      # Read them in both orders to catch it whichever way round it is wrong.
      guide = Content.doc_html(:guide, "second")
      docs = Content.doc_html(:docs, "secret")

      assert guide =~ "250 coins"
      assert docs =~ "The formula is"
      refute docs =~ "250 coins"
      assert Content.doc_html(:guide, "second") == guide
    end

    test "the default collection is still :docs" do
      assert Content.list_docs() == Content.list_docs(:docs)
      assert Content.get_doc("secret") == Content.get_doc(:docs, "secret")
    end

    test "an unregistered collection is empty rather than a crash" do
      assert Content.list_doc_categories(:nope) == []
      assert Content.list_docs(:nope) == []
      refute Content.get_doc(:nope, "first")
    end
  end

  describe "post_render" do
    test "runs on the collection that declared it" do
      assert Content.doc_html(:guide, "second") =~ "<b>250 coins</b>"
    end

    test "does not run on one that did not" do
      # Same marker, other collection. A hook registered globally rather than
      # per collection would rewrite this too.
      assert Content.doc_html(:docs, "secret") =~ "[coins:1]"
    end

    test "is rejected unless it is a {module, function}" do
      assert_raise ArgumentError, fn ->
        Content.register_path(:bad, kind: :dir, path: @root, post_render: :nope)
      end
    end
  end

  describe "neighbours and categories" do
    test "neighbours run across category boundaries, in reading order" do
      assert {nil, %{slug: "second"}} = Content.doc_neighbours(:guide, "first")
      # "third" is in a different folder; stopping at the boundary would strand
      # the reader on the last page of every section.
      assert {%{slug: "first"}, %{slug: "third"}} = Content.doc_neighbours(:guide, "second")
      assert {%{slug: "second"}, nil} = Content.doc_neighbours(:guide, "third")
    end

    test "the first page has no previous" do
      # `Enum.at(list, -1)` wraps to the END of the list, so this is the case
      # that turns "previous" into "last" if the index is not guarded.
      assert {nil, _next} = Content.doc_neighbours(:guide, "first")
    end

    test "an unknown slug has no neighbours and no category" do
      assert {nil, nil} = Content.doc_neighbours(:guide, "nope")
      refute Content.doc_category(:guide, "nope")
      refute Content.doc_category(:guide, nil)
    end

    test "a category is found by membership and carries its display metadata" do
      category = Content.doc_category(:guide, "first")

      assert category.category == "Alpha"
      assert category.icon == "hero-flag"
      assert category.color == "text-sky-400"
    end

    test "a folder with no _category.md is humanised from its own name" do
      # `beta/` has no `_category.md`, so a new category costs nothing but a
      # directory — the metadata file only overrides the defaults.
      assert Content.doc_category(:guide, "third").category == "Beta"
    end
  end

  describe "excerpts" do
    test "join the whole first paragraph, not just its first line" do
      # Markdown is hard-wrapped, so taking one line cut every card and every
      # <meta name="description"> off mid-sentence.
      assert Content.get_doc(:guide, "first").summary ==
               "An opening paragraph that is hard-wrapped across three source lines so the excerpt has something to join."
    end
  end
end
