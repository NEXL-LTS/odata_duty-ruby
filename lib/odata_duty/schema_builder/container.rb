module OdataDuty
  module SchemaBuilder
    class Container
      attr_reader :name, :_defined_at_

      def initialize(name:)
        @name = name.to_str.clone.freeze
        @_defined_at_ = caller.find { |line| !line.include?('/lib/odata_duty/') }

        return if Property.valid_name?(@name)

        raise InvalidNCNamesError, "\"#{@name}\" is not a valid property name"
      end
    end
  end
end
