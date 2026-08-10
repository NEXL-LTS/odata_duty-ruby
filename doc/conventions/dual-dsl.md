---
paths: ["lib/**", "spec/**"]
---

# Two parallel DSLs — keep both in sync

There are **two ways to define a schema**, and most features must be implemented in both:

1. **Class-based DSL** (`lib/odata_duty.rb`, `entity_type.rb`, `complex_type.rb`, `enum_type.rb`):
   subclass `OdataDuty::EntityType`, `OdataDuty::EntitySet`, `OdataDuty::Schema`. The entity set
   itself implements the data methods (`collection`, `individual`, `create`).
2. **Builder DSL** (`lib/odata_duty/schema_builder.rb` + `schema_builder/*`):
   `OdataDuty::SchemaBuilder.build(namespace:, host:, scheme:, base_path:) { |s| ... }` constructs
   the schema at runtime (e.g. from `request` data in a controller). Data logic lives in a separate
   `OdataDuty::SetResolver` subclass referenced by string name via `resolver:`.

The split is mirrored in the specs: `spec/odata_duty/entity_set/**` covers the class DSL,
`spec/odata_duty/schema_builder/**` covers the builder DSL, often with near-identical cases.

**Why:** a feature that lands in only one DSL is invisible to half the gem's consumers, and nothing
mechanical catches the gap — the two trees are independent code paths with independent specs.

## Verify

The change touches both `lib/odata_duty/*` (class DSL) and `lib/odata_duty/schema_builder/*`
(builder DSL), and both `spec/odata_duty/entity_set/**` and `spec/odata_duty/schema_builder/**`
have a covering example — or the feature genuinely applies to only one DSL and the reason is
stated in the commit message.
