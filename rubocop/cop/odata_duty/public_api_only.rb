module RuboCop
  module Cop
    module OdataDuty
      # Flags specs that reach past the gem's documented public API.
      class PublicApiOnly < RuboCop::Cop::Base
        CONST_MSG = '`%<name>s` is not part of the public API. ' \
                    'Specs must exercise the gem through its documented surface.'.freeze
        INTERNAL_MSG = '`%<name>s` is an internal method (`__` prefix). ' \
                       'Specs must exercise the gem through its documented surface.'.freeze
        BYPASS_MSG = '`%<name>s` bypasses method visibility. ' \
                     'Specs must exercise the gem through its documented surface.'.freeze
        MOCK_MSG = '`%<name>s` mocks gem behaviour. ' \
                   "Specs must assert on the gem's output instead.".freeze

        BYPASS_METHODS = %i[
          send __send__ instance_variable_get instance_variable_set
          instance_eval const_get method
        ].to_set.freeze
        MOCK_METHODS = %i[expect_any_instance_of allow_any_instance_of stub_const].to_set.freeze

        def on_const(node)
          return if node.parent&.const_type?

          name = const_path(node)
          return unless name.start_with?("#{namespace}::")
          return if allowed_constant?(name)

          add_offense(node, message: format(CONST_MSG, name: name))
        end

        def on_send(node)
          method_name = node.method_name
          message = send_message(method_name)
          return unless message

          add_offense(node.loc.selector, message: format(message, name: method_name))
        end
        alias on_csend on_send

        private

        def send_message(method_name)
          return BYPASS_MSG if BYPASS_METHODS.include?(method_name)
          return INTERNAL_MSG if method_name.start_with?('__')

          MOCK_MSG if MOCK_METHODS.include?(method_name)
        end

        def const_path(node)
          namespace_node = node.children.first
          prefix = namespace_node ? "#{const_path(namespace_node)}::" : ''
          "#{prefix}#{node.children.last}"
        end

        def namespace
          @namespace ||= cop_config.fetch('Namespace', 'OdataDuty')
        end

        def allowed_constant?(name)
          allowed_constants.include?(name) ||
            allowed_constant_patterns.any? { |pattern| pattern.match?(name) }
        end

        def allowed_constants
          @allowed_constants ||= (cop_config['AllowedConstants'] || []).to_set
        end

        def allowed_constant_patterns
          @allowed_constant_patterns ||=
            (cop_config['AllowedConstantPatterns'] || []).map { |pattern| Regexp.new(pattern) }
        end
      end
    end
  end
end
