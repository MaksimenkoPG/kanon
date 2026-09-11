# Kanon

One way to read application configuration: a YAML file becomes a frozen tree of
nodes, and the values that belong to the environment are declared in that same
file.

```ruby
Kanon[:service].token
```

## What it is for

Reading configuration tends to accumulate: a framework helper in one place,
`YAML.load` with ERB in another, `YAML.load_file` inside a class in a third. None
of them caches, so global constants appear for the sole purpose of reading a file
once. Access forms multiply, and a typo returns `nil` — which is how a credential
is silently dropped and an application boots into an outage.

So the defaults here are the opposite ones:

- **A value is mandatory unless declared otherwise.** A missing one brings the
  application down at boot, naming every absent variable at once.
- **A typo raises.** `NoMethodError` with the available keys in the message,
  never a silent `nil`.
- **What was read cannot change.** The tree is deeply frozen and read once per
  process.
- **The file states which variables exist.** That list can be extracted without
  reading the environment, so a pre-boot check needs no grammar of its own.
- **A secret never leaves through diagnostics.** Inspection, serialization and
  error messages carry key names, classes and lengths — never values.

## Installation

```ruby
gem 'kanon'
```

Ruby 2.7 or newer. Nothing outside the standard library: `yaml`, `erb`, `monitor`,
and `json` when `to_json` is called.

## A configuration file

```yaml
default: &default
  :service:
    :endpoint: "https://service.example.com"
    :token: ~
    :timeout: { default: 5 }
    :recipients: { type: list, default: [ops@example.com] }
    :verbose: { default: false }

production:
  <<: *default
```

The variables it expects:

```sh
SERVICE_TOKEN=a-real-token
SERVICE_RECIPIENTS=alice@example.com,bob@example.com
```

What the application gets:

```ruby
Kanon[:service].token        # => "a-real-token"
Kanon[:service].recipients   # => ["alice@example.com", "bob@example.com"]
Kanon[:service].timeout      # => 5
Kanon[:service].verbose      # => false
```

**Which part of the file is read.** A file is read through the section named after
the current environment; one whose top level carries no such key is read whole, so
a list or a dictionary needs no section wrapper around it. A single root key
becomes the prefix of every variable name below it, and leaves the data when what
it holds is a hash of its own — hence `Kanon[:service].token` above, not
`.service.token`. Over a list or over a declaration it stays in the data and only
lends its name, and several root keys all stay, each prefixing its own subtree.

**What a scalar means.** A scalar holding a value is a constant of the file and
never looks at the environment. An empty one means "expected and not given", under
a name built from the path with levels joined by a single `_`: `service` → `token`
reads `SERVICE_TOKEN`, and a nested `pool` → `size` would read
`SERVICE_POOL_SIZE`.

**What a hash means.** A hash whose keys all come from the four words below
declares a value the environment may provide, so `timeout` stays `5` until
`SERVICE_TIMEOUT` says otherwise.

- **`env`** — the variable name, written out instead of derived from the path.
- **`default`** — the value when the variable is absent, cast the same way a
  variable is.
- **`type`** — one of `string`, `integer`, `float`, `boolean`, `list`. Writing the
  key and leaving it empty is refused rather than ignored; leaving it out lets the
  class of the `default` decide.
- **`optional: true`** — the only way to let a value be missing and still boot.
  Only a literal `true` counts: the string `'false'` is truthy in Ruby and would
  otherwise switch the flag on. An empty string written as the `default` is a
  different thing — it is a value, and it reaches the consumer.

**Two forms whose sides look different.** A list is a real array in the file and
one comma separated string in the environment, spaces around the commas ignored;
an array default implies `type: list`. A variable that leaves no items after
parsing, `,,` for instance, counts as no value at all and fails the boot rather
than falling back to the default. A boolean takes `1`, `true`, `yes`, `on` and
`0`, `false`, `no`, `off` in any case, stopping the boot on anything else and
naming what it does accept. Numbers and strings hold no such surprise —
`SERVICE_TIMEOUT=10` yields the integer `10`, and a leading zero is not octal.

