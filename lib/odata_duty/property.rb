require 'odata_duty/edms'
require 'odata_duty/property/single_prop'
require 'odata_duty/property/collection_prop'

module OdataDuty
  module Property
    MUTABILITIES = %i[read_write immutable non_insertable computed].freeze
    MUTABILITIES_LIST = MUTABILITIES.map(&:inspect).join(', ').freeze

    def self.new(name, type = String, line__defined__at: nil, nullable: true, method: nil,
                 computed: :unset, mutability: :unset)
      unless valid_name?(name)
        raise InvalidNCNamesError, "\"#{name}\" is not a valid property name"
      end

      prop_class = type.instance_of?(Array) ? CollectionProp : SingleProp
      prop_class.new(name, type,
                     line__defined__at: line__defined__at,
                     nullable: nullable,
                     method: method,
                     mutability: resolve_mutability(name, computed, mutability))
    end

    def self.resolve_mutability(name, computed, mutability)
      mutability = computed_to_mutability(name, computed, mutability) unless computed == :unset
      mutability = :read_write if mutability == :unset
      return mutability if MUTABILITIES.include?(mutability)

      raise ArgumentError,
            "#{name}: invalid mutability #{mutability.inspect}, " \
            "must be one of #{MUTABILITIES_LIST}"
    end

    def self.computed_to_mutability(name, computed, mutability)
      unless mutability == :unset
        raise ArgumentError,
              "#{name}: pass either `mutability:` or `computed:`, not both \u2014 they control " \
              'the same axis'
      end
      computed ? :computed : :read_write
    end

    NAME_REGEXP = Regexp.new('\A(?:\p{L}|_)(?:[\p{L}\p{Nd}_])*\z').freeze

    def self.valid_name?(name)
      name.match?(NAME_REGEXP)
    end
  end
end
