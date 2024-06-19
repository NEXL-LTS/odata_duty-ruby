require_relative 'data_type'

module OdataDuty
  module SchemaBuilder
    class ComplexType < DataType
      attr_reader :properties

      def initialize(**kwargs)
        super
        @properties = []
      end

      def property(*args, **kwargs)
        Property.new(*args, **kwargs).tap do |property|
          properties << property
        end
      end

      def to_value(val, context)
        properties.each_with_object({}) do |property, obj|
          obj[property.name] = property.to_value(val.public_send(property.name.to_sym), context)
        end
      end

      def to_oas2
        {
          'type' => 'object',
          'properties' => properties.each_with_object({}) do |property, obj|
            obj[property.name.to_s] = property.to_oas2
          end
        }
      end
    end
  end
end