An array written out in the file is a different thing entirely from `type: list`,
and the next section is about it.

**How the file is processed.** ERB runs before YAML is parsed, so
`<%= ENV.fetch(...) %>` needs no marker, both styles mix in one file, and control
tags (`<% if %> ... <% end %>`) may build the structure of the file itself. YAML is
then parsed with `safe_load` on every psych version: symbol keys and `<<: *default`
anchors work, while `!ruby/...` tags and types outside the allowed list are never
built.

### Arrays

An index is a path segment like any other key, so a value inside an array is
named after the position it sits at:

```yaml
:service:
  :queues:
    - :name: ~        # SERVICE_QUEUES_0_NAME
    - :name: ~        # SERVICE_QUEUES_1_NAME
  :matrix:
    - [~, ~]          # SERVICE_MATRIX_0_0, SERVICE_MATRIX_0_1
```

Depth is not limited; one segment joins the name per level. A file whose root is
an array has no root key to borrow, so it takes the name of the file — the same
name that wraps it into a node:

```yaml
# endpoints.yml
- :url: ~             # ENDPOINTS_0_URL, read back as .endpoints[0].url
```

The position is the entire name, which makes these names brittle. Insert an
element at the head and every name below it shifts by one: the value meant for one
element lands in its neighbour, and the boot stops only if some name in the
shifted range holds nothing. Reordering a list becomes an edit of the environment,
not of the file alone.

So an array the environment fills is usually better declared than written out.
`type: list` gives the whole list one stable name, and `env` gives a single
element a name of its own:

```yaml
:service:
  :queues:
    - :name: { env: PRIMARY_QUEUE }
    - :name: { env: BACKUP_QUEUE }
```

An array whose values are all in the file asks nothing of the environment and
carries none of this.

## The interface

- **`Kanon.directory`, `Kanon.environment`** — what is in force right now.
- **`Kanon.directory = path`** — where the files live, `config` until set.
- **`Kanon.environment = name`** — which section to read, taken from `APP_ENV`,
  then `RAILS_ENV`, then `RACK_ENV`, else `development`; an empty variable is
  skipped in favour of the next one, and surrounding whitespace is trimmed off
  whichever name wins. Setting either of the two empties the cache.
- **`Kanon[:service]`** — the node from the cache, the same object every time. On
  a miss it falls back to `load_config`, so a cleared cache heals itself.
- **`Kanon.load_config(:service)`** — reads once and remembers; later calls return
  that same object.
- **`Kanon.load_configs(:service, :storage)`** — the same for several names at
  once, returning `{ service: node, storage: node }`.
- **`Kanon.read_config(:service)`** — reads the file again and leaves the cache
  alone. A new object with equal data, so compare readings by value.
- **`Kanon.expected_variables(:service)`** — the names the file reads and whether
  each is mandatory, `{ 'SERVICE_POOL_SIZE' => false }`, without reading one of
  them. It walks the file the way a read does, so a file that could not load is
  refused here too instead of reporting a clean list.
- **`Kanon.loaded_files`** — which files the cache holds.

Every reader that resolves values stops the application when a mandatory one is
missing, naming every absent variable at once; `expected_variables` reads none of
those variables and never fails that way — what it refuses is a file the loader
could not read at all. One `load_configs` at boot turns this into a single check at
startup instead of a failure at first use.

A reader hands back a node, never a hash:

- **`node.token`** — a key written out in the code. A typo raises `NoMethodError`
  listing the keys that are there.
- **`node[:token]`, `node['token']`** — a key computed at runtime, as a symbol or
  a string.
- **`node.dig(:pool, :size)`** — the same at depth, and into arrays by index.
- **`node.key?(:token)`, `node.keys`** — what the node holds.
- **`node.to_h`** — a copy for a third party that needs a hash. Its containers are
  new and unfrozen; leaf strings stay the frozen ones of the tree.

What any implementation of this format must do — the grammar of a declaration, how
a variable name is derived, the casting table, the order of checks — is in
[docs/specification.md](docs/specification.md). Why it is shaped that way, and the
known edges it leaves, are in [docs/decisions.md](docs/decisions.md).

