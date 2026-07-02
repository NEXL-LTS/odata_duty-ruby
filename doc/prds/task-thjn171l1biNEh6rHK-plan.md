# Build plan: SimpleCov code coverage with a 100% line + branch gate

> PRD: [task-thjn171l1biNEh6rHK.md](./task-thjn171l1biNEh6rHK.md)

## Nature of this PRD

This is a **tooling** PRD, not a consumer-API PRD. It wires SimpleCov into the RSpec
suite and enforces **100% line + branch** coverage of `lib/` on full-suite runs (`bundle
exec rake`), while leaving single-file iteration (`bundle exec rspec foo.rb[:42]`)
unaffected. Because it is tooling, it does **not** touch the two consumer DSLs — but
reaching 100% coverage requires **new public-API specs across both spec trees**
(`spec/odata_duty/entity_set/**` and `spec/odata_duty/schema_builder/**`).

## Recon findings (measured before planning)

With SimpleCov measure-only wired in, the current suite reports:

- **Line coverage: 97.98%** (29 lines missed)
- **Branch coverage: 84.21%** (51 branches missed)

Uncovered spots (tracked `lib/` files, after filters) include: error-class `#status`
methods and `InvalidValue` rescue paths (`errors.rb`, `edms.rb`), collection-typed
`to_oas2` branches for several `Edm*` types (`edms.rb`), defensive/duplicate-type and
not-found raises, and assorted branches in `executor.rb`, `filter.rb`,
`parslet_search_expression.rb`, `schema_builder/*`, `property/*`, `enum_type.rb`,
`entity_type.rb`, `oas2/individual_patch_path.rb`, and the install generator. All are
reachable through the gem's **public API**; genuinely unreachable defensive lines may use
`# :nocov:` with justification.

## Ordering constraint

The enforcement gate is armed by a `COVERAGE_ENFORCE` env var that the `spec` Rake task
sets. Once the Rakefile sets that flag, `bundle exec rake` **fails** unless coverage is
100%. Therefore enforcement must be turned on **only after** coverage reaches 100%. Task
order below reflects this: measure-only first → close gaps → arm gate → docs.

Each task must end green on `bundle exec rake`. Tasks 1 and 2 stay green because
enforcement is still off (the env var is unset under plain `rake`); their coverage
progress is verified with `COVERAGE_ENFORCE=1 bundle exec rspec`. Task 3 arms the gate and
is green only because Task 2 reached 100%.

---

## Tasks

### - [ ] Task 1 — Add SimpleCov as a measure-only dev dependency

**Task text:** Add SimpleCov to the suite so every full RSpec run *measures* line and
branch coverage of `lib/`, without yet enforcing any threshold under `bundle exec rake`.
Add `gem 'simplecov', '~> 0.22', require: false` to the **Gemfile** (dev deps, alongside
`byebug`/`rspec`/`rubocop`) — **not** `odata_duty.gemspec` (never needed at runtime, must
not ship in `spec.files`). At the very **top** of `spec/spec_helper.rb`, before any require
of the gem, `require 'simplecov'` and call `SimpleCov.start` with: `enable_coverage
:branch`, `primary_coverage :branch`, `add_filter '/spec/'`, `add_filter '/benchmarks/'`,
`add_filter '/bin/'`, `add_filter 'lib/odata_duty/railtie.rb'`, and a guarded gate — `if
ENV['COVERAGE_ENFORCE']` then `minimum_coverage line: 100, branch: 100`. Do **not** modify
the Rakefile yet, so `COVERAGE_ENFORCE` is unset under plain `rake` and the build stays
green. Confirm `bundle exec rake` is green and prints a coverage summary, and that
`coverage/index.html` is generated (`coverage/` is already gitignored).

**Defining PRD excerpt:** §4.1 (`gem 'simplecov', '~> 0.22', require: false` in Gemfile,
not the gemspec) and §4.2 (the `require 'simplecov'` + `SimpleCov.start` block with
`enable_coverage :branch`, `primary_coverage :branch`, the four `add_filter`s, and the
`if ENV['COVERAGE_ENFORCE']` → `minimum_coverage line: 100, branch: 100` guard, placed
above the `require 'odata_duty'` on what is currently line 3).

**Likely files:** `Gemfile`, `spec/spec_helper.rb`, `Gemfile.lock` (regenerated).

