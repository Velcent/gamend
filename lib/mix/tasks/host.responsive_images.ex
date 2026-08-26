defmodule Mix.Tasks.Host.ResponsiveImages do
  use Mix.Task

  @moduledoc false

  @shortdoc "Generates the srcset width variants the presentation config asks for"

  # `"widths": [480, 960]` on a theme/config.json image means the renderer will
  # emit `<base>-480.<ext>` and `<base>-960.<ext>` in a srcset. This task is what
  # puts those files on disk. The renderer drops a width whose file is missing,
  # so a stale run costs bytes rather than broken images — but every width the
  # config names should exist, which is what `--check` asserts.
  @config_path "theme/config.json"
  @static_root "priv/static"
  @webp_quality "80"
  @png_quality "82-96"

  @impl Mix.Task
  def run(args) do
    {opts, _argv, _invalid} = OptionParser.parse(args, strict: [check: :boolean])
    check? = Keyword.get(opts, :check, false)

    planned = planned_variants(File.read!(@config_path))

    if planned == [] do
      Mix.shell().info("No config image declares \"widths\" — nothing to generate.")
      :ok
    else
      planned
      |> Enum.map(&resolve(&1, check?))
      |> report(check?)
    end
  end

  @doc """
  Every `{source, variant, width}` the config's `widths` declarations imply.

  Pure so it can be tested against the real config without touching disk.
  """
  def planned_variants(json) do
    json
    |> Jason.decode!()
    |> collect_images()
    |> Enum.flat_map(fn image ->
      widths = image |> Map.get("widths", []) |> Enum.filter(&(is_integer(&1) and &1 > 0))

      for path <- Enum.filter([image["light"], image["dark"]], &is_binary/1),
          width <- Enum.uniq(widths),
          do: {path, variant_path(path, width), width}
    end)
    |> Enum.uniq()
    |> Enum.sort()
  end

  # Walks the whole config rather than the known page shapes: hero and section
  # images live at different depths, and a new block that carries an "image" is
  # picked up without touching this task.
  defp collect_images(value) when is_map(value) do
    own = if is_map(value["image"]), do: [value["image"]], else: []
    own ++ Enum.flat_map(Map.values(value), &collect_images/1)
  end

  defp collect_images(value) when is_list(value), do: Enum.flat_map(value, &collect_images/1)
  defp collect_images(_value), do: []

  defp variant_path(path, width) do
    ext = Path.extname(path)
    String.replace_suffix(path, ext, "-#{width}#{ext}")
  end

  defp resolve({source, variant, width}, check?) do
    source_file = Path.join(@static_root, source)
    variant_file = Path.join(@static_root, variant)

    cond do
      not File.regular?(source_file) ->
        {:missing_source, variant}

      check? ->
        if File.regular?(variant_file), do: {:current, variant}, else: {:stale, variant}

      # Never upscale: a variant wider than the source is the source, and
      # writing it anyway would put a bigger file behind a smaller descriptor.
      width >= source_width(source_file) ->
        {:skipped_upscale, variant}

      fresh?(source_file, variant_file) ->
        {:current, variant}

      true ->
        generate(source_file, variant_file, width)
    end
  end

  defp fresh?(source_file, variant_file) do
    with {:ok, %{mtime: variant_mtime}} <- File.stat(variant_file, time: :posix),
         {:ok, %{mtime: source_mtime}} <- File.stat(source_file, time: :posix) do
      variant_mtime >= source_mtime
    else
      _ -> false
    end
  end

  defp generate(source_file, variant_file, width) do
    File.mkdir_p!(Path.dirname(variant_file))
    rel = Path.relative_to(variant_file, @static_root)

    args =
      case Path.extname(variant_file) do
        ".webp" ->
          [
            source_file,
            "-resize",
            "#{width}x",
            "-quality",
            @webp_quality,
            "-define",
            "webp:method=6",
            variant_file
          ]

        _ ->
          [source_file, "-resize", "#{width}x", "-strip", variant_file]
      end

    case System.cmd(magick(), args, stderr_to_stdout: true) do
      {_output, 0} ->
        shrink_png(variant_file)
        verify_smaller(source_file, variant_file, rel)

      {output, _status} ->
        {{:failed, output}, rel}
    end
  end

  # ImageMagick writes truecolor PNG, but the sources are pngquant palettes —
  # so a naive 960-wide cut of a 1440 capture came out 25% BIGGER than the
  # original. Requantise to the same recipe host.optimize_images uses.
  defp shrink_png(variant_file) do
    if Path.extname(variant_file) == ".png" do
      pngquant = System.find_executable("pngquant")
      optipng = System.find_executable("optipng")
      tmp = variant_file <> ".quant.png"

      if pngquant do
        case System.cmd(
               pngquant,
               [
                 "--quality",
                 @png_quality,
                 "--speed",
                 "1",
                 "--force",
                 "--output",
                 tmp,
                 variant_file
               ],
               stderr_to_stdout: true
             ) do
          {_output, 0} -> File.rename!(tmp, variant_file)
          _ -> File.rm(tmp)
        end
      end

      if optipng, do: System.cmd(optipng, ["-quiet", "-o3", "-strip", "all", variant_file])
    end

    :ok
  end

  # A narrower cut that weighs more than the full-size original is worse than
  # having no variant at all: the browser would pick it on a small screen and
  # download more than it would have. Drop it rather than ship it.
  defp verify_smaller(source_file, variant_file, rel) do
    if File.stat!(variant_file).size < File.stat!(source_file).size do
      {:generated, rel}
    else
      File.rm!(variant_file)
      {:skipped_bigger, rel}
    end
  end

  defp source_width(source_file) do
    case System.cmd(magick(), ["identify", "-format", "%w", source_file], stderr_to_stdout: true) do
      {output, 0} ->
        case Integer.parse(String.trim(output)) do
          {width, _rest} -> width
          :error -> 0
        end

      _ ->
        0
    end
  end

  defp magick do
    System.find_executable("magick") ||
      Mix.raise("ImageMagick not found. Install imagemagick to generate responsive images.")
  end

  defp report(results, check?) do
    Enum.each(results, fn
      {{:failed, output}, variant} -> Mix.shell().error("  failed #{variant}: #{output}")
      {:missing_source, variant} -> Mix.shell().error("  no source for #{variant}")
      {:stale, variant} -> Mix.shell().error("  not generated: #{variant}")
      _ -> :ok
    end)

    tally = Enum.frequencies_by(results, &elem(&1, 0))
    failed = Enum.count(results, &match?({{:failed, _}, _}, &1))

    Mix.shell().info(
      "Responsive images: #{Map.get(tally, :generated, 0)} generated, " <>
        "#{Map.get(tally, :current, 0)} current, " <>
        "#{Map.get(tally, :skipped_upscale, 0)} skipped (would upscale), " <>
        "#{Map.get(tally, :skipped_bigger, 0)} skipped (variant weighed more)"
    )

    stale = Map.get(tally, :stale, 0) + Map.get(tally, :missing_source, 0) + failed

    if stale > 0 do
      Mix.raise(
        if(check?,
          do: "#{stale} responsive image(s) missing — run: mix host.responsive_images",
          else: "#{stale} responsive image(s) could not be generated"
        )
      )
    end

    :ok
  end
end
