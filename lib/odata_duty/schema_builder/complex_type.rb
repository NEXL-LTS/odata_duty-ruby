require_relative 'data_type'

module OdataDuty
  module SchemaBuilder
    class ComplexType < DataType
      attr_reader :properties

      def initialize(**kwargs)
        super
        @properties = []
      end

      def property(*args, line__defined__at: caller[0], **kwargs)
        Property.new(*args, line__defined__at: line__defined__at, **kwargs).tap do |property|
          properties << property
        end
      end

      def to_value(val, context)
        properties.each_with_object({}) do |property, obj|
          obj[property.name] = property.value_from_object(val, context)
        rescue StandardError => e
          if e.backtrace && property.line__defined__at
            index = e.backtrace.find_index { |l| l.include?('lib/odata_duty') }
            e.backtrace.insert(index, property.line__defined__at) if index
          end
          raise e
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
