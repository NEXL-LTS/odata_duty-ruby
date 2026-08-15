---
skill: true
description: "Use when adding or changing a schema-level feature in odata_duty — anything a
  consumer writes in the DSL or sees in $metadata, $oas2, or MCP."
---

# Adding a schema-level feature

A feature is only finished when it exists in **both DSLs**, in **both spec trees**, and in **every
rendered surface** that should reflect it. Work through this list.

## 1. Both DSLs

- Class-based DSL — `lib/odata_duty.rb`, `entity_type.rb`, `complex_type.rb`, `enum_type.rb`.
- Builder DSL — `lib/odata_duty/schema_builder.rb` + `schema_builder/*`, with data logic in an
  `OdataDuty::SetResolver` subclass.

See `doc/conventions/dual-dsl.md`. If the feature genuinely applies to only one DSL, say why in the
commit message.

## 2. Every rendered surface

Ask which of these the feature should show up in, and cover each one it should:

- `$metadata` EDMX XML (`EdmxSchema`, `lib/metadata.xml.erb`) — including annotations such as
  `Core.Description` and `Capabilities.*`;
- the OData index document (`index_hash`);
- `$oas2` JSON (`oas2.rb` + `oas2/*_path.rb`), including per-operation request bodies;
- MCP tools (`mcp_server_builder.rb`, `mcp_input_schemas.rb`) — tool list, input schemas,
  descriptions;
- the executed JSON response (`executor.rb`).

## 3. Both spec trees

`spec/odata_duty/entity_set/**` and `spec/odata_duty/schema_builder/**`, written as usage examples
through the public API only — see `doc/conventions/specs.md`.

## 4. Documentation

- Add or update the `doc/using_<feature>.md` guide.
- Add or update the one-line entry in the `AGENTS.md` Features index.
- Update `README.md` if the example usage changes.

## 5. Green

`bundle exec rake` (RSpec + RuboCop + 100% line and branch coverage) and
`bundle exec mutant run --since main` with no survivors.

## Verify

Both DSLs changed, both spec trees have covering examples, every rendered surface the feature
belongs in is asserted on, the `doc/using_*.md` guide and `AGENTS.md` Features entry are current,
and `rake` plus `mutant --since main` are clean.
