module OdataDuty
  module SchemaBuilder
    class DataType
      attr_reader :name, :_defined_at_

      def initialize(name:)
        @name = name.to_str.clone.freeze
        @_defined_at_ = caller.find { |line| !line.include?('/lib/odata_duty/') }

        return if Property.valid_name?(@name)

        raise InvalidNCNamesError, "\"#{@name}\" is not a valid property name"
      end

      def scalar?
        false
      end
    end
  end
end
