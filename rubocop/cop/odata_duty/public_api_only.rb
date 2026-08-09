module RuboCop
  module Cop
    module OdataDuty
      # Flags specs that reach past the gem's documented public API.
      #
      # See doc/prds/public-api-only-cop.md for the full contract.
      class PublicApiOnly < Base
        CONSTANT_MSG = '`%<name>s` is not part of the public API. ' \
                        'Specs must exercise the gem through its documented surface.'.freeze

        def on_const(node)
          return if node.parent&.const_type?

          name = node.const_name
          return unless internal_constant?(name)

          add_offense(node, message: format(CONSTANT_MSG, name: name))
        end

        private

        def internal_constant?(name)
          name.start_with?("#{namespace}::") &&
            !allowed_constants.include?(name) &&
            allowed_constant_patterns.none? { |pattern| pattern.match?(name) }
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
