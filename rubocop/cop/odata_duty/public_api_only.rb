module RuboCop
  module Cop
    module OdataDuty
      # Flags specs that reach past the gem's documented public API.
      #
      # See doc/prds/public-api-only-cop.md for the full contract.
      class PublicApiOnly < Base
        CONSTANT_MSG = '`%<name>s` is not part of the public API. ' \
                        'Specs must exercise the gem through its documented surface.'.freeze
        INTERNAL_METHOD_MSG = '`%<name>s` is an internal method (`__` prefix). ' \
                               'Specs must exercise the gem through its documented surface.'.freeze
        BYPASS_MSG = '`%<name>s` bypasses method visibility. ' \
                     'Specs must exercise the gem through its documented surface.'.freeze
        MOCKING_MSG = '`%<name>s` mocks gem behaviour. ' \
                      "Specs must assert on the gem's output instead.".freeze

        BYPASS_METHODS = %i[send __send__ instance_variable_get instance_variable_set
                            instance_eval const_get method].freeze
        MOCKING_METHODS = %i[expect_any_instance_of allow_any_instance_of stub_const].freeze

        def on_const(node)
          return if node.parent&.const_type?

          name = node.const_name
          return unless internal_constant?(name)

          add_offense(node, message: format(CONSTANT_MSG, name: name))
        end

        def on_send(node)
          name = node.method_name
          if BYPASS_METHODS.include?(name)
            add_offense(node.loc.selector, message: format(BYPASS_MSG, name: name))
          elsif MOCKING_METHODS.include?(name)
            add_offense(node.loc.selector, message: format(MOCKING_MSG, name: name))
          elsif internal_method_call?(node, name)
            add_offense(node.loc.selector, message: format(INTERNAL_METHOD_MSG, name: name))
          end
        end
        alias on_csend on_send

        private

        def internal_constant?(name)
          name.start_with?("#{namespace}::") &&
            !allowed_constants.include?(name) &&
            allowed_constant_patterns.none? { |pattern| pattern.match?(name) }
        end

        # A bare `__foo` call has no receiver, so it can only be a spec-local helper or a
        # Ruby builtin (e.g. `Kernel#__dir__`) — never a gem-internal method, which is
        # always called on a gem object.
        def internal_method_call?(node, name)
          !node.receiver.nil? && name.to_s.start_with?('__')
        end

        def namespace
          cop_config.fetch('Namespace', 'OdataDuty')
        end

        def allowed_constants
          @allowed_constants ||= Set.new(cop_config.fetch('AllowedConstants', []))
        end

        def allowed_constant_patterns
          @allowed_constant_patterns ||=
            cop_config.fetch('AllowedConstantPatterns', []).map { |pattern| Regexp.new(pattern) }
        end
      end
    end
  end
end
