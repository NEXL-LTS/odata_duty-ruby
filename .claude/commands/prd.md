---
description: Build a Product Requirement Document in doc/prds/ focused on OdataDuty's external/consumer API — what it allows and what it enables. Plans only; no implementation.
argument-hint: <rough idea of the feature or fix>
---

# Create a PRD (Product Requirement Document)

Turn a rough idea — `$ARGUMENTS` — into a focused PRD saved under `doc/prds/`, precise enough that Claude can later **build or fix** the described capability.

OdataDuty is a *library*. Its product is its **external API**: the DSL a gem consumer writes and the OData / EDMX / OAS2 / MCP output they observe. A PRD here describes WHAT that API allows and WHAT it enables for a consumer — never how the gem implements it internally.

## Boundaries

- **Do not implement.** Your only outputs are questions, dialogue, and the PRD document. Never modify `lib/` or `spec/`. If you find yourself reaching for Edit/Write on source code, stop and return to drafting the PRD. The only files you may write are `doc/prds/<name>.md` (and, only if the user explicitly asks, a guide under `doc/`).
- **Stay at the API boundary.** Describe the consumer-facing surface and observable behavior — not the internal machinery.
  - ✅ In scope to describe: the class-based DSL (`OdataDuty::EntityType` / `EntitySet` / `Schema`), the builder DSL (`OdataDuty::SchemaBuilder.build` + `OdataDuty::SetResolver`), declarations like `property` / `property_ref` / `entity_type` / `namespace`, the `od_*` hooks (`od_after_init`, `collection`, `individual`, `create`, `count`, `od_filter_eq/ne/gt/lt`, `od_search`, `od_select`, `od_next_link_skiptoken`), OData query options (`$filter`, `$select`, `$search`, `$top`, `$skip`, `/$count`), and the generated outputs (`$metadata` EDMX XML, the index JSON, `$oas2` JSON, MCP/JSON-RPC resources & tools).
  - ❌ Out of scope to prescribe: `Executor`, the `*Wrapper` classes, the parslet search grammar, ERB templates, mapper builders, or any other internal class. The PRD says what the API does, not how it's wired.
- **Use OData terminology.** OdataDuty exposes an OData service, so the consumer-facing vocabulary should track the [OData v4 spec and vocabularies](doc/odata_crash_course.md), not invented synonyms. When a capability corresponds to a standard OData concept, name the DSL surface (keyword, enum value, query option, hook) after the OData term and **map each one to the exact vocabulary annotation/term it represents** in the PRD. Examples: a read-only/server-set property is `computed` (`Org.OData.Core.V1.Computed`); a set-on-create-only property is `immutable` (`Org.OData.Core.V1.Immutable`); insert/update/delete capability maps to `Capabilities.InsertRestrictions` / `UpdateRestrictions` / `DeleteRestrictions` (and their `Non*Properties` collections); query options keep their OData spelling (`$filter`, `$select`, …). The existing guides (`using_computed.md`, `using_create_update_and_delete.md`) already follow this — match them. Only coin a new name when OData has no corresponding term, and say so explicitly.
- **State the exclusions behind any baseline/audit number.** If the PRD reports a measured baseline (e.g. "0 pre-existing offenses of X today"), name what the count does and doesn't include — especially anything that shares a naming pattern with what's being restricted but isn't actually in scope (e.g. a language built-in that looks like the internal convention being enforced). Otherwise every implementer independently re-derives the same judgment call from scratch, and different ones can resolve it differently.

## Process (lighter / faster — favor a short batch of questions over a long dialogue)

