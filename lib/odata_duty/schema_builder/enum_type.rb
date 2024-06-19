require_relative 'data_type'

module OdataDuty
  module SchemaBuilder
    class EnumType < DataType
      attr_reader :members

      def initialize(**kwargs)
        super
        @members = []
      end

      def member(*args)
        @members << EnumMember.new(*args)
      end

      def to_value(val, _context)
        return val if val.nil? || members.map(&:name).include?(val)

        raise InvalidValue, "#{val} is not a valid member of #{members}"
      end

      def to_oas2
        { 'type' => 'string', 'enum' => members.map(&:name) }
      end
    end
  end
end
