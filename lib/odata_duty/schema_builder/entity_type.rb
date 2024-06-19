require_relative 'complex_type'

module OdataDuty
  module SchemaBuilder
    class EntityType < ComplexType
      attr_reader :property_refs

      def initialize(**kwargs)
        super
        @property_refs = []
      end

      def property_ref(*args)
        property(*args, nullable: false).tap do |property|
          raise 'Multiple Property Reference not yet suported' if property_refs.size.positive?

          property_refs << property
        end
      end

      def to_value(val, context)
        odata_id = integer_property_ref? ? val.id : "'#{val.id}'"
        super.merge(
          '@odata.id': context.url_for(url: "#{context.endpoint.url}(#{odata_id})")
        )
      end

      def integer_property_ref?
        property_refs.first.raw_type == EdmInt64
      end
    end
  end
end
