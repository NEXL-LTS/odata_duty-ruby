# Test coverage with SimpleCov

This guide is for maintainers and contributors, not consumers of the gem. `odata_duty` measures test coverage with [SimpleCov](https://github.com/simplecov-ruby/simplecov) and enforces **100% line and branch coverage** on full-suite runs. New code must be exercised by the RSpec suite before it lands.

## Overview

- **Purpose:** Guarantee every tracked line and every branch in `lib/` is exercised by the specs.
- **Where:** `spec/spec_helper.rb` starts SimpleCov before the gem loads; `Rakefile` arms the enforcement gate for full runs.
- **Enforcement:** Only `bundle exec rake` (the default task) fails on missed coverage. Single-file `rspec` runs measure and print coverage but never fail on the threshold, so day-to-day iteration stays lenient.
- **Nothing is uploaded** anywhere; the report is written locally to `coverage/`, which is gitignored.

## Running the full suite

`bundle exec rake` runs RSpec and RuboCop, and enforces coverage:

```
bundle exec rake
```

This is what CI runs (four times, to surface flaky tests) and what the pre-commit hook runs. The `spec` task depends on an `enforce_coverage` prerequisite that sets `COVERAGE_ENFORCE=true`, which arms this gate in `spec_helper.rb`:

```ruby
minimum_coverage(line: 100, branch: 100) if ENV['COVERAGE_ENFORCE']
```

If any tracked line or branch is unexercised, the run exits non-zero, the missed lines/branches are printed to the console, and the same detail is available in the HTML report.

## Iterating on a single file

A bare `rspec` invocation does **not** load the `Rakefile`, so `COVERAGE_ENFORCE` is unset and the gate is not armed:

```
bundle exec rspec spec/odata_duty/entity_set/collection_spec.rb
bundle exec rspec spec/odata_duty/entity_set/collection_spec.rb:42
```

These still measure and print coverage, but never fail on the 100% threshold. Run `bundle exec rake` before considering work done to enforce the gate against the whole suite.

## Opening the HTML report

Every run writes an HTML report. Open it to see which lines and branches were missed, highlighted per file:

```
open coverage/index.html        # macOS
xdg-open coverage/index.html    # Linux
```

## What is measured

SimpleCov is configured with branch coverage as the primary metric and excludes paths that are not part of the shipped library:

```ruby
SimpleCov.start do
  enable_coverage :branch
  primary_coverage :branch

  add_filter '/spec/'
  add_filter '/benchmarks/'
  add_filter '/bin/'
  add_filter 'lib/odata_duty/railtie.rb'

  minimum_coverage(line: 100, branch: 100) if ENV['COVERAGE_ENFORCE']
end
```

The filters keep the specs, the benchmarks, the generator harness (`bin/`), and the Rails-only `railtie.rb` out of the numbers, so the 100% target applies to the rest of `lib/`.

`simplecov` is a development dependency in the `Gemfile` (`gem 'simplecov', '~> 0.22', require: false`), not a gemspec runtime dependency, so it never ships in the published gem.

### Scope limits

Coverage is measured for the **RSpec suite only**. It does not cover code exercised outside RSpec:

- the benchmarks (`benchmarks/*.rb`),
- the generator harness (`ruby bin/test_generator.rb`),
- the Rack demo (`spec/config.ru`) run standalone (e.g. via `foreman start`).

Nothing is uploaded anywhere; the report is written locally to `coverage/`, which is gitignored.

## Common Error Cases

When `bundle exec rake` fails on coverage, the output names the file and the specific lines or branches that were not exercised, for example:

```
Line coverage (99.20%) is below the expected minimum coverage (100.00%).
Branch coverage (98.50%) is below the expected minimum coverage (100.00%).
```

Two ways to resolve a failure:

- **Add a test.** This is almost always the right fix — the uncovered line or branch is behavior that no spec exercises. Add a case to the relevant file under `spec/` (remember both DSL spec trees where the code path is shared). Open `coverage/index.html` to see exactly which branch of a conditional was missed.

- **Mark genuinely-unreachable code.** For defensive code that cannot be reached in practice (e.g. an `else` guarding an impossible state), wrap it in SimpleCov's `# :nocov:` markers so it is not counted:

  ```ruby
  def coerce(value)
    case value
    when String then value
    when Integer then value.to_s
    # :nocov:
    else
      raise ArgumentError, "unreachable: #{value.class}"
    # :nocov:
    end
  end
  ```

  Use this sparingly and only for truly-unreachable code; prefer a test whenever the branch is reachable.
