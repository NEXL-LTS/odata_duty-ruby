module OdataDuty
  class CreateComplexTypeHashWrapper
    def initialize(hash, complex_type, context)
      @hash = hash
      @complex_type = complex_type
      @context = context
    end

    def method_missing(method_name, *args)
      matching_prop = @complex_type.properties.find { |p| p.name.to_sym == method_name.to_sym }
      if matching_prop && args.empty?
        __load(matching_prop, method_name, @hash[method_name.to_s])
      else
        super
      end
    rescue NoMethodError
      raise NoSuchPropertyError, "No such property '#{method_name}'"
    end

    def respond_to_missing?(method_name, _include_private = false)
      @complex_type.properties.any? { |p| p.name.to_sym == method_name.to_sym } || super
    end

    private

    def __load(matching_prop, method_name, value)
      return nil if value.nil?
      return matching_prop.to_value(value, @context) if matching_prop.scalar?

      if matching_prop.collection?
        value.map { |v| CreateComplexTypeHashWrapper.new(v, matching_prop.raw_type, @context) }
      else
        CreateComplexTypeHashWrapper.new(value, matching_prop.raw_type, @context)
      end
    rescue InvalidValue
      raise InvalidType, "The value provided for '#{method_name}' is of wrong type"
    end
  end
end