1. **Read the idea.** Use `$ARGUMENTS`. If it's empty, ask the user to describe the goal in their own words (free text, not a multiple-choice question).
2. **Gather context quickly.** Read `README.md`, `CLAUDE.md`, and the most relevant existing guides in `doc/` (`using_search.md`, `using_select.md`, `using_init_args.md`, `odata_crash_course.md`, `mcp_crash_course.md`). Skim the public surface in `lib/odata_duty.rb` and any directly relevant spec under `spec/odata_duty/**` to see how similar capabilities already behave today. Identify the **closest existing guide** — the new capability will usually extend that guide or warrant a new one in the same style.
3. **Loop on clarifying questions until nothing is unresolved.** Ask in batches with `AskUserQuestion` (2–4 at once, not one at a time), then **keep looping**: read the answers, and whenever an answer leaves a gap, contradicts something, or opens a new decision, ask the next batch. Continue until you have zero open questions — every decision needed to write a complete, unambiguous PRD is settled. The PRD you produce **must not contain an "Open questions" section**; resolve each such point with the user instead of deferring it into the document. Favor tight batches over a long one-at-a-time dialogue, but do not stop early just to keep it short — clarity is the exit condition, not question count. Ask only what you genuinely can't infer from context; if the codebase already answers something, don't ask it. Center the questions on:
   - **Goal** — the consumer problem this solves, or (for a fix) the current wrong behavior vs. the expected behavior.
   - **API shape** — how a consumer invokes it: a new `od_*` hook? a new DSL declaration? a new/changed query option? a change to existing output? And **which DSL(s)** it applies to — class-based, builder, or both. When you present naming options, prefer the OData term (see *Use OData terminology* above) and call out which OData vocabulary annotation it maps to.
   - **What it enables & limits** — the capability from the consumer's perspective, and anything explicitly out of bounds.

   Before drafting, confirm to yourself that no open question remains. If any do, run another batch — do not proceed to the draft with unresolved points.
4. **Draft the PRD** using the sections below, with **concrete DSL snippets and expected I/O**.
5. **Review once.** Before showing the draft, do an **OData terminology pass**: walk every consumer-facing name the PRD introduces (keywords, enum values, hooks, query options, output annotations) and confirm each either matches the OData v4 term/vocabulary annotation for that concept — citing it — or is explicitly flagged as a coined name because OData has none. Fix any drift before presenting. Then show the draft and confirm with `AskUserQuestion` (Approve / Revise), noting the terminology check passed. Apply any revisions.
6. **Write** the PRD to `doc/prds/<kebab-summary>.md` and tell the user the path.

## PRD sections

Match the house style of the existing `doc/*.md` guides: purpose-first, example-driven, ending with a "Common Error Cases" section.

1. **Summary** — one or two sentences: the capability and who it's for.
2. **Goal / Problem** — why it matters and the consumer pain it removes. For a fix, state current vs. expected behavior.
3. **What it enables** — short consumer user stories: "As a gem consumer, I can …". Note any scope limits.
4. **External API** — the consumer-facing surface this introduces or changes:
   - A **code snippet** for each affected DSL (class-based and/or `SchemaBuilder`) showing how a consumer writes it.
   - The contract of any new hook/method: the arguments it receives, what it must return, and when the framework calls it.
5. **Behavior & expected I/O** — concrete request → response examples. Where relevant, show the effect across outputs: collection / individual JSON, `$metadata` XML, `$oas2` JSON, and/or the MCP tool/resource shape. For fixes, show realistic before/after.
6. **Common error cases** — which errors are raised and when (e.g. `InvalidQueryOptionError`, `NoImplementationError`, `UnknownPropertyError`, `ResourceNotFoundError`, `InvalidValue`), mirroring the existing guides.
7. **Scope** — explicit in / out boundaries; which DSL(s) are covered.
8. **Documentation impact** — name the guide this should **extend** (e.g. `doc/using_search.md`) or the **new** `doc/<name>.md` to add, in the same style. Note it here only — don't write the guide unless the user asks.

The PRD has **no "Open questions" section** — every decision must be resolved with the user in the questioning loop (step 3) before the document is written. If something feels unresolved while drafting, that is a signal to return to step 3 and ask, not to add a caveat to the document.

## Output

Save to `doc/prds/<kebab-summary>.md` (e.g. `doc/prds/orderby-support.md`), creating `doc/prds/` if needed. Before saving, verify: no internal-implementation prescriptions; every affected DSL has a snippet; expected I/O is concrete; error cases are listed; **every introduced name uses OData terminology and is mapped to its vocabulary term (or flagged as coined)**; **no "Open questions" section and no unresolved decisions remain** (any that surfaced were settled with the user in step 3); and the user approved the draft.

PRDs are transient: `/build` deletes the PRD (and its plan) in a final commit once it's implemented, so git history is the archive.
