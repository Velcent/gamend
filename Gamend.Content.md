# `Gamend.Content`
[🔗](https://github.com/appsinacup/gamend/blob/v1.0.7/lib/gamend/content.ex#L1)

Reads and renders Markdown content from project files and directories.

Lookup is path-based rather than theme-config driven. Hosts register named
content sources, and this module resolves whichever configured files or
directories exist for those sources.

All content is cached in `:persistent_term` after the first read.
Call `reload/0` to invalidate everything (e.g. after a config change).

# `asset_path`

```elixir
@spec asset_path(atom() | String.t(), String.t()) :: String.t() | nil
```

Returns the absolute path for an asset relative to a registered content
source. Returns `nil` when not found or path traversal is attempted.

# `blog_neighbours`

```elixir
@spec blog_neighbours(String.t()) :: {map() | nil, map() | nil}
```

Returns `{prev_post, next_post}` neighbours for the given slug (newest-first order).
Either may be `nil`.

# `blog_post_html`

```elixir
@spec blog_post_html(String.t()) :: String.t() | nil
```

Renders a blog post's markdown to HTML, or `nil`.

# `blog_posts_grouped`

```elixir
@spec blog_posts_grouped() :: [{integer(), [{integer(), [map()]}]}]
```

Groups blog posts by `{year, month}` (newest first).
Returns a list of `{year, [{month, [posts]}]}`.

# `changelog_html`

```elixir
@spec changelog_html() :: String.t() | nil
```

Returns the rendered changelog HTML, or `nil` when the changelog path is
not configured or the file doesn't exist.

# `doc_html`

```elixir
@spec doc_html(String.t()) :: String.t() | nil
```

Renders a guide's markdown to HTML, or `nil`.

The leading `# ` heading is dropped: the page renders the title itself, in
the disclosure summary you click to open the guide.

# `frontmatter`

```elixir
@spec frontmatter(String.t()) :: %{required(String.t()) =&gt; String.t()}
```

Reads a leading `---` fenced block of `key: value` lines.

Deliberately not YAML: the values here are single-line strings, and a parser
dependency for that would be its own liability.

# `get_blog_post`

```elixir
@spec get_blog_post(String.t()) :: map() | nil
```

Returns a single blog post map by slug, or `nil`.

# `get_doc`

```elixir
@spec get_doc(String.t()) :: map() | nil
```

Returns a single guide map by slug, or `nil`.

# `list_blog_posts`

```elixir
@spec list_blog_posts() :: [map()]
```

Lists all blog posts sorted newest-first.

Each post is a map with keys:
  * `:slug`  – URL-safe identifier derived from the filename
  * `:title` – extracted from the first `# ` heading (or humanised slug)
  * `:date`  – `Date.t()` parsed from filename prefix or file mtime
  * `:path`  – absolute path to the `.md` file
  * `:excerpt` – first non-heading paragraph (≤ 200 chars)

# `list_doc_categories`

```elixir
@spec list_doc_categories() :: [%{category: String.t(), guides: [map()]}]
```

Lists every guide, grouped into categories in reading order.

Structure comes from the file tree rather than front matter, so a guide is a
file and nothing else has to be edited to add one:

    priv/docs/10-core-setup/20-deployment.md

The numeric prefixes order categories and guides and are stripped from the
slug; the folder name is the category; the title is the first `# ` heading.
Returns `[%{category: String.t(), guides: [guide]}]`, each guide a map of
`:slug`, `:title`, `:summary` and `:path`.

# `list_docs`

```elixir
@spec list_docs() :: [map()]
```

Every guide as a flat list, in the same order as `list_doc_categories/0`.

# `path`

```elixir
@spec path(atom() | String.t()) :: String.t() | nil
```

Returns the resolved absolute path for a registered content source, or `nil`.

# `register_path`

```elixir
@spec register_path(
  atom() | String.t(),
  keyword()
) :: :ok
```

Registers a named content source.

Supported options:
  * `:kind` - `:file` or `:dir`
  * `:path` - single candidate path
  * `:candidates` - ordered candidate paths
  * `:asset_root` - `:self` or `:dirname` when serving assets

# `reload`

```elixir
@spec reload() :: :ok
```

Clears all cached content so the next call re-reads from disk.

# `roadmap_html`

```elixir
@spec roadmap_html() :: String.t() | nil
```

Returns the rendered roadmap HTML, or `nil` when the roadmap path is
not configured or the file doesn't exist.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
