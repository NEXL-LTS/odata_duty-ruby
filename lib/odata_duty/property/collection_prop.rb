require_relative 'single_prop'

module OdataDuty
  module Property
    class CollectionProp < SingleProp
      def convert(value, context)
        value&.map { |v| super(v, context) }
      rescue NoMethodError
        raise InvalidValue, "#{value} is not an collection"
      end

      def to_oas2_type
        if scalar?
          raw_type.to_oas2(is_collection: true)
        else
          { 'type' => 'array', 'items' => ref_oas2 }
        end
      end

      def collection?
        true
      end
    end
  end
end
