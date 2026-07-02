# PRD: SimpleCov code coverage with a 100% line + branch gate

> **Scope note — this is a tooling PRD, not an external-API PRD.** Every other document in
> `doc/prds/` describes OdataDuty's consumer-facing API. This one does not: it describes the
> gem's own **test-and-CI workflow**. SimpleCov measures the coverage of the gem's RSpec suite;
> it changes nothing a gem consumer writes or observes. It is filed here because `/build` reads
> from this directory, and the house style (purpose-first, example-driven, error cases) still
> applies.

## 1. Summary

Wire [SimpleCov](https://github.com/simplecov-ruby/simplecov) into the RSpec suite so every full
run measures **line and branch** coverage of `lib/`, and **fails the run (non-zero exit) unless
both reach 100%**. This makes `bundle exec rake` — the check CI runs four times and the
pre-commit hook runs once — refuse to pass when any line or branch in the covered source is
unexercised by the suite.

## 2. Goal / Problem

Today the suite has no coverage measurement at all (`grep -ri simplecov` finds only `/coverage/`
already listed in `.gitignore`). Nothing stops a change from adding a code path — a new `od_*`
branch, an error case, a builder-DSL method — that no spec ever exercises. Because the project
maintains **two parallel DSLs** (class-based and builder) that must stay in sync, an untested
branch in one DSL is easy to miss in review.

**Current behavior:** `bundle exec rake` runs RSpec + RuboCop and reports pass/fail with no
notion of how much of `lib/` was executed.

**Expected behavior:** a full `bundle exec rake` (and a direct full `bundle exec rspec`) also
measures coverage and **exits non-zero if line coverage or branch coverage of the tracked files
is below 100%**, printing which files/lines/branches are missed. A single-file or
`:line`-scoped run (the documented `bundle exec rspec spec/…/foo.rb:42` workflow) still measures
and prints coverage but does **not** fail on the threshold, so day-to-day iteration is unaffected.

## 3. What it enables

- As a maintainer, when I run `bundle exec rake` I get a coverage summary and the build fails if
  any tracked line or branch in `lib/` is unexercised — so untested code cannot merge.
- As a reviewer, CI red on a coverage drop tells me a PR added an unexercised path without my
  having to spot it by eye.
- As a contributor, I can still run `bundle exec rspec spec/odata_duty/entity_set/collection_spec.rb`
  or `…:42` for fast iteration without the coverage gate failing my partial run.
- As anyone, I can open `coverage/index.html` after a run to see exactly which lines and branches
  are missed.

**Scope limits:** coverage is measured for the **RSpec suite only**. It does not measure the
benchmarks (`benchmarks/*.rb`), the ad-hoc generator harness (`bin/test_generator.rb`), or the
Rack demo app (`spec/config.ru`) when those are run standalone. No coverage data is uploaded to
any third-party service.

## 4. External API (developer-facing surface)

Since this is tooling, the "API" is the developer workflow and the config files, not gem DSL.

### 4.1 Dependency

Add SimpleCov as a development dependency in the `Gemfile` (alongside `byebug`, `rspec`,
`rubocop`) — **not** in `odata_duty.gemspec`, since it is never needed at gem runtime and must not
ship in `spec.files`:

```ruby
# Gemfile
gem 'simplecov', '~> 0.22', require: false
```

### 4.2 Start SimpleCov before the code under test loads

Coverage must start **before** `odata_duty` is required, so the loader sees every line. Today
`spec/spec_helper.rb` requires `odata_duty` on line 3; SimpleCov must start above it:

```ruby
# spec/spec_helper.rb (top of file, before any require of the gem)
require 'simplecov'

SimpleCov.start do
  enable_coverage :branch          # measure branch coverage in addition to lines
  primary_coverage :branch         # headline number reported is branch coverage

  add_filter '/spec/'              # don't measure the test code itself
  add_filter '/benchmarks/'
  add_filter '/bin/'
  add_filter 'lib/odata_duty/railtie.rb' # Rails-only glue; never loaded by the RSpec suite

  # Fail the run only when the WHOLE suite ran, so single-file dev runs stay usable.
  if ENV['COVERAGE_ENFORCE']
    minimum_coverage line: 100, branch: 100
  end
end

require 'byebug'
require 'nokogiri'
require 'odata_duty'
# … rest of spec_helper unchanged …
```

### 4.3 Turn the gate on for full-suite runs

The `spec` Rake task (what `rake` default, CI, and the pre-commit hook all invoke) sets the
enforce flag so full runs are strict, while a bare `bundle exec rspec somefile.rb` is not:

```ruby
# Rakefile
require 'rspec/core/rake_task'

RSpec::Core::RakeTask.new(:spec) do |t|
  ENV['COVERAGE_ENFORCE'] = '1' # enforce the 100% gate on the full suite
end
```

Behavior matrix:

| Command                                             | Coverage measured | 100% gate enforced |
|-----------------------------------------------------|:-----------------:|:------------------:|
| `bundle exec rake` (CI ×4, pre-commit)              | yes               | **yes**            |
| `bundle exec rake spec`                             | yes               | **yes**            |
| `COVERAGE_ENFORCE=1 bundle exec rspec`              | yes               | **yes**            |
| `bundle exec rspec` (bare, full suite, no flag)     | yes               | no                 |
| `bundle exec rspec spec/…/collection_spec.rb`       | yes               | no                 |
| `bundle exec rspec spec/…/collection_spec.rb:42`    | yes               | no                 |

### 4.4 Reporting

SimpleCov's default HTML formatter writes `coverage/index.html` (already git-ignored). Add a
terminal summary so CI logs show the numbers without opening HTML — e.g. via
`SimpleCov::Formatter::MultiFormatter` with the HTML formatter plus a small summary line, or the
`simplecov_lcov`/`simplecov-console` formatter if a compact console table is wanted. No
formatter that transmits data off-box is added.

## 5. Behavior & expected I/O

### 5.1 Full suite at 100% — passes

```
$ bundle exec rake
… RSpec examples …
Coverage report generated for RSpec to /home/…/coverage.
Line Coverage: 100.0% (1234 / 1234)
Branch Coverage: 100.0% (456 / 456)
… RuboCop …
$ echo $?
0
```

### 5.2 Full suite below 100% — fails with a non-zero exit

```
$ bundle exec rake
… RSpec examples (all green) …
Coverage report generated for RSpec to /home/…/coverage.
Line Coverage: 99.8% (1232 / 1234)
Branch Coverage: 99.1% (452 / 456)
lib/odata_duty/executor.rb: missed lines 88, 141; missed branches 88[else], 141[then]
SimpleCov failed with exit 2 due to a coverage related error.
  line coverage (99.8%) is below the expected minimum coverage (100.00%).
  branch coverage (99.1%) is below the expected minimum coverage (100.00%).
$ echo $?
2   # rake reports failure; pre-commit blocks the commit; CI job goes red
```

Note the exit is non-zero **even though every example passed** — the coverage shortfall alone
fails the run.

### 5.3 Single-file dev run — measures but never fails on the gate

```
$ bundle exec rspec spec/odata_duty/entity_set/collection_spec.rb:42
.
Coverage report generated for RSpec to /home/…/coverage.
Line Coverage: 6.1% (75 / 1234)
$ echo $?
0   # gate not enforced (COVERAGE_ENFORCE unset) — low % is expected for one file
```

## 6. Common error cases

- **Coverage below the minimum on a full run** → SimpleCov's `at_exit` sets a non-zero process
  exit and prints `line coverage (X%) is below the expected minimum coverage (100.00%)` (and the
  same for branch). RSpec examples may all pass; the run still fails. This is the intended gate.
- **SimpleCov started after `require 'odata_duty'`** → files already loaded before `SimpleCov.start`
  report as fully missed or are absent, producing spurious `0%`/low numbers. The start block must
  precede every `require` of gem code (see §4.2).
- **A newly added `lib/` file with no spec** → it appears in the report at <100% and fails the
  full-run gate until a spec exercises every line and branch, or (only if genuinely unreachable
  by the suite, like `railtie.rb`) it is added to an `add_filter` with a one-line justification.
- **RuboCop failure on the config edits** → the `spec_helper.rb` / `Rakefile` changes must satisfy
  the tightened metrics in `.rubocop.yml` (99-char lines, `MethodLength` 13, etc.) like any other
  code; a lint failure fails `rake` independently of coverage.
- **Partial run mistaken for a pass** → a single-file run reporting a low percentage is *not* a
  failure (gate off by design); only full runs (`rake` / `COVERAGE_ENFORCE=1`) enforce 100%.

## 7. Scope

**In scope**
- `simplecov` dev dependency in `Gemfile`.
- `SimpleCov.start` block at the top of `spec/spec_helper.rb` with branch coverage enabled and a
  full-run-only `minimum_coverage line: 100, branch: 100` gate.
- `spec` Rake task sets `COVERAGE_ENFORCE` so `rake` / CI / pre-commit enforce the gate.
- Filters excluding `/spec/`, `/benchmarks/`, `/bin/`, and `lib/odata_duty/railtie.rb`.
- Whatever **new specs** are required to bring the tracked files to 100% line + branch — covering
  both the class-based and builder DSLs and both spec trees, per CLAUDE.md's "keep both in sync".
- Local HTML report + a terminal coverage summary.

**Out of scope**
- Any change to OdataDuty's consumer-facing DSL or generated `$metadata` / `$oas2` / MCP output.
- Uploading coverage to Codecov/Coveralls or any external service (would need a risk assessment
  and secrets; flag before adding).
- Coverage for standalone benchmarks, `bin/test_generator.rb`, or the Rack demo app.
- Adding a coverage badge or changing the CI matrix/`.github/workflows/ruby.yml` structure
  (the existing `bundle exec rake` steps already carry the gate; no workflow edit is required).

**DSL coverage:** both the class-based DSL and the builder DSL are in scope for *reaching* 100% —
gaps in either fail the gate.

## 8. Documentation impact

- Add a short **"Coverage"** subsection to the **Commands** section of `CLAUDE.md` (and, if a
  human-facing note is wanted, `README.md`): that `rake` enforces 100% line + branch coverage,
  how to read `coverage/index.html`, and that single-file runs don't enforce the gate.
- No new `doc/using_*.md` guide is warranted — this is internal tooling, not a consumer feature.
  (Write nothing until asked.)

## 9. Open questions

- **Attainability of 100% today:** the current suite almost certainly leaves some lines/branches
  in `lib/` unexercised. `/build` must add specs to close every gap; if any file proves
  genuinely unreachable by RSpec (as `railtie.rb` is), it should be `add_filter`ed with a
  one-line reason rather than left failing. The set of such files is unknown until a first
  instrumented run is done.
- **Console formatter choice:** whether to add a dependency like `simplecov-console` for a compact
  terminal table, or hand-print a one-line summary from a tiny inline formatter (no extra dep).
  Defaulting to no extra dependency unless the table is wanted.
- **`refuse_coverage_drop`:** not included (the 100% floor already forbids any drop); can be added
  later if a lower floor is ever adopted.
