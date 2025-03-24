require 'odata_duty/edms'
require 'odata_duty/property/single_prop'
require 'odata_duty/property/collection_prop'

module OdataDuty
  module Property
    def self.new(name, type = String, line__defined__at: nil, nullable: true, method: nil)
      unless valid_name?(name)
        raise InvalidNCNamesError, "\"#{name}\" is not a valid property name"
      end

      prop_class = type.is_a?(Array) ? CollectionProp : SingleProp
      prop_class.new(name, type,
                     line__defined__at: line__defined__at,
                     nullable: nullable,
                     method: method)
    end

    def self.valid_name?(name)
      name.to_s.match?(/\A(?:\p{L}|_)(?:[\p{L}\p{Nd}_])*\z/)
    end
  end
end
