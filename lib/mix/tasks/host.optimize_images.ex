defmodule Mix.Tasks.Host.OptimizeImages do
  use Mix.Task

  @moduledoc false

  @shortdoc "Optimizes PNG presentation images"

  @image_exts ~w(.png)
  # Output directories an earlier pipeline could have written into. They are
  # removed up front and skipped while scanning, so a previous generation never
  # becomes the input of the next one.
  @stale_dirs ~w(generated optimized)
  @digest_pattern ~r/-[0-9a-f]{32}\.[^.]+$/i
  @png_animation_chunk "acTL"
  @pngquant_quality "82-96"

  @impl Mix.Task
  def run(args) do
    {opts, _argv, _invalid} =
      OptionParser.parse(args, strict: [required: :boolean, force: :boolean])

    required? = Keyword.get(opts, :required, false)

    case System.find_executable("optipng") do
      nil ->
        message = "optipng not found. Install optipng to optimize PNG images."

        if required? do
          Mix.raise(message)
        else
          Mix.shell().info("Skipping image optimization: #{message}")
        end

      optipng ->
        optimize_images(optipng, System.find_executable("pngquant"), required?)
    end
  end

  defp optimize_images(optipng, pngquant, required?) do
    source_root = Path.expand("priv/static/images")
    remove_stale_image_dirs(source_root)

    results =
      source_root
      |> image_sources()
      |> Enum.map(&optimize_image(optipng, pngquant, &1, required?))

    optimized = Enum.count(results, &(&1 == :optimized))
    current = Enum.count(results, &(&1 == :current))

    Mix.shell().info("Image optimization: #{optimized} optimized, #{current} current")
  end

  defp remove_stale_image_dirs(source_root) do
    Enum.each(@stale_dirs, fn dir ->
      source_root
      |> Path.join(dir)
      |> File.rm_rf!()
    end)
  end

  defp image_sources(source_root) do
    source_root
    |> Path.join("**/*")
    |> Path.wildcard()
    |> Enum.filter(&image_source?(&1, source_root))
    |> Enum.sort()
  end

  defp image_source?(path, source_root) do
    rel_parts =
      path
      |> Path.relative_to(source_root)
      |> Path.split()

    ext =
      path
      |> Path.extname()
      |> String.downcase()

    File.regular?(path) and
      ext in @image_exts and
      not Enum.any?(rel_parts, &(&1 in @stale_dirs)) and
      not Regex.match?(@digest_pattern, Path.basename(path))
  end

  defp optimize_image(optipng, pngquant, source, required?) do
    before_size = File.stat!(source).size

    source
    |> normalize_static_png!(required?)
    |> quantize_png(pngquant)
    |> then(fn normalized_source ->
      {_, 0} = System.cmd(optipng, ["-quiet", "-o3", "-strip", "all", normalized_source])
    end)

    if File.stat!(source).size < before_size do
      :optimized
    else
      :current
    end
  end

  defp quantize_png(source, nil), do: source

  defp quantize_png(source, pngquant) do
    if indexed_png?(source) do
      source
    else
      do_quantize_png(source, pngquant)
    end
  end

  defp do_quantize_png(source, pngquant) do
    before_size = File.stat!(source).size
    tmp = source <> ".quant.png"

    case System.cmd(
           pngquant,
           ["--quality", @pngquant_quality, "--speed", "1", "--force", "--output", tmp, source],
           stderr_to_stdout: true
         ) do
      {_output, 0} ->
        if File.stat!(tmp).size < before_size do
          backup_original_image!(source)
          File.rename!(tmp, source)
        else
          File.rm(tmp)
        end

      {_output, _status} ->
        File.rm(tmp)
    end

    source
  end

  defp indexed_png?(source) do
    case File.read!(source) do
      <<137, 80, 78, 71, 13, 10, 26, 10, _length::32, "IHDR", _width::32, _height::32,
        _bit_depth::8, 3, _rest::binary>> ->
        true

      _other ->
        false
    end
  end

  defp normalize_static_png!(source, required?) do
    if animated_png?(source), do: normalize_animated_png!(source, required?), else: source
  end

  defp normalize_animated_png!(source, required?) do
    (System.find_executable("magick") || System.find_executable("convert"))
    |> normalize_animated_png!(source, required?)
  end

  defp normalize_animated_png!(nil, source, required?) do
    message = "ImageMagick not found. Install imagemagick to convert APNG files to static PNG."
    handle_missing_imagemagick(source, required?, message)
  end

  defp normalize_animated_png!(magick, source, _required?) do
    tmp = source <> ".static.png"
    args = magick_args(magick, source, tmp)
    {_, 0} = System.cmd(magick, args)
    backup_original_image!(source)
    File.rename!(tmp, source)
    source
  end

  defp handle_missing_imagemagick(_source, true, message), do: Mix.raise(message)

  defp handle_missing_imagemagick(source, false, message) do
    Mix.shell().info("Skipping APNG conversion for #{source}: #{message}")
    source
  end

  defp animated_png?(source) do
    source
    |> File.read!()
    |> :binary.match(@png_animation_chunk)
    |> case do
      :nomatch -> false
      _match -> true
    end
  end

  defp magick_args(_magick, source, target), do: ["#{source}[0]", target]

  # pngquant and the APNG flatten both overwrite the tracked source in place, so
  # keep the pre-optimization bytes. IMAGE_BACKUP_RUN_ID groups everything one
  # `assets.deploy` touched under a single directory; without it each call gets
  # its own timestamp.
  defp backup_original_image!(source) do
    root = Path.expand("priv/static/images")
    run_id = System.get_env("IMAGE_BACKUP_RUN_ID") || timestamp()

    relative =
      case Path.relative_to(source, root) do
        ^source -> Path.basename(source)
        value -> value
      end

    target = Path.join([Path.expand("priv/image_backups"), run_id, relative])
    File.mkdir_p!(Path.dirname(target))
    File.cp!(source, target)
  end

  defp timestamp do
    DateTime.utc_now()
    |> Calendar.strftime("%Y%m%dT%H%M%SZ")
  end
end
