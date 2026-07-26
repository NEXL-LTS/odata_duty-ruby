# Kill mutant survivors for the 29 non-MCP ignored subjects

## Summary
Strengthen OdataDuty's **public-API spec suite** so the mutation-testing gate can be turned on for 29 currently-ignored subjects, then delete their entries from `.mutant.yml`. This is test-quality debt cleanup (the ratchet in `spec/using_mutant.md`), scoped to the non-MCP subjects; the 18 `Mcp*` entries stay ignored for a later pass.

## Goal / Problem
`.mutant.yml`'s `matcher: ignore:` list disables the mutation gate on 47 subjects. An ignored subject has **no** mutation verification: SimpleCov proves each line *runs*, but nothing proves each line is *checked*. The 29 subjects in this PRD span the gem's most consumer-visible behavior — `$filter` coercion, property→JSON serialization, `$metadata` EDMX output, OAS2 type mapping, resolver init/paging, and error responses — so their behavior should be pinned by specs a consumer could have written.

- **Current:** these 29 subjects are skipped by `bundle exec mutant run`; surviving mutations in their code go undetected.
- **Expected:** each of the 29 entries is removed, and `bundle exec mutant run '<subject>'` reports **zero surviving mutations** for it — every survivor killed by a public-API spec, or (where a mutation proves the code redundant) by accepting the simplifying source change.

## What it enables
- As a gem maintainer, I can trust that the `$filter`, serialization, metadata, OAS2, paging, and error behaviors these methods implement are locked down by specs — a future refactor that silently changes them fails CI.
- As a contributor, I inherit a shorter ratchet (47 → 18 entries) and worked examples of killing survivors through the public API.

Scope limit: **only** the 29 listed subjects. No new consumer feature, no behavior change intended — where a mutation is *accepted*, the observable output must stay identical (the mutation only removes redundant internal code).

## The 29 subjects, grouped by the consumer behavior they govern
Specs must exercise these through the public API (`Schema` / `SchemaBuilder` execution, generated `$metadata` / `$oas2` / MCP output, resolver hooks) — never by calling the internal method directly (`AGENTS.md`).

| Consumer-observable behavior | Subjects | Public-API surface to assert through |
|---|---|---|
| **`$metadata` EDMX XML** | `EdmxSchema.metadata_xml` | `Schema.metadata_xml` output XML |
| **`$filter` query option** | `Filter#initialize`, `Filter#operation`, `Filter.split_outside_quotes`, `Filter.validate` | `?$filter=` requests routed to `od_filter_eq/ne/gt/lt`; quoted values, multi-clause filters, invalid filters |
| **Object→JSON serialization** | `MapperBuilder#confirm_boolean`, `#confirm_one_of`, `#obj_to_base_hash`, `#obj_to_hash`, `.build_class`, `.eval_erb_class` | collection / individual JSON bodies; `Boolean` coercion; `Enum` (one-of) value validation |
| **Property declaration & mutability** | `Property.new`, `Property.resolve_mutability`, `Property.valid_name?` | `property` declarations; `computed` (`Org.OData.Core.V1.Computed`), `immutable` (`Org.OData.Core.V1.Immutable`), `non_insertable` reflected in `$metadata` / `$oas2`; invalid property names |
| **Property value & type conversion** | `Property::CollectionProp#convert`, `Property::SingleProp#calling_method?`, `#collection?`, `#convert`, `#filter_convert`, `#initialize`, `#load_type_instance_vars`, `#to_oas2_type`, `#to_value` | typed values in JSON output; `$filter` value coercion; `$oas2` type/format for each property type; collection-valued properties |
| **Error responses** | `RequestError#initialize` | error body/status raised for bad requests (e.g. `InvalidQueryOptionError`, `InvalidValue`) |
| **Resolver lifecycle** | `SetResolver#entity_set`, `#handle_init_args_error`, `#initialize`, `#od_next_link_skiptoken` | builder-DSL resolver via `resolver:`; `od_after_init` init-args error path; `@odata.nextLink` server-driven paging |

## External API
None changed. The consumer-facing DSL and outputs are unchanged by design — this PRD adds specs against existing surface and, at most, removes redundant internal code that a mutation proves has no observable effect. New specs land in both spec trees where a subject spans both DSLs: `spec/odata_duty/entity_set/**` (class DSL) and `spec/odata_duty/schema_builder/**` (builder DSL). `SetResolver` subjects are builder-DSL-specific; `Property`/`MapperBuilder`/`Filter`/`EdmxSchema` subjects surface through both.

## Behavior & expected I/O
Every new spec is a runnable usage example asserting observable output. Illustrative shapes:

- **`Filter.split_outside_quotes`** — a `$filter` with a comma or space *inside* a quoted string must not be split: `?$filter=name eq 'Smith, John'` reaches `od_filter_eq('name', 'Smith, John')` as one value. A spec that only used unquoted values would let a "strip the quote-awareness" mutation survive.
- **`MapperBuilder#confirm_boolean`** — a resolver object returning a non-Boolean for a `Boolean` property raises (public error), while `true`/`false` serialize to JSON `true`/`false`; assert both branches so "always return true" / "skip the check" mutations die.
- **`Property::SingleProp#to_oas2_type`** — `$oas2` JSON must show the correct `type`/`format` per property type (e.g. `DateTimeOffset` → `string`/`date-time`); assert each type mapping so a swapped-format mutation is caught.
- **`SetResolver#od_next_link_skiptoken`** — a paged collection returns `@odata.nextLink` with the expected `$skiptoken`, and the final page omits it; assert both so "always/never emit next link" mutations die.
- **`RequestError#initialize`** — a malformed request yields the documented error class with its message/status intact.

For an **accepted** mutation, the before/after observable output is identical — the PR shows the source simplification plus a note that no behavior changed, backed by the existing/added spec.

## Common error cases
The specs pin the framework's existing error contract, asserting these are raised through the public API where the subject governs them: `InvalidQueryOptionError` (bad `$filter`), `InvalidValue` (property coercion failures, e.g. non-Boolean / non-member enum), `UnknownPropertyError` (invalid property reference), `NoImplementationError` (absent `od_*` hook), `ResourceNotFoundError` (unknown key). No new error types are introduced.

## Scope
- **In:** the 29 non-MCP subjects listed above; new/expanded specs in both spec trees via the public API; removal of each entry from `.mutant.yml`; optional accepted-mutation source simplifications with unchanged output; a clean `bundle exec mutant run '<subject>'` per removed entry; full `bundle exec rake` (RSpec + RuboCop + 100% coverage) still green.
- **Out:** the 18 `Mcp*` ignore entries; any consumer-facing behavior change; adding ignore entries; testing internals directly.
- **DSLs:** both class-based and builder, matched to where each subject surfaces (per the table).

## Documentation impact
No consumer guide changes. `spec/using_mutant.md` already documents the ratchet and its shrink count ("47 entries"). Update that count to the post-cleanup number when the entries are removed. Note only; don't rewrite the guide unless asked.

## Open questions
- If any single subject proves to have a genuinely unkillable survivor (a mutation that is neither observably wrong nor safely acceptable), it's surfaced here with the specific mutation rather than silently left in the ignore list — per the "all 29 required" bar.