**Dependencies:** none.

### - [ ] Task 2 — Close all coverage gaps to 100% (line + branch)

**Task text:** Bring line and branch coverage of the tracked `lib/` files to **100%/100%**
by writing meaningful, behavior-focused specs that exercise every currently-uncovered line
and branch **through the gem's public API only** (never internal classes). Verify with
`COVERAGE_ENFORCE=1 bundle exec rspec` reporting `Line Coverage: 100%` and `Branch
Coverage: 100%`. Where a feature exists in **both** DSLs, add the covering spec under the
matching tree (`spec/odata_duty/entity_set/**` for the class DSL,
`spec/odata_duty/schema_builder/**` for the builder DSL). Reserve `# :nocov:` for lines
that are genuinely unreachable from public API (defensive guards); justify each in the
task report. Known gaps to close (from recon): error-class `#status` and `InvalidValue`
rescue paths; collection-typed `to_oas2` for `Edm*` scalar types; duplicate-type and
resource-not-found raises; and branches in `executor.rb`, `filter.rb`,
`parslet_search_expression.rb`, `schema_builder/*`, `set_resolver.rb`, `property/*`,
`enum_type.rb`, `entity_type.rb`, `oas2/individual_patch_path.rb`, and
`generators/.../install_generator.rb`. Plain `bundle exec rake` must remain green
(enforcement still off).

**Defining PRD excerpt:** §1/§2 — "fails the run … unless both reach 100%"; §3 — "untested
code cannot merge"; the gate is `minimum_coverage line: 100, branch: 100`. For the gate to
pass, the suite must actually reach 100% line and branch coverage of the tracked files.

**Likely files:** new/extended specs under `spec/odata_duty/entity_set/**` and
`spec/odata_duty/schema_builder/**`; possibly small `# :nocov:` annotations in `lib/**`.

**Dependencies:** Task 1 (SimpleCov must be measuring first).

### - [ ] Task 3 — Arm the enforcement gate for full-suite runs

**Task text:** Make the `spec` Rake task (invoked by the `rake` default, CI, and the
pre-commit hook) set `COVERAGE_ENFORCE` so full-suite runs are strict, while a bare
`bundle exec rspec somefile.rb` remains lenient. Set the env var via a mechanism that only
affects the actual spec run (e.g. a prerequisite task that sets `ENV['COVERAGE_ENFORCE']`
before the `RSpec::Core::RakeTask` subprocess is spawned, so the flag is inherited by the
rspec process). After this change, `bundle exec rake` must enforce `minimum_coverage line:
100, branch: 100` — green now (Task 2 reached 100%), and would go red if coverage
regressed. Do not change single-file behavior.

**Defining PRD excerpt:** §3 — "I can still run `bundle exec rspec …:42` for fast iteration
without the coverage gate failing my partial run"; §4.3 — "The `spec` Rake task (what
`rake` default, CI, and the pre-commit hook all invoke) sets the enforce flag so full runs
are strict, while a bare `bundle exec rspec somefile.rb` is not."

**Likely files:** `Rakefile`.

**Dependencies:** Task 2 (coverage must be 100% or this turns `rake` red).

### - [ ] Task 4 — Document the coverage workflow

**Task text:** Document the coverage tooling for maintainers/contributors: add a `doc/`
guide (e.g. `doc/using_coverage.md`) explaining that `bundle exec rake` measures line +
branch coverage and fails below 100%, that the gate is armed only for full runs via
`COVERAGE_ENFORCE` (so single-file `bundle exec rspec foo.rb[:42]` iteration is
unaffected), how to open `coverage/index.html`, the scope limits (RSpec suite only; not
benchmarks/generator harness/Rack demo; nothing uploaded), and the SimpleCov filters in
effect. Update `CLAUDE.md`'s `## Commands` section to note that `bundle exec rake` now also
enforces 100% coverage and point at the guide. This capability is developer-tooling, not a
consumer-facing gem feature, so the `## Features` index in `CLAUDE.md` is **not** amended.

**Defining PRD excerpt:** house-style note in the PRD header ("purpose-first,
example-driven, error cases still applies"); §3 bullets (maintainer/reviewer/contributor
workflows) and "Scope limits" paragraph.

**Dependencies:** Tasks 1–3 (documents their final behavior).
