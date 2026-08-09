module RuboCop
  module Cop
    module OdataDuty
      # Enforces that specs exercise the gem only through its public API.
      class PublicApiOnly < RuboCop::Cop::Base
        CONSTANT_MSG = '`%<name>s` is not part of the public API. Specs must exercise the gem ' \
                       'through its documented surface.'.freeze
        INTERNAL_MSG = '`%<name>s` is an internal method (`__` prefix). Specs must exercise the ' \
                       'gem through its documented surface.'.freeze
        BYPASS_MSG = '`%<name>s` bypasses method visibility. Specs must exercise the gem ' \
                     'through its documented surface.'.freeze
        MOCK_MSG =
          "`%<name>s` mocks gem behaviour. Specs must assert on the gem's output instead.".freeze

        BYPASS_METHODS = %i[
          send __send__ instance_variable_get instance_variable_set instance_eval const_get method
        ].to_set.freeze
        MOCK_METHODS = %i[expect_any_instance_of allow_any_instance_of stub_const].to_set.freeze
        RUBY_BUILTINS = %i[__dir__ __method__ __callee__ __id__].to_set.freeze
        private_constant :CONSTANT_MSG, :INTERNAL_MSG, :BYPASS_MSG, :MOCK_MSG,
                         :BYPASS_METHODS, :MOCK_METHODS, :RUBY_BUILTINS

        def on_const(node)
          return if node.parent&.const_type?

          name = node.source
          return unless name.start_with?("#{namespace}::")
          return if allowed_constant?(name)

          add_offense(node, message: format(CONSTANT_MSG, name: name))
        end

        def on_send(node)
          method_name = node.method_name
          return add_offense(node.loc.selector, message: bypass_or_mock_message(method_name)) \
            if BYPASS_METHODS.include?(method_name) || MOCK_METHODS.include?(method_name)

          return unless internal_method?(method_name)

          add_offense(node.loc.selector, message: format(INTERNAL_MSG, name: method_name))
        end
        alias on_csend on_send

        private

        def internal_method?(method_name)
          method_name.start_with?('__') && !RUBY_BUILTINS.include?(method_name)
        end

        def bypass_or_mock_message(method_name)
          template = MOCK_METHODS.include?(method_name) ? MOCK_MSG : BYPASS_MSG
          format(template, name: method_name)
        end

        def namespace
          cop_config.fetch('Namespace', 'OdataDuty')
        end

        def allowed_constant?(name)
          allowed_constants.include?(name) || allowed_patterns.any? { |p| p.match?(name) }
        end

        def allowed_constants
          @allowed_constants ||= Set.new(cop_config.fetch('AllowedConstants', []))
        end

        def allowed_patterns
          @allowed_patterns ||=
            cop_config.fetch('AllowedConstantPatterns', []).map { |p| Regexp.new(p) }
        end
      end
    end
  end
end
