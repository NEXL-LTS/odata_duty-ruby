require 'securerandom'

module OdataDuty
  class MapperBuilder
    def self.build(complex_type, &block)
      mapper_class = build_class(complex_type)
      mapper_class.new(complex_type.properties, &block)
    end

    def self.build_class(complex_type)
      @dynamic_classes ||= {}
      @dynamic_classes[complex_type] ||= eval_erb_class(complex_type)
    end

    require 'erb'
    ERB_TEMPLATE = ERB.new(File.read("#{__dir__}/dynamic_object_wrapper.rb.erb"), trim_mode: '<>')
    ERB_TEMPLATE.location = ["#{__dir__}/dynamic_object_wrapper.rb.erb", 1]
    ERB_TEMPLATE.freeze

    def self.eval_erb_class(complex_type)
      class_result = ERB_TEMPLATE.result(binding)

      # puts class_result
      eval(class_result) # rubocop:disable Security/Eval
    end

    attr_accessor :obj
    attr_reader :complex_types, :calling_methods, :mappers

    def initialize(props, &block)
      @complex_types = props.reject(&:scalar?).to_h { |cp| [cp.name, cp.set_type] }
      @calling_methods = props.select(&:calling_method?).to_h { |cp| [cp.name, cp.calling_method] }
      @block = block
      initialize_mappers
    end

    def obj_to_hash(obj)
      self.obj = obj
      base_hash = to_h
      @block.call(base_hash, obj)
      base_hash
    end

    def obj_to_base_hash(obj)
      return nil if obj.nil?

      self.obj = obj
      to_h
    end

    VALID_BOOLEAN_VALUES = [true, false, nil].freeze

    def confirm_boolean(name, value)
      case value
      when true, false, nil
        value
      else
        raise InvalidValue, "Property #{name} must be a boolean and not #{value}"
      end
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
