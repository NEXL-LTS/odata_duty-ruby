require_relative 'public_send_method'

module OdataDuty
  module Property
    class SingleProp
      attr_reader :name, :nullable, :calling_method, :line__defined__at, :raw_type, :type

      def initialize(name, type = String, line__defined__at: nil, nullable: true, method: nil)
        @line__defined__at = line__defined__at
        @name = name.to_str.to_sym
        @calling_method = if method.respond_to?(:call)
                            method
                          else
                            PublicSendMethod.new(method&.to_sym || @name)
                          end
        @nullable = nullable ? true : false

        load_type_instance_vars(type)
      end

      def scalar?
        raw_type.scalar?
      end

      def value_from_object(obj, context)
        to_value(calling_method.call(obj), context)
      end

      def to_value(value, context)
        raise "#{name} cannot be null" if !nullable && value.nil?

        begin
          result = convert(value, context)
        rescue InvalidValue => e
          raise InvalidValue, "#{name} : #{e.message}"
        end

        raise "#{name} cannot be null" if !nullable && result.nil?

        result
      end

      def convert(value, context)
        return value if value.nil?

        @set_type.to_value(value, context)
      end

      def filter_convert(value, context)
        convert(value, context)
      rescue OdataDuty::InvalidValue
        raise InvalidFilterValue, "Invalid value #{value} for #{name}"
      end

      def to_oas2
        nullable ? to_oas2_type.merge('x-nullable' => true) : to_oas2_type
      end

      def to_oas2_type
        if scalar?
          raw_type.to_oas2(is_collection: false)
        else
          ref_oas2
        end
      end

      def build_odata_id(context, id)
        context.current['odata_url_base'] ||= context.url_for(url: context.endpoint.url)
        "#{context.current['odata_url_base']}(#{raw_type.url_id(id)})"
      end

      def collection?
        false
      end

      private

      def ref_oas2
        { '$ref' => "#/definitions/#{raw_type.name}" }
      end

      def load_type_instance_vars(type)
        type = Array(type).first
        @set_type = TYPES_MAPPING[type] || type
        raise "Invalid type #{type.inspect} for #{name}" unless @set_type

        @raw_type = @set_type.respond_to?(:__metadata) ? @set_type.__metadata : @set_type
        @type = @raw_type.respond_to?(:property_type) ? @raw_type.property_type : @raw_type.name
      end
    end
  end
end
