require_relative 'data_type'
require_relative '../mapper_builder'

module OdataDuty
  module SchemaBuilder
    class ComplexType < DataType
      attr_reader :properties

      def initialize(**kwargs)
        super
        @properties = []
      end

      def property(name, *args, line__defined__at: caller[0], **kwargs)
        if properties.any? { |p| p.name == name.to_sym }
          raise PropertyAlreadyDefinedError, "#{name} is already defined"
        end

        Property.new(name, *args, line__defined__at: line__defined__at, **kwargs).tap do |property|
          properties << property
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
