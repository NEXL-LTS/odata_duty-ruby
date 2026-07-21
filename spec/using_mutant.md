# Mutation testing with mutant

[Mutant](https://github.com/mbj/mutant) validates the quality of the test suite by mutating the
source code (changing operators, removing statements, altering return values) and re-running the
specs. A mutation that *survives* (specs still pass) means either the code is redundant or a test
is missing. SimpleCov's 100% line/branch coverage (`doc/using_coverage.md`) says every line runs;
mutation coverage says every line is *verified*.

## Running

Configuration lives in `.mutant.yml` (opensource usage, rspec integration). Target subjects with
a [mutant expression](https://github.com/mbj/mutant/blob/main/docs/subject-expressions.md):

```bash
bundle exec mutant run 'OdataDuty::FilterPredicate*'   # a class and all its methods
bundle exec mutant run 'OdataDuty::Executor#count_endpoint'  # a single method
bundle exec mutant run --since main 'OdataDuty*'       # only code touched since main
```

Results persist in `.mutant/` — inspect past runs without re-running:

```bash
bundle exec mutant session show
bundle exec mutant session subject 'OdataDuty::FilterPredicate#initialize'
```

## Handling a surviving mutation

Two options, per mutant's own guidance:

1. **Accept the mutation** — the mutated code is simpler and the tests agree; the original code
   was redundant. Change the source.
2. **Add a missing test** — the original code is correct but unverified. Per `AGENTS.md`, kill the
   mutant through the gem's public API (e.g. asserting behavior a resolver observes), never by
   testing internals directly.

## Daily development flow

1. While working on a class, run mutant against just that subject
   (`bundle exec mutant run 'OdataDuty::Executor#count_endpoint'`) alongside the usual specs.
2. Before pushing, sweep everything the branch touched: `bundle exec mutant run --since main`.
   `--since` diffs the git revision and only mutates subjects whose code changed, so this stays
   fast and never flags code you didn't touch.
3. In CI, the `mutation` job in `.github/workflows/ruby.yml` runs
   `mutant run --since origin/<base branch>` on every pull request — the mutation-testing
   equivalent of a diff review. It is **blocking**: any surviving mutation in code the PR
   touched fails the build.

## The debt ratchet

Mutant has no partial-coverage threshold — one survivor in a matched subject fails the run.
When CI was made blocking, 221 of 339 subjects had pre-existing survivors (3248 mutations,
~67% coverage overall), so those subjects were listed under `matcher: ignore:` in `.mutant.yml`,
the same pattern as `.rubocop_todo.yml`; ongoing cleanup has since shrunk that list to 80
entries. Rules of the ratchet:

- **Never add entries.** A PR that can't pass mutation CI needs better tests, not a bigger
  ignore list.
- **Shrink it as you go.** When you modify an ignored method, delete its entry, run mutant on
  that subject, and kill the survivors (accept the mutation or add a test). Ignored subjects
  are skipped entirely, so an entry means *no* mutation gate on that method.
- The list was generated from a full `bundle exec mutant run`; re-running one after a cleanup
  session confirms the remaining entries are still the right set.

## Notes

- `spec/spec_helper.rb` skips SimpleCov when `MUTANT=1` (set automatically via `.mutant.yml`)
  so coverage tracking doesn't slow down or interfere with mutation runs.
- Mutation runs are not part of `bundle exec rake`; `rake` stays the local pass/fail gate while
  mutant measures test *quality* on the code you changed.
