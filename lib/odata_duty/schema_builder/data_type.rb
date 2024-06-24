module OdataDuty
  module SchemaBuilder
    class DataType
      attr_reader :name

      def initialize(name:)
        @name = name.to_str.clone.freeze
      end

      def scalar?
        false
      end
    end
  end
end
