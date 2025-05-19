# Contributor Guidelines

## Running Tests
- Use `bundle exec rake` to run the full test suite, which includes RSpec tests and RuboCop.
- Write tests that rely only on the gem's public API.
- Avoid testing internal classes or methods directly.

## Coding Style
- Follow Ruby 3 syntax with two-space indentation.
- Keep lines under 99 characters.
- The `.rubocop.yml` file defines additional style rules.

## Documentation
- Add or update guides in the `doc/` folder when appropriate.
- Update `README.md` if external usage changes.
