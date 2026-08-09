# Keeping specs on the public API with a RuboCop cop

`CLAUDE.md` states the rule: tests must use only the gem's public API. The
`OdataDuty/PublicApiOnly` cop (`rubocop/cop/odata_duty/public_api_only.rb`) enforces it
mechanically, over `spec/**/*_spec.rb`. `bundle exec rake` runs RuboCop as part of the
full suite, so an offense fails the same way a broken spec does — locally and in CI.

## What it enforces

Four independent checks:

1. **Internal constants.** Any constant under the `OdataDuty::` namespace that isn't on
   the `AllowedConstants` allowlist (or matched by an `AllowedConstantPatterns` regex) in
   `.rubocop.yml` is flagged. `OdataDuty::Executor`, `OdataDuty::MapperBuilder`, any
   `*Wrapper` — all internal, all flagged. `OdataDuty::EntitySet` — allowlisted, fine.
2. **`__`-prefixed method calls.** Any call to a method starting with `__`, as long as it
   has an explicit or safe-navigated receiver (`schema.__metadata`, `set&.__load`). A
   bare `__foo` with no receiver can only be a spec-local helper or a Ruby builtin, never
   a gem-internal method — those are always called on a gem object — so the cop leaves
   receiverless calls alone.
3. **Visibility bypass.** `send`, `__send__`, `instance_variable_get`,
   `instance_variable_set`, `instance_eval`, `const_get`, `method` — regardless of
   receiver. These reach around Ruby's own method/ivar visibility, which is exactly what
   "use the public API" means to exclude.
4. **Mocking gem behaviour.** `expect_any_instance_of`, `allow_any_instance_of`,
   `stub_const` — regardless of receiver. A spec that mocks how the gem itself behaves
   isn't exercising the gem; it's asserting against a stand-in.

`public_send` is deliberately never flagged — see below.

## What the allowlist means

`.rubocop.yml`'s `OdataDuty/PublicApiOnly` config carries `AllowedConstants` and
`AllowedConstantPatterns`. Between them they *are* the written definition of the gem's
public contract — read the config to see exactly what's public, without inferring it
from `lib/`. The entries fall into four groups, matching the README:

- **Base classes a consumer subclasses** — `EntityType`, `ComplexType`, `EnumType`,
  `EntitySet`, `SetResolver`, `Schema`.
- **Entry points a consumer calls** — `SchemaBuilder`, `EdmxSchema`, `OAS2`.
- **Objects the framework hands to consumer hooks** — `SearchExpression`, `SearchTerm`,
  passed to `od_search` (see `doc/using_search.md`).
- **Rails generators** — `Generators::InstallGenerator`, `Generators::EntitySetGenerator`,
  consumer-facing via `bin/rails generate odata_duty:install`.

Errors are handled separately, by pattern rather than by name: `AllowedConstantPatterns`
matches anything ending in `Error` plus the handful of `Invalid*` classes that don't.
Every class in `errors.rb` is public because consumers rescue them, and deriving that by
pattern means a new error class is public automatically — the correct default, and one
less allowlist edit per new error.

Two rules to keep in mind:

- **Nested constants aren't inherited.** `Schema` being allowlisted does not make
  `Schema::Metadata` or `SchemaBuilder::Schema` public — each nested path needs its own
  allowlist entry (or pattern match) to be accepted. This is the case that leaks in
  practice, so the cop checks the full constant path, not just the outermost segment.
- **The `__` prefix means internal.** The gem already names things this way —
  `__metadata`, `__load`, `__to_value`, `__wrap`, `__member_names` — and the cop
  formalizes it. This matters because RuboCop can't infer types: it has no way to know
  that `subject` holds an `Executor`, so it can't tell that `subject.foo` reaches an
  internal method unless `foo` itself is marked internal by name. Prefixing every new
  internal method on an otherwise-public class with `__` is what keeps this check
  effective as the gem grows.

## Responding to each offense

**Internal constant.** Rewrite the spec through the documented DSL or entry point
instead of naming the internal class. If the constant genuinely needs to be public —
because a consumer hook is handed an instance of it, the way `od_search` receives a
`SearchExpression` — that's an allowlist change, not a workaround; see below.

**`__`-prefixed method.** Find the public method that gets you the same outcome. If
there isn't one, the spec is probably reaching for an implementation detail rather than
an observable behavior — assert on the rendered output (`$metadata`, `$oas2`, the OData
JSON, an MCP response) instead of the internal state that produces it.

**Visibility bypass.** Don't reach around `private`/`protected` with `send` or poke at
instance variables directly — use the public API to set up the scenario and observe the
result. If the only way to observe something is by bypassing visibility, that's a sign
the behavior isn't actually reachable by a consumer, which is worth questioning on its
own.

**Mocking gem behaviour.** Replace the mock with an assertion on the gem's actual output.
`spec/odata_duty/entity_set/select_spec.rb` has the pattern already, in
`CapturingSelectSet`: instead of `expect_any_instance_of(SomeSet).to
receive(:od_select)`, the fixture records what the framework handed it —

```ruby
class CapturingSelectSet < OdataDuty::EntitySet
  class << self
    attr_accessor :captured_select
  end

  def od_select(select)
    self.class.captured_select = select
    # ...
  end
end
```

— and the example asserts on the recording afterward:

```ruby
it 'hands od_select the resolved property names' do
  schema.execute('CapturingSelect', context: Context.new,
                                    query_options: { '$select' => 'id,i' })
  expect(CapturingSelectSet.captured_select).to eq(%i[id i])
end
```

This is strictly better documentation than the mock it replaces: it shows a consumer
exactly what their own `od_select`/`od_search` implementation receives, rather than an
assertion that only makes sense from inside the test suite.

## Widening the allowlist is a contract change

Adding a constant to `AllowedConstants` or a regex to `AllowedConstantPatterns` makes
something part of the gem's public API. Treat it like any other public API addition:
it goes through review, and it needs a corresponding `doc/using_*.md` update explaining
what a consumer can now rely on — the same bar as adding a new DSL method. Don't widen
the allowlist just to make a cop offense go away; widen it only when the constant is
genuinely something a consumer's code is meant to touch.

## Why `public_send` isn't a bypass

`public_send` only ever calls a method that's already public — it can't reach anything
`send` could reach that `public_send` couldn't. Resolver fixtures across the suite use
it legitimately to dispatch on a property name computed at runtime (e.g. reading a
property off a record by its string name). That's normal use of the public API through
a different calling convention, not a visibility bypass, so the cop leaves it alone.
