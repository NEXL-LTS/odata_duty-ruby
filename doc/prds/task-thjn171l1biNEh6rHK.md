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