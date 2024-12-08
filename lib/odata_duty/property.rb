require 'odata_duty/edms'
require 'odata_duty/property/single_prop'
require 'odata_duty/property/collection_prop'

module OdataDuty
  module Property
    def self.new(name, type = String, line__defined__at: nil, nullable: true, method: nil)
      prop_class = if type.is_a?(Array)
                     CollectionProp
                   else
                     SingleProp
                   end
      prop_class.new(name, type,
                     line__defined__at: line__defined__at,
                     nullable: nullable,
                     method: method)
    end
  end
end
