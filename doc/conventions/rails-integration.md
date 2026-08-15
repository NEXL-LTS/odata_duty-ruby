---
paths: ["lib/generators/**", "lib/odata_duty/railtie.rb"]
---

# Rails integration is optional

Rails support loads via `railtie.rb` **only when Rails is present** — the gem itself must keep
working with no Rails in the bundle. Nothing outside `lib/generators/**` and `railtie.rb` may
require or reference Rails constants at load time.

Generators live under `lib/generators/odata_duty/`:

- `install` — controller + schema boilerplate;
- `entity_set` — entity type, set/resolver, specs, and an ActiveRecord concern.

See `doc/entity_set_generator.md`. Exercise changes with `ruby bin/test_generator.rb`, which runs
the generator against a temp dir without a full Rails app.

**Why:** `odata_duty` is a plain Ruby gem; a stray top-level Rails dependency breaks every
non-Rails consumer, and generator templates are not covered by the RSpec suite.

## Verify

`ruby bin/test_generator.rb` passes, `doc/entity_set_generator.md` matches what the generator now
emits, and no Rails constant is referenced outside the railtie/generator load path.
