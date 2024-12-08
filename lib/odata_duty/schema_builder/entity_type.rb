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

      def prop_ref
        property_refs.first
      end

      def to_value(val, context)
        result = super
        result['@odata.id'] = prop_ref.build_odata_id(context, val.id)
        result
      end

      def integer_property_ref?
        @property_ref_raw_type ||= property_refs.first.raw_type
        @property_ref_raw_type == EdmInt64
      end
    end
  end
end
