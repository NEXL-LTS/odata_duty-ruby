module OdataDuty
  module SchemaBuilder
    class DataType
      attr_reader :name, :_defined_at_, :description

      def initialize(name:, description: nil)
        @name = name.clone
        @_defined_at_ = caller.find { |line| !line.include?('/lib/odata_duty/') }

        raise InvalidNCNamesError, "\"#{@name}\" is not a valid property name" unless
          Property.valid_name?(@name)

        @description = Property.resolve_description(@name, description)
      end

      def scalar?; end
    end
  end
end
