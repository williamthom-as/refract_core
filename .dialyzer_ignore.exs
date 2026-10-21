optional_dep_calls = [
  {"lib/refract/shape/load.ex", :unknown_function}
]

if System.get_env("REFRACT_OPTIONAL") == "none", do: optional_dep_calls, else: []
