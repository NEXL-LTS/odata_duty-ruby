# Build plan: Mutation-gate the Edm scalar types

PRD: [task-thsjvvi8xs9kEdcmMW.md](./task-thsjvvi8xs9kEdcmMW.md)

Goal: remove the ten `OdataDuty::Edm*.to_oas2` / `.to_value` entries from the `.mutant.yml` debt
ratchet by pinning the consumer-observable contracts of the five OData primitive types with
public-API specs, enriching the create/update coercion-failure message with the underlying
reason, and accepting the behavior-preserving dead-code mutations. Both DSLs, both spec trees.

The single shared coercion path is `lib/odata_duty/create_complex_type_hash_wrapper.rb`, used by
both DSLs, so the message change lands once. The five primitive types live in
`lib/odata_duty/edms.rb`. Specs go under both `spec/odata_duty/entity_set/**` and
`spec/odata_duty/schema_builder/**`.

## Tasks

- [x] **Task 1 — Enrich the create/update coercion-failure message with the underlying reason**

  Task text: When a POST/PATCH body value fails coercion, `InvalidType` currently reports only
  `The value provided for '<name>' is of wrong type`, discarding why. Append the underlying
  reason so API clients see the cause. Change `create_complex_type_hash_wrapper.rb`'s
  `rescue InvalidValue` to `rescue InvalidValue => e` and raise
  `"The value provided for '#{method_name}' is of wrong type: #{e.message}"`. In `edms.rb`, the
  four `rescue StandardError => e; raise InvalidValue, e.message` sites carry an equivalent
  mutant `raise InvalidValue, e` (`e.to_s == e.message`); adopt the simpler `raise InvalidValue, e`
  form so it is not a false survivor. Add public-API specs in **both** spec trees asserting the
  enriched message for each of the five primitive types (`Edm.Int64`, `Edm.String`, `Edm.Date`,
  `Edm.DateTimeOffset`, `Edm.Boolean`) on **both** create and update, matching the reason
  substring (e.g. `invalid date`, `invalid value for Integer()`, `not boolean value`).

  Likely files: `lib/odata_duty/create_complex_type_hash_wrapper.rb`, `lib/odata_duty/edms.rb`;
  `spec/odata_duty/entity_set/create/coercion_errors_spec.rb`,
  `spec/odata_duty/entity_set/update/**`, `spec/odata_duty/schema_builder/entity_set/create/**`,
  `spec/odata_duty/schema_builder/entity_set/update/**`.

  PRD excerpt: Before `The value provided for 'birth_date' is of wrong type`; After
  `The value provided for 'birth_date' is of wrong type: invalid date`. The appended reason is
  the coercion failure for each type. Common error case: uncoercible POST/PATCH body value →
  `InvalidType` (400), message `The value provided for '<name>' is of wrong type: <reason>`.

  Dependencies: none.

- [x] **Task 2 — Pin the ISO 8601 String coerced-value contract and the Boolean coercion source**

  Task text: Nothing pins that `Edm.Date`/`Edm.DateTimeOffset` coercion hands consumer hooks an
  ISO 8601 **String** (`'2021-01-01'`) rather than a `Date`/`DateTime` object — this is the
  contract. Add specs in **both** spec trees where a `$filter` predicate on a `Date` (and a
  `DateTimeOffset`) property drives `od_filter_eq(property_name, value)` and the resolver/set
  asserts the received `value` is a `String` equal to the ISO 8601 form — killing the `.iso8601`
  removal mutant. Also add a create spec (both trees) passing a custom object that responds to
  `to_boolean` as a `Edm.Boolean` body value and asserting the coerced result, so the
  `object.to_boolean` receiver cannot be mutated to `self.to_boolean`. No lib change.

  Likely files: new filter specs under `spec/odata_duty/entity_set/**` and
  `spec/odata_duty/schema_builder/entity_set/**`; create specs in both trees.

  PRD excerpt: `GET /People?$filter=birth_date eq 2021-01-01` → `od_filter_eq('birth_date',
  '2021-01-01')` — an ISO 8601 String, not a `Date`. `Edm.Boolean` `object.to_boolean` →
  `self.to_boolean`: killed by a create spec passing a custom object responding to `to_boolean`.

  Dependencies: Task 1 (shares edms specs / message behavior).

- [x] **Task 3 — Accept the behavior-preserving dead-code mutations in `edms.rb`**

  Task text: Two pieces of dead code have no observable effect and are resolved by accepting the
  mutation (option 1 in `spec/using_mutant.md`): (a) the `is_collection:` keyword **default**
  on all five `to_oas2` fragments is never used — every framework call site
  (`single_prop.rb`, `collection_prop.rb`) passes it explicitly — so make it a **required**
  keyword: `def self.to_oas2(is_collection:)`. (b) the `Edm.Int64` `object && Integer(object)`
  nil guard is unreachable (nil short-circuits in `SingleProp#convert` before type coercion on
  every public path) — drop the guard: `Integer(object)`. No new tests (existing `$oas2` specs
  already assert single and collection shapes for all five types; the nil path is unreachable).

  Likely files: `lib/odata_duty/edms.rb`.

  PRD excerpt: dead code (12 survivors): the `is_collection:` keyword default is never used and
  the `Edm.Int64` nil guard is unreachable. Per `spec/using_mutant.md` option 1, resolved by
  accepting the mutation — behavior-preserving simplification, no observable change.

  Dependencies: Task 1 (both edit `edms.rb`; sequential to avoid conflict).

- [ ] **Task 4 — Remove the ten `.mutant.yml` entries and verify zero surviving mutations**

  Task text: Delete the ten `OdataDuty::Edm{Bool,Date,DateTimeOffset,Int64,String}.{to_oas2,
  to_value}` entries from the `matcher: ignore:` list in `.mutant.yml`, then run
  `bundle exec mutant run 'OdataDuty::EdmBool*' 'OdataDuty::EdmDate*'
  'OdataDuty::EdmDateTimeOffset*' 'OdataDuty::EdmInt64*' 'OdataDuty::EdmString*'` (the ten
  subjects) and confirm zero alive. If any equivalent mutant remains, resolve per
  `spec/using_mutant.md` (accept it or add a public-API test) — never re-add an ignore entry.

  Likely files: `.mutant.yml`.

  PRD excerpt: The entries to remove (ten listed). Finish by deleting the ten entries and running
  `bundle exec mutant run` on the ten subjects — zero alive.

  Dependencies: Tasks 1, 2, 3.

- [ ] **Task 5 — Documentation and gemspec patch bump**

  Task text: Extend `doc/using_create_update_and_delete.md` to state the coercion-failure message
  now includes the underlying reason (`The value provided for '<name>' is of wrong type:
  <reason>`). Clarify `doc/using_filter.md` that coerced values for `Edm.Date` /
  `Edm.DateTimeOffset` are handed to hooks as ISO 8601 Strings, not `Date`/`DateTime` objects.
  Bump `spec.version` in `odata_duty.gemspec` by a patch level (lib changes).

  Likely files: `doc/using_create_update_and_delete.md`, `doc/using_filter.md`,
  `odata_duty.gemspec`.

  PRD excerpt: Documentation impact — extend `doc/using_create_update_and_delete.md`; clarify
  `doc/using_filter.md`. Scope: gemspec patch bump (lib changes).

  Dependencies: Task 1 (final message wording), Task 2 (contract wording).
