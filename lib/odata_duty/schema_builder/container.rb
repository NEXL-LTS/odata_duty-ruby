module OdataDuty
  module SchemaBuilder
    class Container
      attr_reader :name

      def initialize(name:)
        @name = name.to_str.clone.freeze
      end
    end
  end
end
