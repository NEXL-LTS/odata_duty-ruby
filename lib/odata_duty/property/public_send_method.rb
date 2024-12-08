module OdataDuty
  module Property
    class PublicSendMethod
      def initialize(method)
        @method = method.to_sym
      end

      def call(obj)
        obj.public_send(@method)
      end
    end
  end
end
