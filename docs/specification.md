# Kanon: the specification

What an implementation must do, in any language. The reasons behind these rules
are in [decisions.md](decisions.md); the Ruby interface is in the
[README](../README.md).

The key words MUST, MUST NOT, REQUIRED, SHALL, SHALL NOT, SHOULD, SHOULD NOT,
RECOMMENDED, MAY and OPTIONAL in this document are to be interpreted as described
in [RFC 2119](https://www.rfc-editor.org/rfc/rfc2119.html). They carry that
meaning only in capitals.

## 1. What this describes

A **configuration** is one text file. Reading it yields a **tree**: mappings,
sequences and scalars, where some scalars came from the file and some came from
outside it. The file says which ones come from outside, and under what names.

Terms used below:

- **document** — what the file parses to before anything is done with it.
- **node** — a mapping in the result tree, as the consumer sees it.
- **leaf** — a scalar position, or a declaration standing in for one.
- **path** — the keys and indices from the root of the document down to a leaf.
- **declaration** — a mapping that describes a value instead of being one.
- **source** — a lookup from a name to text or nothing. The reference
  implementation reads the process environment.
- **refusal** — a named failure. The names in section 11 are normative, how an
  implementation represents them is not.

## 2. Settings

An implementation MUST take two settings from its caller and MUST NOT discover
them any other way.

**directory** — where configuration files live, `config` until set.

**environment** — which section to read. When the caller does not set it, an
implementation MUST take the first of `APP_ENV`, `RAILS_ENV`, `RACK_ENV` that is
not empty, and MUST fall back to `development` when none is.

Throughout this document, **empty** means absent, or text holding nothing once
surrounding whitespace is removed. Setting either to nothing MUST be refused, as
`EmptyDirectory` and `EmptyEnvironment`, and what is stored MUST have surrounding
whitespace removed. Both settings are process-wide, and changing either MUST empty
the cache of section 13.

## 3. Locating the file

A configuration is addressed by name. A name MUST consist only of lowercase
letters, digits and underscores; anything else MUST be refused as `FileMissing`
without touching the filesystem, which also forbids paths.

The file is `<directory>/<name>.yml`. When no such file exists the refusal is
`FileMissing`. When it exists but cannot be opened — it is a directory, or the
process may not read it — the refusal is `InvalidSource`.

## 4. Reading the document

The file is turned into a document in three steps, in this order.

**4.1 Template pass.** The text is run through a template pass before it is
parsed. The pass MAY build the structure of the file, not only its values, so a
conditional MAY decide whether a key exists at all. When the pass fails, the
refusal is `InvalidSource` and the message MUST carry only the kind of failure,
never the text that failed.

The template language is implementation-defined; the reference implementation
uses ERB. **This is the one part of a configuration that does not port.** A file
carrying template tags is tied to the implementation that reads it, and an
implementation MUST document which language it accepts.

**4.2 Parse.** The result of the template pass is parsed as YAML.

- Only the first document MUST be read. A `---` separator starts a second one,
  and everything past it is dropped.
- Aliases and merge keys MUST be resolved, `<<: *anchor` included.
- The permitted values are text, numbers, booleans, nothing, mappings and
  sequences. Anything else the parser would build — a timestamp, a
  language-specific object — MUST be refused as `InvalidSource`.
- A malformed document, and a document referring to itself through an alias, MUST
  be refused as `InvalidSource`. An implementation MUST NOT let a self-referring
  document exhaust its stack.

**4.3 Key normalisation.** A key written as an unquoted scalar beginning with a
colon names the same key as that text without the colon, so `token:` and `:token:`
are one key. A key written in quotes names exactly its text, so `":token":` is a
third, different key. Two keys in one mapping that normalise to one name MUST be
refused as `InvalidSource`, naming both spellings.

The distinction rests on quoting, which a parser knows but a plain mapping of the
parse result no longer carries. An implementation whose parser discards it MUST
document that a quoted key beginning with a colon is not supported, rather than
quietly merging it with the unquoted spelling.

Keys that are not text at all — a number, a boolean, a sequence used as a key —
are kept as they are. They are reachable by computed access but never by a
literal one, and a variable name derived through one is refused by section 8.

## 5. Choosing the section

If the document is a mapping and its top level holds a key equal to the
environment name, the document MUST be narrowed to the value under that key.
Otherwise the document MUST be read whole. A file with no sections is therefore
read as it stands, and nothing forces a section onto a list or a dictionary.

A narrowed section holding nothing MUST be read as an empty mapping.

## 6. The root key

When the document is a mapping with exactly one key, and that key holds a mapping
which is not a declaration, the key MUST be removed from the data and MUST become
the first segment of every variable name derived inside it.

In every other case the single key stays in the data: over a sequence, over a
scalar, and over a declaration. It is then an ordinary path segment, so the names
derived below it are the same either way — only the reading path differs.

When the document is a sequence, the **file name** MUST become the first segment
of every variable name derived inside it, and the result MUST be wrapped in a
mapping under that same name.

## 7. Declarations

A declaration is a mapping that describes a value. Its vocabulary is exactly four
keys:

- **`env`** — the variable name to read, in place of the derived one.
- **`default`** — what the value is when the source holds nothing.
- **`type`** — how text from the source becomes a value.
- **`optional`** — whether the value may be absent.

A mapping MUST be treated as a declaration when it holds `env`, or when it holds
at least one vocabulary key and no other key. Any other mapping is data.

A declaration holding a key outside the vocabulary MUST be refused as
`InvalidDeclaration`, naming the unwanted keys. A mapping carrying `env` is a
declaration on that key alone, so its other keys are refused rather than keeping
it as data.

`optional` permits a value to be **absent**. Only the value `true` counts, never
the text `"true"`. An empty string written as `default` is a value, not an
absence, and reaches the consumer.

## 8. Deriving a variable name

A derived name is built from the path: the prefix from section 6, then every key
and index down to the leaf. Each segment is rendered as text and upper-cased, and
the segments are joined with a single underscore.

```
:service: { :pool: { :size: ~ } }    →  SERVICE_POOL_SIZE
:service: { :queues: [ { :name: ~ } ] }  →  SERVICE_QUEUES_0_NAME
```

A sequence index is a segment like any key, which means a name records a
**position**. Inserting an element renames every name below it.

A declaration holding `env` uses that name instead, whatever the path.

Every name, derived or written out, MUST match `[A-Za-z_][A-Za-z0-9_]*`; anything
else MUST be refused as `InvalidVariableName`.

Two leaves MUST NOT read one name. The second MUST be refused as
`ConflictingVariable`, naming both paths.

## 9. Resolving a leaf

A scalar that holds a value in the file is a constant: it MUST NOT consult the
source, and its name MUST NOT appear in the report of section 14.

Every other leaf — an empty scalar, or a declaration — resolves in this order:

1. Determine the name (section 8). A name outside the permitted shape is refused
   here, before anything else about the leaf is examined.
2. Refuse a declaration holding keys outside the vocabulary.
3. Refuse a declaration whose `type` is not one of the five names of section 10.
   A `type` key written and left empty is refused too, rather than ignored.
4. Claim the name, refusing a second leaf reading it.
5. Look the name up in the source. Text holding nothing counts as no value; text
   of whitespace only counts as a value.
6. Cast what was found, or the `default` when nothing was found (section 10).
7. When the result is nothing and the leaf is not `optional`, record the name as
   missing.

After the whole document has been walked, if any names were recorded missing the
read MUST be refused as `MissingValue` **naming all of them at once**. An
implementation MUST NOT stop at the first.

A leaf that is `optional` and resolves to nothing MUST appear in the tree with an
empty value rather than being dropped.

## 10. Casting

No value is no value whatever produced it: a `~` in the file, a template tag that
expanded to nothing, and a variable that was never set are the same.

**With an explicit `type`**, one of five:

- **`string`** — rendered as text.
- **`integer`** — read in base ten, so `010` is ten and never eight, and `0x10` is
  refused rather than read as sixteen.
- **`float`** — read as a number, so `1e3` is `1000.0`.
- **`boolean`** — `1`, `true`, `yes` and `on` are true; `0`, `false`, `no` and
  `off` are false; letter case is ignored. Anything else is refused, naming what
  is accepted.
- **`list`** — split on commas, each item trimmed, empty items dropped. A value
  that leaves no items counts as nothing, so a mandatory list fails rather than
  falling back to its default.

A value that does not fit its type MUST be refused as `InvalidValue`. The message
MUST carry the type, the kind of the value and its length — never the value.

**Without an explicit `type`**, the kind of `default` decides: a whole number
casts as `integer`, a number with a fraction as `float`, `true` or `false` as
`boolean`, a sequence as `list`. A `default` that is text imposes nothing, and
whatever the source held arrives unchanged.

Either way a `default` MUST be cast exactly as a value from the source is, so
`{ default: "5", type: integer }` yields the number five.

## 11. Refusals

Every refusal below MUST be distinguishable by the consumer, and an implementation
SHOULD group them under one kind so that a single catch covers the reading of a
file.

- **`FileMissing`** — the file is absent, or the name is not a bare file name.
- **`InvalidSource`** — the file cannot be opened, its template pass failed, it
  cannot be parsed, it holds a forbidden value, it refers to itself, or it holds
  two keys that normalise to one.
- **`EmptyDirectory`** — the directory was set to nothing.
- **`EmptyEnvironment`** — the environment was set to nothing.
- **`MissingValue`** — mandatory values are absent, all named at once.
- **`InvalidValue`** — a value does not fit its type, or a declaration names a
  type outside the five.
- **`InvalidDeclaration`** — a declaration carries a key outside the vocabulary.
- **`InvalidVariableName`** — a name, derived or written out, is not a usable
  variable name.
- **`ConflictingVariable`** — two paths read one name.
- **`UnknownKey`** — a key that is not in the node, an index past the end of a
  sequence, a descent into a scalar.
- **`ReservedKey`** — a key that would shadow a member of the node itself.

An implementation MUST NOT let a failure of the host language escape in place of
one of these while reading a file.

## 12. The result

**One shape.** A consumer MUST NOT be able to tell which values came from the
file and which from the source.

**A node, never a plain mapping.** A reader MUST hand back a node offering access
by a key written out in the code, access by a key computed at runtime, a descent
by path, a test for a key, a list of its keys, and a copy as an ordinary mapping
for a third party that needs one. It MUST NOT pretend to be an ordinary mapping of
the host language.

**A key that is not there is a refusal.** Reading an absent key MUST refuse,
naming the keys that are present; returning nothing MUST NOT happen. A key
computed at runtime refuses as `UnknownKey`. A key written out in the code MAY
instead refuse the way the host language refuses an absent member, as long as the
message names the keys that are there.

**Reserved keys.** If nodes expose named members, a key clashing with one MUST be
refused as `ReservedKey` when the tree is built, rather than shadowed at read
time.

**Immutable.** The tree MUST be deeply immutable, down to the scalars inside
sequences. The copy handed out as an ordinary mapping is new and mutable, while
the scalars inside it remain the immutable ones of the tree.

**Diagnostics carry no values.** Inspection, serialisation and the refusals of
section 11 MUST carry names — of keys, of variables, of declared types — together
with kinds and lengths, and MUST NOT carry a value read from the source or held in
the file as data. A name is printed whatever produced it, a template tag included.
A refusal that wraps a lower failure MUST NOT carry that failure along.

## 13. Caching

A configuration is read once per process and kept. Repeated reading through the
caching reader MUST hand back the same tree, not an equal one. A separate reader
that re-reads the file every time MUST leave the cache alone, and its result MUST
be compared by value.

Reading is lazy: a configuration the application never asks for MUST NOT be read.
Changing either setting of section 2 MUST empty the cache. A reader taking several
names at once MUST cache the trees, not the collection it returns, and MUST
rebuild that collection on every call.

## 14. Reporting expected variables

An implementation MUST offer a report of the names a configuration reads and
whether each must be provided, without consulting the source.

The report MUST be produced by walking the file through the same code a read
walks, with an empty source in place of the real one.

A name is reported as required when, with an empty source, the leaf resolves to
nothing and is not `optional`.

The report walks the document but does not build the tree, so it raises every
refusal of section 11 except two: `MissingValue`, which an empty source would
raise for every name, and `ReservedKey`, which is found only while the tree is
built.

## 15. Out of scope

An implementation MUST NOT extend beyond these.

- **Not a validator.** Casting and mandatoriness are the whole of it; format,
  ranges and permitted values belong to the application.
- **Not a secret store.** Rotation, delivery and permissions belong to the
  infrastructure.
- **Not hot reload.** A configuration is read once per process.
- **Not a way to express structure through the source.** Nested structure lives in
  the file; a value from the source replaces a scalar, or a flat list of scalars
  given as one comma separated text.
- **Nothing about environments beyond the section.** Differences between
  installations belong to variables and to per-environment files, never to logic
  inside the configuration.

## 16. Conformance

An implementation conforms when it follows every MUST in sections 2 to 15.

Two implementations following this text alone MAY still disagree, because prose
cannot cover every case. Agreement between ports is established by a shared corpus
— an input, a source, and the tree or refusal that MUST result — not by a
document. Until one exists, the reference implementation is the tie-breaker.

The known edges of this format are listed in [decisions.md](decisions.md). They
are consequences of the rules above, not departures from them, and a conforming
implementation reproduces them.
