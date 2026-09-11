# Changelog

## 0.1.0

- A YAML file becomes a deeply frozen tree of nodes, read once per process, with
  dotted access, `[]`, `dig`, `key?`, `keys` and `to_h`.
- A file is read through the section named after the current environment, and read
  whole when it carries no such section. A single root key leaves the data only
  when it holds a hash of its own.
- Values that belong to the environment are declared in the same file. A name
  derives from the path, an array index joining it as a segment of its own; `env`
  writes the name out instead, `default` gives a fallback.
- A value is mandatory unless it carries a `default` or `optional: true`. A read
  that misses one stops the application, naming every absent variable at once. An
  empty variable counts as absent.
- `type` casts to `string`, `integer`, `float`, `boolean` or `list`; without it
  the class of the default decides, and a `type` written and left empty is refused
  rather than ignored. Integers are read as decimal, so a leading zero is not
  octal.
- A typo in a key raises `NoMethodError` listing the available keys, never a
  silent `nil`.
- `expected_variables` reports the names a file reads and whether each is
  mandatory. It walks the file the way a read does with nothing behind it, so it
  refuses a file that could not load instead of reporting a clean list.
- Everything the loader raises descends from `Kanon::Error`, including a name no
  shell could set, two paths reading one variable, two keys that differ only by
  quoting, a file that cannot be opened, and a directory or environment set to
  nothing.
- Inspection, serialization and error messages carry key names, classes and
  lengths — never values. `Marshal.dump` refuses, and a wrapped failure drops the
  exception that caused it, so the text that broke a cast or a template tag cannot
  reach a log.
- ERB runs before YAML is parsed. Parsing goes through `safe_load` on every psych
  version.
- The format is specified in `docs/specification.md` without reference to Ruby,
  and the reasons behind it are in `docs/decisions.md`.
- Ruby 2.7 and newer. Nothing outside the standard library.
