require 'odata_duty/edms'

module OdataDuty
  class Property
    attr_reader :name, :nullable, :calling_method, :line__defined__at

    def initialize(name, type = String, line__defined__at: nil, nullable: true, method: nil)
      @line__defined__at = line__defined__at
      @name = name.to_str.to_sym
      @calling_method = method.respond_to?(:call) ? method : method&.to_sym || @name
      @collection = type.is_a?(Array)
      type = Array(type).first
      @type = TYPES_MAPPING[type] || type
      raise "Invalid type #{type.inspect} for #{name}" unless @type

      @nullable = nullable ? true : false
    end

    def raw_type
      return @type unless @type.respond_to?(:__metadata)

      @type.__metadata
    end

    def type
      return raw_type.property_type if raw_type.respond_to?(:property_type)

      raw_type.name
    end

    def collection?
      @collection
    end

    def value_from_object(obj, context)
      if calling_method.is_a?(Symbol)
        to_value(obj.public_send(calling_method), context)
      else
        to_value(calling_method.call(obj), context)
      end
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

      if collection?
        raise InvalidValue, "Invalid value #{value} for #{name}" unless value.is_a?(Array)

        value.map { |v| @type.to_value(v, context) }
      else
        @type.to_value(value, context)
      end
    end

    def filter_convert(value, context)
      convert(value, context)
    rescue OdataDuty::InvalidValue
      raise InvalidFilterValue, "Invalid value #{value} for #{name}"
    end

    def to_oas2
      result =
        if raw_type.scalar?
          raw_type.to_oas2(is_collection: collection?)
        else
          collection? ? { 'type' => 'array', 'items' => ref_oas2 } : ref_oas2
        end
      nullable ? result.merge('x-nullable' => true) : result
    end

    private

    def ref_oas2
      { '$ref' => "#/definitions/#{raw_type.name}" }
    end
  end
end
