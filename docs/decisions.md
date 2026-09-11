# Kanon: decisions and their reasons

Why the format and the library are shaped the way they are. What an
implementation must do is in [specification.md](specification.md); this document
never restates a rule, only the thinking behind it.

## Principles

Break any of these and the solution stops being itself.

**1. Configuration is data, not code.** Composition, defaults and types live in
the file. Changing a value never means changing the application, and the whole
shape of a configuration is visible in one place.

**2. One way to read, one shape of access.** A node always comes out. There is no
second entry point handing out a raw mapping, and the node never pretends to be
one — partial resemblance hides a forgotten conversion until it breaks somewhere
else.

**3. What was read cannot change.** Immutability is what makes "read once" safe to
rely on: a tree that nobody can edit is the same tree wherever it is passed. The
copy handed to a third party has left the configuration and lives by that party's
rules.

**4. Read once, on first use.** Laziness exists so that a configuration the
application does not need cannot keep it from starting. Caching exists so that a
crowd of global constants does not appear for the sole purpose of reading a file
once.

**5. Failure is loud and early.** A missing value brings the application down at
boot naming every absent variable at once, not one per restart. A typo in a key
is an error listing what is there. The silent empty value is what all of this
exists to prevent: a credential quietly dropped is an outage that starts long
before anyone reads a log.

**6. The file states which variables exist.** The structure is the single source
of truth about what must be provided, and that list can be extracted without
reading any of it, so a check before boot needs no grammar of its own.

**7. No value leaves through the library's own diagnostics.** Names do — of keys,
of variables, of declared types — because a refusal nobody can act on is worse than
one that names what to fix, and a name built by a template tag is printed like any
other. What the host language says on its own is outside this: the error Ruby
raises for an attempt to change an immutable leaf prints the value it refused to
change, and nothing in the library can stop it.

**8. No framework underneath.** The standard library only, with the directory and
the environment injected from outside. Without that there is no library, only a
piece of somebody's application.

**9. A configuration class is optional.** It appears only where something has to
be computed. Reading data takes no code at all.

**10. Whatever was read becomes one shape.** The consumer cannot tell where a
value came from.

## Settled

**YAML, at a cost that is worth naming.** Six complications in the specification
exist only because the format is YAML: a second document after `---`, a
self-referring alias, an alias with no anchor, a forbidden tagged type, two keys
that differ only by a leading colon, and what a file built on `default: &default`
does when it is read outside its sections. A simpler format would carry none of
them.

It is still the right base. The library is meant to read configuration files a
project already has, with the smallest possible edit, and such files are built on
`default: &default` anchors and carry template tags. A format without anchors turns
adopting the library into rewriting every file it is meant to read. YAML also
comes with the standard library, while every alternative costs a dependency and
with it principle 8.

**Domain dictionaries do not belong to this layer.** Lists of types, tax tables and
similar data are the same on every installation and change together with the code.
Principles 5 and 6 work against them: a variable name would be derived from a data
key, an empty entry would read as a missing variable, and arbitrary key text would
be normalised. Dropping the demand for a section made such a file readable; it did
not make reading it a good idea.

**Values come from the environment, and from nothing else.** A pluggable source —
a setter in place of the single environment lookup — was weighed and left out.
Secret stores are reached before the process starts, by tools that export what they
fetched, or by the secret injection of container platforms, and their values arrive
as ordinary variables. One deployment would justify the seam: one forbidden to put
secrets into the process environment at all. Until such a deployment exists the
seam is an abstraction with a single implementation, and adding it later breaks
nothing — the setter is new surface, not changed surface.

**A derived name has to be one a shell could set.** Nothing else can satisfy it,
so a name outside `[A-Za-z_][A-Za-z0-9_]*` is refused at boot rather than asked
for and never answered.

**A marker for declarations was rejected.** The one way to close the edge below
where data can look like a declaration is to demand a marker on every declaration.
That makes the common case pay for the rare one, and every existing file pay for a
collision most of them never hit.

## The Ruby surface

```ruby
Kanon[:name]                       # node from the cache, load_config on a miss
Kanon.read_config(:name)           # node, reads the file every time
Kanon.load_config(:name)           # node, reads once and remembers
Kanon.load_configs(:one, :two)     # { one: node, two: node }
Kanon.expected_variables(:name)    # { name => mandatory? }, reads no such variable
Kanon.directory                    # and Kanon.directory = path
Kanon.environment                  # and Kanon.environment = name
Kanon.loaded_files                 # diagnostics
```

`read` and `load` split "read" from "read and remember"; `[]` is the consumer's
form, honest because everything is warmed up at boot.

Contracts that are easy to lose in a rewrite:

- `load_configs` returns a name-to-node mapping on purpose: a one-letter typo
  (`load_configs` instead of `load_config`) then fails on the same line.
- `read_config` returns a new object with equal data every time. Only
  `load_config` guarantees identity, so compare configurations by value.
- `expected_variables` walks the file through the same code a read walks. A walk
  of its own would drift from the real one, and did.

## Known edges

Consequences of the rules, documented rather than fixed. A conforming
implementation reproduces them.

**A data key can be mistaken for an environment section.** Not demanding a section
costs one silent case: a file whose top-level key happens to be `test` or
`production` is truncated to that branch without a word. A file built around a
`default: &default` anchor gives itself away instead, because every copy of the
anchor resolves at once — the read stops either on the values those copies expect,
named with the section in front (`DEFAULT_SERVICE_TOKEN` beside
`TEST_SERVICE_TOKEN`), or on two paths reading one variable where a declaration
carries an explicit `env`.

**A hash of data can look like a declaration.** Real data uses the four vocabulary
words too. Most such collisions announce themselves: a `type` outside the five
names is refused, and a declaration that demands a value stops the boot naming a
variable nobody meant to set. It passes quietly only when the declaration it
imitates demands nothing — it carries a `default`, or it is `optional` — and the
subtree is then replaced by that default or by nothing. One key from outside the
vocabulary keeps a mapping as data, and that is the escape when converting a file —
but not for a mapping carrying `env`, which is a declaration on that key alone.

**A misspelt declaration key turns the declaration into data.** `{ dfault: 5 }`
carries no word of the vocabulary, so it is data, reads back as data and expects
nothing. "A typo raises" covers a key read out of the tree; nothing can tell a near
miss from a dictionary that happens to be worded that way.

**Only the first document of a file is read.** Everything past a `---` separator is
dropped without a word.

**The shape of the tree depends on how much data is in the file.** A single root
key over a mapping of its own is dropped, so removing the last but one entry of a
dictionary changes every reading path.

**A value with a default hides a vanished variable.** The default takes over
silently; the report of expected variables names it, but nothing compares that list
against the example environment file.

**An index is a position, not a name.** Inserting an element into a sequence
renames everything below it. The file keeps parsing and the shifted names keep
resolving, so the mistake surfaces as wrong values rather than as a failure. A name
that must survive reordering is written out with `env`.

**Whitespace counts differently on the two sides.** A variable holding only spaces
is a value, while an environment name holding only spaces is refused. A name made of
spaces can mean nothing, and a value made of spaces can; the asymmetry is deliberate
and easy to trip over.

**A value reaches the consumer verbatim.** A declaration is substituted after the
document has been parsed, so a value cannot add keys, define anchors or overwrite a
neighbour the way it could through a template tag. In exchange the parser no longer
folds control characters: what the source holds arrives as it is, which matters for
values that end up in mail headers or glued into a URL.
