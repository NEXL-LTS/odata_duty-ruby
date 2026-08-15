# A runtime spec guard that raises on non-public-API access

## Summary

A spec-support guard, installed once for the whole suite, that **raises** when a
spec calls a gem method that is not part of the documented public API — for
example `schema.types` or `schema.__metadata` on a `SchemaBuilder::Schema`. It
closes the one gap the `OdataDuty/PublicApiOnly` RuboCop cop cannot: a spec that
holds a legitimately-obtained gem object (e.g. the schema returned by
`SchemaBuilder.build`) and then reaches into an **internal instance method** on
it. RuboCop can't see that, because it has no type information; at runtime the
object's class is known exactly.

This is developer tooling for contributors, not a consumer-facing capability. It
adds no DSL surface and changes no `$metadata`, `$oas2`, OData JSON, or MCP
output. It lives entirely under `spec/`.

**It complements the cop; it does not replace it.** The two are strong in
opposite places and both stay on. See *Relationship to the cop*.

## Goal / Problem

The cop enforces the *name-based* half of "tests use only the public API":
internal constants, `__`-prefixed methods, visibility bypass, and mocking. It
provably **cannot** enforce the *type-based* half:

```ruby
schema = build_schema { |s| s.description = 'Only a description' }
expect(schema.description).to eq('Only a description')   # reads internal state
```

`schema` is a local holding an `OdataDuty::SchemaBuilder::Schema`; `.description`
is an internal `attr_reader`. The cop sees `(send (lvar :schema) :description)`
with no way to know the receiver's type, so it stays silent. This is the
documented "no type inference" hole in the cop PRD's *Scope*.

An audit of the current suite shows this is not hypothetical — specs already read
internal schema state in several places (counts are grep occurrences across
`spec/**/*_spec.rb`):

| Internal reader accessed on a schema in specs | Count |
|---|---|
| `schema.types` | 4 |
| `schema.entity_sets` | 2 |
| `schema.namespace` | 2 |
| `schema.base_url` | 2 |
| `schema.entity_types` | 1 |