## What the loader refuses

Every name below lives under `Kanon::` and descends from `Kanon::Error`.

- **`FileMissing`** — the file is absent, or the name is not a bare file name at
  all.
- **`InvalidSource`** — the file exists but cannot be read: a directory or a file
  the process may not open, broken YAML, an alias with no anchor, a failing ERB
  tag, a forbidden YAML type, a document that refers to itself through an alias,
  or two keys that become one when they turn into symbols.
- **`EmptyDirectory`** — the directory was set to nothing: `nil`, or a string with
  no more than whitespace in it.
- **`EmptyEnvironment`** — the environment was set to nothing, by the same
  measure.
- **`MissingValue`** — a mandatory value is absent or empty, naming every such
  variable at once.
- **`InvalidValue`** — a value does not fit its type, or a declaration names a
  type outside the five.
- **`InvalidDeclaration`** — a declaration carries an unsupported key.
- **`InvalidVariableName`** — a name no shell could set, derived or written out
  in `env`: anything but a letter or `_` followed by letters, digits and `_`.
- **`ConflictingVariable`** — two paths read one variable, derived or explicit.
- **`UnknownKey`** — an unknown key in `[]`, a `dig` that ran into a scalar, an
  index past the end of an array.
- **`ReservedKey`** — a key named after a node method, which would otherwise
  shadow the value.

Outside that family the loader lets Ruby speak: `NoMethodError` for a typo in a
key, listing the keys that are there, and `FrozenError` for an attempt to change
what was read.

An empty string counts as an absent value. No message of Kanon's own prints a
value: a failing cast reports the class and the length instead. Names it does
print — a key, a variable, a declared type — so a secret an ERB tag put in one of
those places reaches the message like any other name.

Reserved keys are every public instance method the node has: its own (`[]`,
`dig`, `key?`, `keys`, `to_h`, `==`, `eql?`, `hash`, `inspect`, `as_json`,
`to_json`, `encode_with`, `marshal_dump`, `instance_variables`) and all of
`Object`'s, `class` and `dup` and `send` and `freeze` and `tap` among them. Private
`Kernel` methods such as `format` or `timeout` are free to be keys.

## What never leaves through diagnostics

`inspect`, `as_json`, `to_json` and `to_yaml` print key names only,
`instance_variables` is empty and `Marshal.dump` refuses, so a tree of secrets
reaches neither a JSON response, nor a log, nor a queue. A typo reports what is
there without any value: `undefined method 'tokn' for #<Kanon::Node keys: url,
username, token>`.

A failure the library wraps drops the exception that caused it, so the offending
text cannot reach a log through `cause`, through `full_message` or through an
exception tracker that walks the chain. Ruby's own `FrozenError` is the exception
to all of this: an attempt to change a leaf prints the value it refused to change,
and nothing here can stop it.

One hole cannot be closed from here: `Oj.dump` in `:object` mode reads instance
variables through the C API, past any Ruby method, and prints the values. That
holds for every object of an application, not only these; the cure is
`Oj.default_options = { mode: :compat }` on the application side.

## What it is not

- **Not a validator.** There is casting and there is mandatoriness; format,
  ranges and allowed values are out of scope.
- **Not hot reload.** A config is read once per process; changing a value means
  restarting.
- **Not a secret store.** Values arrive from the environment; rotation and
  permissions belong to the infrastructure.
- **Not a way to express structures through the environment.** Nested structures
  live in the file. A variable overrides a scalar, or a flat list of scalars
  given as a comma separated string.

One edge is worth knowing before converting a file: a hash of data whose keys all
come from the declaration vocabulary is read as a declaration, and a key named
`env` makes one on its own. The rest are in
[docs/decisions.md](docs/decisions.md).

Reading through a node costs about five times a plain hash read, and about seven
times when every read goes through `Kanon[...]`. It shows only in loops of hundreds
of thousands of reads — on a hot path take the node into a local variable once. The
numbers come from `script/benchmark.rb`, which needs no framework:
`ruby -Ilib script/benchmark.rb`.

## License

MIT. See [LICENSE](LICENSE).
