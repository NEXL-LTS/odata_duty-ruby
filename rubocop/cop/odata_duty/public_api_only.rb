module RuboCop
  module Cop
    module OdataDuty
      class PublicApiOnly < Base
        MSG_INTERNAL_CONST = '`%<const>s` is not part of the public API. ' \
                             'Specs must exercise the gem through its ' \
                             'documented surface.'.freeze
        MSG_INTERNAL_METHOD = '`%<method>s` is an internal method ' \
                              '(`__` prefix). Specs must exercise the gem ' \
                              'through its documented surface.'.freeze
        MSG_VISIBILITY_BYPASS = '`%<method>s` bypasses method visibility. ' \
                                'Specs must exercise the gem through its ' \
                                'documented surface.'.freeze
        MSG_MOCKING = '`%<method>s` mocks gem behaviour. Specs must assert ' \
                      'on the gem\'s output instead.'.freeze

        def initialize(config, options = nil)
          super
          @allowed_constants = nil
          @allowed_patterns = nil
          @namespace = nil
        end

        def on_const(node)
          return if node.parent&.const_type?

          const_name = full_const_name(node)
          return if allowed?(const_name)

          add_offense(node, message: format(MSG_INTERNAL_CONST, const: const_name))
        end

        def on_send(node)
          check_internal_method(node)
          check_visibility_bypass(node)
          check_mocking(node)
        end

        def on_csend(node)
          check_internal_method(node)
        end

        private

        def check_internal_method(node)
          return unless node.method_name.to_s.start_with?('__')
          return if node.method_name == :__send__ && bypass_method?(node)

          add_offense(node, message: format(MSG_INTERNAL_METHOD, method: node.method_name))
        end

        def check_visibility_bypass(node)
          return unless bypass_method?(node)

          add_offense(node, message: format(MSG_VISIBILITY_BYPASS, method: node.method_name))
        end

        def check_mocking(node)
          return unless mocking_method?(node)

          add_offense(node, message: format(MSG_MOCKING, method: node.method_name))
        end

        def bypass_method?(node)
          bypass_methods = %i[
            send __send__ instance_variable_get instance_variable_set
            instance_eval const_get method
          ]
          bypass_methods.include?(node.method_name)
        end

        def mocking_method?(node)
          %i[expect_any_instance_of allow_any_instance_of stub_const].include?(node.method_name)
        end

        def full_const_name(node)
          names = []
          current = node

          while current
            break unless current.const_type?

            names.unshift(current.const_name)
            current = current.parent
          end

          names.join('::')
        end

        def allowed?(const_name)
          return true unless const_name.start_with?(namespace)
          return true if const_name == namespace

          in_allowed?(const_name)
        end

        def in_allowed?(const_name)
          allowed_constants.include?(const_name) ||
            allowed_patterns.any? { |pattern| const_name.match?(pattern) }
        end

        def allowed_constants
          @allowed_constants ||= Set.new(cop_config.fetch('AllowedConstants', []))
        end

        def allowed_patterns
          patterns = cop_config.fetch('AllowedConstantPatterns', [])
          @allowed_patterns ||= patterns.map { |p| Regexp.new(p) }
        end

        def namespace
          @namespace ||= cop_config.fetch('Namespace', 'OdataDuty')
        end
      end
    end
  end
end
