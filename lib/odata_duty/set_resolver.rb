module OdataDuty
  class SetResolver
    attr_reader :context

    def initialize(context:, init_args:)
      @context = context
      return unless respond_to?(:od_after_init)

      begin
        call_od_after_init(init_args)
      rescue InitArgsMismatchError => e
        e.backtrace.insert(1, entity_set._defined_at_)
        raise
      rescue StandardError => e
        e.backtrace.insert(2, entity_set._defined_at_)
        raise
      end
    end

    def od_next_link_skiptoken(token = nil)
      @od_next_link_skiptoken = token.to_s if token
      @od_next_link_skiptoken
    end

    private

    def call_od_after_init(init_args)
      case init_args
      when nil then od_after_init
      when Hash then od_after_init(**init_args)
      when Array then od_after_init(*init_args)
      else od_after_init(init_args)
      end
    rescue ArgumentError => e
      handle_init_args_error(e)
    end

    def handle_init_args_error(arg_error)
      raise unless arg_error.backtrace.first.include?("od_after_init'")

      err = InitArgsMismatchError.new(arg_error)
      err.set_backtrace(arg_error.backtrace)

      raise err
    end

    def entity_set
      context.endpoint.entity_set
    end
  end
end
