require 'securerandom'

module OdataDuty
  class MapperBuilder
    def self.build(complex_type, val, &block)
      mapper_class = build_class(complex_type, val)
      mapper_class.new(val, complex_type.properties, &block)
    end

    def self.build_class(complex_type, val)
      @dynamic_classes ||= {}
      @dynamic_classes[[val.class, complex_type]] ||= eval_erb_class(complex_type, val)
    end

    require 'erb'
    ERB_TEMPLATE = ERB.new(File.read("#{__dir__}/dynamic_object_wrapper.rb.erb"), trim_mode: '<>')
    ERB_TEMPLATE.location = ["#{__dir__}/dynamic_object_wrapper.rb.erb", 1]
    ERB_TEMPLATE.freeze

    def self.eval_erb_class(complex_type, val)
      base_name = [complex_type.name, val.class.to_s.gsub('::', '')].uniq.join('For')
      klass_name = "#{base_name}#{SecureRandom.hex(2)}"

      class_result = ERB_TEMPLATE.result(binding)

      eval(class_result) # rubocop:disable Security/Eval

      const_get(klass_name)
    end

    attr_accessor :obj
    attr_reader :complex_types, :calling_methods, :mappers

    def initialize(obj, props, &block)
      @obj = obj
      @complex_types = props.reject(&:scalar?).to_h { |cp| [cp.name, cp.set_type] }
      @calling_methods = props.select(&:calling_method?).to_h { |cp| [cp.name, cp.calling_method] }
      @block = block
      @mappers = {}
    end

    def obj_to_hash(obj)
      self.obj = obj
      to_h.tap { |h| @block&.call(h, obj) }
    end

    VALID_BOOLEAN_VALUES = [true, false].freeze

    def confirm_boolean(name, value)
      return value if VALID_BOOLEAN_VALUES.include?(value)

      raise InvalidValue, "Property #{name} must be a boolean and not #{value}"
    end

    def not_nullable(name, value)
      raise InvalidValue, "Property #{name} cannot be null" if value.nil?

      value
    end

    def confirm_one_of(name, value, valid_values)
      return value if valid_values.include?(value)

      raise InvalidValue, "Property #{name} must be one of #{valid_values} and not #{value}"
    end
  end
end
