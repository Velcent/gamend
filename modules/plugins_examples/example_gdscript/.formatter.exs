# `gen/` is included deliberately: the compiler emits through
# `Code.format_string!/1`, so `mix format` and `mix gamend.gdscript.compile`
# must agree, or the two `--check` gates would fight each other.
[
  inputs: ["{mix,.formatter}.exs", "gen/**/*.ex"]
]
