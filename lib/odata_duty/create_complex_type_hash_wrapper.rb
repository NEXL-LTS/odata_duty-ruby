module OdataDuty
  class CreateComplexTypeHashWrapper
    SETTABLE_BY_OPERATION = { create: :settable_on_create?, update: :settable_on_update? }.freeze

    def initialize(hash, complex_type, operation:, context:)
      @hash = hash
      @complex_type = complex_type
      @operation = operation
      @context = context
    end

    def method_missing(method_name, *args)
      matching_prop = @complex_type.properties.find { |p| p.name == method_name }
      unless matching_prop && args.empty?
        raise NoSuchPropertyError, "No such property '#{method_name}'"
      end

      __load(matching_prop, method_name, @hash[method_name.to_s])
    end

    def respond_to_missing?(method_name, _include_private)
      @complex_type.properties.any? { |p| p.name == method_name }
    end

    private

    def __load(matching_prop, method_name, value)
      return nil unless settable?(matching_prop)
      return nil if value.nil?
      return matching_prop.to_value(value, @context) if matching_prop.scalar?

      if matching_prop.collection?
        value.map { |v| __wrap(v, matching_prop.raw_type) }
      else
        __wrap(value, matching_prop.raw_type)
      end
    rescue InvalidValue => e
      raise InvalidType, "The value provided for '#{method_name}' is of wrong type: #{e}"
    end

    def settable?(prop)
      prop.public_send(SETTABLE_BY_OPERATION.fetch(@operation))
    end

    def __wrap(value, raw_type)
      CreateComplexTypeHashWrapper.new(value, raw_type, operation: @operation, context: @context)
    end
  end
end
