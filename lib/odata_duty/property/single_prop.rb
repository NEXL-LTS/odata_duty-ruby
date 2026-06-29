module OdataDuty
  module Property
    CORE_ANNOTATION_TERMS = { computed: 'Org.OData.Core.V1.Computed',
                              immutable: 'Org.OData.Core.V1.Immutable' }.freeze

    class SingleProp
      attr_reader :name, :nullable, :calling_method, :line__defined__at, :raw_type, :type,
                  :set_type, :method_name, :mutability

      def initialize(name, type = String, line__defined__at: nil, nullable: true, method: nil,
                     mutability: :read_write)
        @line__defined__at = line__defined__at
        @name = name.to_str.to_sym
        @calling_method = method.respond_to?(:call) ? method : nil
        method = nil if method.respond_to?(:call)
        @method_name = (method || name).to_sym
        @nullable = nullable ? true : false
        @mutability = mutability
        load_type_instance_vars(type)
      end

      def computed?
        mutability == :computed
      end

      def immutable?
        mutability == :immutable
      end

      def non_insertable?
        mutability == :non_insertable
      end

      def core_annotation_term
        CORE_ANNOTATION_TERMS[mutability]
      end

      def settable_on_create?
        !computed? && !non_insertable?
      end

      def settable_on_update?
        !computed? && !immutable?
      end

      def calling_method?
        !!calling_method
      end

      def nullable?
        nullable
      end

      def boolean?
        raw_type == EdmBool
      end

      def string?
        raw_type == EdmString
      end

      def int?
        raw_type == EdmInt64
      end

      def date?
        raw_type == EdmDate
      end

      def datetime?
        raw_type == EdmDateTimeOffset
      end

      def enum?
        raw_type.respond_to?(:members)
      end

      def enum_members
        raw_type.members
      end

      def scalar?
        raw_type.scalar?
      end

      def to_value(value, context)
        convert(value, context).tap do |result|
          raise "#{name} cannot be null" if !nullable && result.nil?
        end
      rescue InvalidValue => e
        raise InvalidValue, "#{name} : #{e.message}"
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
        to_oas2_type.dup.tap do |oas2|
          oas2.merge!('readOnly' => true) if computed?
          oas2.merge!('x-nullable' => true) if nullable
        end
      end

      def to_oas2_type
        return raw_type.to_oas2(is_collection: false) if scalar? && !enum?

        { '$ref' => "#/definitions/#{raw_type.name}" }
      end

      def collection?
        false
      end

      private

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
