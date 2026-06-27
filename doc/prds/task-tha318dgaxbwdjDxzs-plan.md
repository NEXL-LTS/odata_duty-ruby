# Build plan — Stop masking `create` / `update` implementation errors

PRD: [task-tha318dgaxbwdjDxzs.md](./task-tha318dgaxbwdjDxzs.md)

## Overview

`Executor#create` / `Executor#update` currently call the consumer's data method and
blanket-rescue `NoMethodError`, re-labeling *every* `NoMethodError` (including bugs inside the
consumer's own code) as `NoImplementationError`. `delete` already does the right thing: it gates
on the `supports_delete?` capability predicate up front and lets any `NoMethodError` from the
consumer bubble up. This plan makes `create` and `update` mirror `delete`.

The production change is in a single shared file — `lib/odata_duty/executor.rb` — which both DSLs
route through, so there is no separate class-DSL vs builder-DSL production change. Tests, however,
must be added to **both** spec trees (`spec/odata_duty/entity_set/**` and
`spec/odata_duty/schema_builder/**`). The `supports_create?` / `supports_update?` predicates
already exist for both DSLs.

## Tasks

- [x] **Task 1 — Fix `create`: gate on `supports_create?`, stop masking `NoMethodError`**

  Task text: Change `Executor#create` (`lib/odata_duty/executor.rb`) to mirror `Executor#delete`:
  raise `NoImplementationError, "create not implemented for #{endpoint.url}"` up front when
  `!endpoint.supports_create?`, then call `endpoint.create` *without* a `rescue NoMethodError`,
  so a `NoMethodError` raised inside the consumer's own `create` propagates unchanged (message +
  backtrace preserved). The genuinely-missing-`create` case keeps the identical message, now
  produced by the capability gate. Add TDD tests to **both** spec trees proving (a) a consumer
  `create` that raises `NoMethodError` propagates that `NoMethodError` (not
  `NoImplementationError`), and (b) a set without `create` still raises `NoImplementationError`
  with the same message. The existing "does not support create" tests already cover (b) — add the
  new "genuine NoMethodError inside create" case mirroring the existing delete spec.

  Likely files:
  - `lib/odata_duty/executor.rb` (`#create`)
  - `spec/odata_duty/entity_set/create/with_scalars_spec.rb` (add `CreateRaisesTestSet` + test)
  - `spec/odata_duty/schema_builder/entity_set/create/with_scalars_spec.rb`
    (add `CreateRaisesTestResolver` + test)

  PRD excerpt — After:
  ```ruby
  schema.create("People", context: ctx, query_options: { "name" => "Alice" })
  # => raises NoMethodError: undefined method `creat!' for Person (consumer's real error)
  ```
  Unchanged genuinely-missing: `schema.create("Countries", ...)` →
  `OdataDuty::NoImplementationError: create not implemented for Countries`.

  Dependencies: none. Mirror the existing delete precedent in
  `spec/odata_duty/entity_set/delete/with_scalars_spec.rb:88` and
  `spec/odata_duty/schema_builder/entity_set/delete/with_scalars_spec.rb:86`.

- [x] **Task 2 — Fix `update`: gate on `supports_update?`, stop masking `NoMethodError`**

  Task text: Change `Executor#update` (`lib/odata_duty/executor.rb`) the same way as Task 1:
  raise `NoImplementationError, "update not implemented for #{endpoint.url}"` up front when
  `!endpoint.supports_update?`, then call `endpoint.update` *without* a `rescue NoMethodError`.
  A `NoMethodError` inside the consumer's `update` propagates unchanged. The genuinely-missing
  case keeps the identical message via the capability gate. The existing `ResourceNotFoundError`
  (falsey return) and key-coercion error paths must remain unchanged. Add TDD tests to **both**
  spec trees: (a) consumer `update` raising `NoMethodError` propagates it, (b) set without
  `update` still raises `NoImplementationError` (already covered), and confirm the
  `ResourceNotFoundError` path still works.

  Likely files:
  - `lib/odata_duty/executor.rb` (`#update`)
  - `spec/odata_duty/entity_set/update/with_scalars_spec.rb` (add `UpdateRaisesTestSet` + test)
  - `spec/odata_duty/schema_builder/entity_set/update/with_scalars_spec.rb`
    (add `UpdateRaisesTestResolver` + test)

  PRD excerpt — After:
  ```ruby
  schema.update("People('1')", context: ctx, query_options: { "name" => "Alice" })
  # => raises NoMethodError: undefined method `touchh' for #<Person ...> (consumer's real error)
  ```
  Unchanged: missing `update` → `NoImplementationError: update not implemented for <url>`;
  falsey return → `ResourceNotFoundError`.

  Dependencies: Task 1 (same file `#create` already gated — keep `#update` symmetric).

- [ ] **Task 3 — Documentation note + patch version bump**

  Task text: Extend `doc/using_create_update_and_delete.md` **Common Error Cases** section with a
  note (parallel to the existing "not implemented" bullet) clarifying that a `NoMethodError`
  raised *inside* a consumer's `create` / `update` propagates unchanged and is **not** rewritten
  to `NoImplementationError` — consistent with `delete`. Bump `spec.version` in
  `odata_duty.gemspec` from `0.20.0` to `0.20.1`.

  Likely files:
  - `doc/using_create_update_and_delete.md`
  - `odata_duty.gemspec`

  PRD excerpt — Documentation impact / Scope: "Patch version bump in `odata_duty.gemspec`
  (`0.20.0` → `0.20.1`)."

  Dependencies: Tasks 1 & 2 (documents the behavior they implement).
