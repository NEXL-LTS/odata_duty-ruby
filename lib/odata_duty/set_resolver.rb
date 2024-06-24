module OdataDuty
  class SetResolver
    attr_reader :context

    def initialize(context:)
      @context = context
      od_after_init if respond_to?(:od_after_init)
    end

    def od_next_link_skiptoken(token = nil)
      @od_next_link_skiptoken = token.to_s if token
      @od_next_link_skiptoken
    end
  end
end
