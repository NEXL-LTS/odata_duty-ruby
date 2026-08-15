---
contents: ['\bod_[a-z_]+']
---

# The `od_*` hook convention

User code communicates with the framework through methods/hooks prefixed `od_`, looked up
dynamically:

- `od_after_init` — runs after the set/resolver is constructed; typically loads `@records`. Takes
  positional or keyword args (see `set_resolver.rb` and `doc/using_init_args.md`).
- `collection`, `individual(id)`, `count` — read operations; `create(input)`, `update(id, input)`,
  `delete(id)` — write operations. A missing one raises `NoImplementationError` (the framework
  rescues `NoMethodError` to detect absence).
- `od_filter_eq/ne/gt/lt(property_name, value)` — narrow results per `$filter`.
- `od_search(expression)` — enables `$search`, in OData and on the MCP `list_/count_<Set>` tools.
- `od_next_link_skiptoken` — drives server-driven paging `@odata.nextLink`.

**Prefer extending these conventions over adding new public API surface.** Capability is inferred
from method *presence*, so a new `od_` hook is opt-in for consumers and automatically reflected in
`$metadata`, `$oas2`, and the MCP tool list; a new public class or required argument is neither.

## Verify

A new consumer-facing extension point is an `od_`-prefixed method detected by presence, not a new
public class, module, or mandatory constructor argument.