Each couples a test to the gem's internal representation instead of asserting on
rendered output, which is exactly what `CLAUDE.md` warns against ("a DSL macro's
own reader is not proof a value propagated — assert against the rendered output").
Because a runtime guard knows the receiver's class, it can catch every one of
these the moment the example runs.

## Relationship to the cop

The guard and the cop cover different failure modes; neither subsumes the other.

| Failure mode | Cop (static) | Runtime guard |
|---|---|---|
| Naming an internal constant (`OdataDuty::Executor`) | **Yes** | Only if executed *and* a method is then called on it |
| `__`-prefixed method call | **Yes** | Yes (if executed) |
| Visibility bypass (`send`, `instance_variable_get`, `const_get`) | **Yes** | No — `instance_variable_get` reads state without a method dispatch |
| Mocking (`expect_any_instance_of`, `stub_const`) | **Yes** | **No** — the violation is in RSpec's test wiring, not a call to a gem object |
| Internal **method** on a real gem object (`schema.types`) | **No** (no types) | **Yes** |
| Violation in an **unexecuted** example/branch | **Yes** | **No** — only sees code that runs |

The cop remains the primary net: it catches the historically-recurring leak
(mocks) reliably, statically, at zero runtime cost, and even in code paths no
test executes. The guard is a targeted second layer for the type-aware case the
cop structurally cannot reach.

## What it enables

- As a contributor, if a spec reads `schema.types` or any other internal method
  on a gem object, the example **fails** with an error naming the class, the
  method, and the fact that it is not public — pointing me at rendered output
  instead.
- As a maintainer, the per-class public-method allowlist becomes a second,
  executable statement of the contract at the *method* level, complementing the
  cop's constant-level allowlist in `.rubocop.yml`.

Out of bounds: it does not catch mocks or `instance_variable_get` (the cop's
job), does not analyse `lib/`, does not police calls the gem makes to itself, and
does not see code an example never runs.

## External API

### Wiring

The guard is spec-support code, required and installed once from
`spec/spec_helper.rb` (or a file it loads under `spec/support/`). It installs a
single global interceptor for the duration of the run; there is **no** per-file
`using` and no per-example opt-in. Because activation is global, the mechanism is
**not** a Ruby refinement (refinements are lexically scoped and cannot be
switched on for the whole suite from one place); see *Mechanism*.

### The guarded-receiver rule

A method call is checked only when **all three** hold:

1. **The method's owner is a gem class.** Keyed on the *defining* class/module
   (the method's `owner`), not the receiver's runtime class. This is what lets a
   consumer's own subclass keep working: `CapturingSelectSet.captured_select` has
   owner `CapturingSelectSet` (a spec fixture, not a gem class), so it is never
   guarded, while `schema.execute` (owner `OdataDuty::SchemaBuilder::Schema`) is.
2. **The call originates from spec code** — the immediate call site is a
   `spec/**/*_spec.rb` file (fixtures defined in spec files included). Calls the
   gem makes to its own internals (call site in `lib/`) are never guarded, so
   `execute` freely calling dozens of internal methods raises nothing.
3. **The method is not on that owner's public allowlist** (below).

When all three hold, the guard raises `OdataDuty::NonPublicApiError` (a new
subclass of `StandardError`, defined in the spec-support file — **not** in
`lib/`, since it is test-only). Otherwise the call proceeds untouched.

Keying on the method **owner** rather than the receiver also means universal
methods (`inspect`, `to_s`, `==`, `class`, …) whose owner is `Object`/`Kernel`
are allowed automatically — unless a gem class overrides one, in which case it
must be allowlisted (the suite legitimately asserts on `schema.inspect`, so
`inspect` is allowlisted wherever a gem class defines it).

### The per-class public-method allowlist

Defined as data in the spec-support file (a frozen map of gem class → set of
allowed public method names), so it reads as the method-level contract:

| Gem class (owner) | Allowed public methods |
|---|---|
| `OdataDuty::Schema` (class-DSL, singleton) | `execute`, `create`, `update`, `delete`, `metadata_xml`, `index_hash`, `to_mcp_server` |
| `OdataDuty::SchemaBuilder` (module) | `build` |
| `OdataDuty::SchemaBuilder::Schema` (instance) | `execute`, `create`, `update`, `delete`, `metadata_xml`, `index_hash`, `to_mcp_server`, plus the builder-definition methods called inside `build { |s| … }`: `add_entity_type`, `add_complex_type`, `add_enum_type`, `add_entity_set`, `version=`, `title=`, `description=`, `inspect` |
| `OdataDuty::EdmxSchema` | `metadata_xml`, `index_hash` |
| `OdataDuty::OAS2` | `build_json` |
| `OdataDuty::SearchExpression` | `terms`, `or?`, `and?` |
| `OdataDuty::SearchTerm` | `value`, `not?`, `to_s` |
| `OdataDuty` error classes (`errors.rb`) | `message`, `code`, `status`, `target`, `backtrace` |

Anything defined on a gem class and **not** in its row is internal, so a
spec-originated call to it raises. Everything on `OdataDuty::Executor`,
`MapperBuilder`, the `*Wrapper` classes, `Property`, `EnumMember`, the `Edm*`
types, the OAS2 path classes, etc. is internal by construction — a spec that
obtains one of those and calls anything on it raises (this is the type-aware
catch the cop can't do).

The exact contents of each row are finalised during the build against what the
suite actually calls; the table above is the audited starting point. Widening a
row is a change to the contract, reviewed like any public-API change — mirroring
the rule for the cop's constant allowlist.

## Behavior & expected I/O

### Raises

```ruby
schema.types                    # OdataDuty::SchemaBuilder::Schema#types is internal
#=> OdataDuty::NonPublicApiError:
#   `types` is not part of the public API of OdataDuty::SchemaBuilder::Schema.
#   Assert on rendered output (metadata_xml/build_json/execute) instead.

schema.__metadata               # __-prefixed internal (also caught by the cop)
OdataDuty::OAS2.build_json(s).paths   # `.paths` on the returned Hash is fine; but
Executor.new(...).some_internal        # any method on an internal object raises
```

### Accepted

```ruby
schema.execute('People', context: Context.new)          # documented
OdataDuty::OAS2.build_json(schema, context: Context.new) # documented entry point
schema.inspect                                           # observable output, allowlisted
def od_search(expr) = expr.terms.map(&:value)            # SearchExpression/Term allowlist
CapturingSelectSet.captured_select                       # consumer's own fixture method
SampleSchema.metadata_xml                                # class-DSL documented method
```

### Not guarded, by design

- **Calls the gem makes to itself.** When a spec calls `schema.execute`, and
  `execute` internally calls `schema.__metadata`, the internal call's site is in
  `lib/`, so it does not raise — only the spec-written call would.
- **Mocks and `instance_variable_get`.** No gem method is dispatched at mock
  setup, and `instance_variable_get` bypasses method dispatch entirely. These
  stay the cop's responsibility.
- **Unexecuted code.** A violating line in an example that never runs is invisible
  until it runs; the cop covers that statically.

### Migrating the existing suite

Turning the guard on raises in the already-identified internal-reader accesses.
All must be resolved in the same change so `bundle exec rake` stays green. For
each (`schema.types`, `schema.entity_sets`, `schema.entity_types`,
`schema.namespace`, `schema.base_url`, and any `e.member`-style error access the
build surfaces), the resolution is one of:

1. **Migrate to rendered output** — replace the internal read with an assertion
   on `metadata_xml` / `build_json` / `execute` output that proves the same
   thing. This is the default and the strictly-better documentation.
2. **Promote to public** — if a reader turns out to be a genuine part of the
   documented contract (candidates to weigh: `namespace`, `base_url`), add it to
   the class's allowlist row *and* document it in the relevant `doc/using_*.md`.
   Promotion is a contract decision, made explicitly per method, not a reflex to
   silence the guard.

The build derives the exact list from the guard's own failures at runtime, not
from a grep, since the guard sees the real receiver types.

## Mechanism

A single `TracePoint(:call)` installed once at suite start. On each Ruby method
entry the handler:

1. Reads `tp.defined_class`; returns immediately unless it is a gem class (fast
   path for the overwhelming majority of calls, which are RSpec/stdlib/fixture).
2. Returns if `tp.method_id` is in that class's allowlist row.
3. Otherwise inspects the call site (`caller_locations`) and raises
   `NonPublicApiError` only if it is a `_spec.rb` file; returns otherwise.

`:call` (not `:c_call`) suffices because every gem method is Ruby-defined. Keying
on `defined_class`/`method_id` gives correct behaviour under inheritance and
`prepend` for free.

**Refinements were considered and rejected** for this: they are lexically scoped,
so they would require a `using` line in every spec file and still would not cover
fixtures cleanly — incompatible with the chosen global, caller-aware activation.

## Coverage / performance

- **Coverage.** The guard lives under `spec/`, which SimpleCov already excludes
  (`add_filter '/spec/'`). Unlike the cop (which lives in `rubocop/` and carries
  a 100% line+branch obligation), the guard is **not** coverage- or
  mutation-enforced. It still ships with its own spec (below); it simply is not
  held to the `lib/`/`rubocop/` bar.
- **Performance.** A global `TracePoint(:call)` fires on every Ruby method entry
  in the suite. The handler must early-exit in O(1) when `defined_class` is not a
  gem class so the common path stays cheap; `caller_locations` is computed only
  for the rare gem-internal-method call. The build **measures** suite wall-clock
  before and after and reports it; if the overhead is unacceptable, the fallback
  is to enable the TracePoint only around each example (`around(:each)`) or to
  narrow it to gem source files. A visible slowdown that cannot be mitigated is a
  reason to reconsider scope, and must be surfaced, not hidden.

## The guard's spec

`spec/rubocop/` is the cop's home; the guard's spec sits under `spec/support/`
or `spec/odata_duty/` as a plain RSpec file. It must cover:

- an internal method on a gem object (e.g. a builder schema's `types`), raises
- a documented method on the same object (`execute`), accepted
- a `SearchExpression`/`SearchTerm` allowlisted method, accepted; a non-allowlisted
  one, raised
- a consumer-subclass method (a fixture's own accessor), accepted
- a call the gem makes to its own internal method (driven via `execute`), **not**
  raised — proving caller-awareness
- `inspect`/`to_s` on a gem object, accepted
- `NonPublicApiError` names the class and method in its message

## Common error cases

- **False positive on gem-internal calls.** Without the caller-site check, every
  internal call `execute` makes would raise. The `_spec.rb`-caller gate is what
  prevents this and must be covered by the "not raised when driven via execute"
  example.
- **False positive on consumer fixtures.** Keying on the method *owner* (not the
  receiver) is what keeps `CapturingSelectSet.captured_select` and
  `SupportsCollectionSearchSet.last_search_terms` working; a receiver-class check
  would wrongly flag them.
- **Missing allowlist entry.** A documented method absent from its row raises a
  false positive; the guard's spec pins the core ones, and the migration step
  finalises the rows against the real suite.
- **Silent gaps are acceptable and expected.** Mocks, `instance_variable_get`,
  and unexecuted violations are explicitly out of scope (the cop's job); the
  guard must not grow branches trying to cover them.

## Scope

**In**

- A spec-support guard installed once from `spec/spec_helper.rb`, with the
  per-class public-method allowlist and the `NonPublicApiError` it raises.
- Its spec.
- Migrating the existing internal-reader accesses the guard surfaces.
- Contributor documentation (below).

**Out**

- **It does not replace the cop.** Both mechanisms stay on; the cop remains the
  primary, static net (mocks, bypass, constants, unexecuted paths).
- `lib/` is not analysed and is not modified (the `NonPublicApiError` is
  test-only, defined under `spec/`).
- Mocks, `stub_const`, and `instance_variable_get` are not caught here.
- Code an example never executes is not caught here.
- No consumer-facing behaviour changes: no DSL, `$metadata`, `$oas2`, OData JSON,
  or MCP output is affected.
- Both DSLs are covered equally (the guard runs over the whole suite), but
  neither DSL changes.

## Documentation impact

**Update `spec/using_public_api_only.md`** — the cop's contributor guide gains a
section on the runtime guard: what it catches that the cop cannot (internal
methods on real gem objects), that it is a complement not a replacement (with the
strong/weak split), how to respond to a `NonPublicApiError` (assert on rendered
output, or promote a method to the allowlist as a reviewed contract change), and
where the per-class allowlist lives.

**Update `CLAUDE.md`** — the "Tests must use only the gem's public API"
convention bullet notes that enforcement is now two-layered: the RuboCop cop for
name/mock/bypass leaks and the runtime guard for internal-method access on gem
objects.

No `## Features` entry — this is contributor tooling, not a consumer capability.
