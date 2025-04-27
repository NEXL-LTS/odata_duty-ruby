module OdataDuty
  class SetResolver
    attr_reader :context

    def initialize(context:, init_args:)
      @context = context
      if respond_to?(:od_after_init)
        begin
          if init_args == :_od_none_
            od_after_init
          else
            if od_init_args_type == :keyword
              od_after_init(**init_args)
            else
              od_after_init(*Array(init_args))
            end
          end
        rescue ArgumentError => e
          if e.backtrace[0].include?(':in `od_after_init')
            new_error = InitArgsMismatchError.new(e.message)
            new_error.set_backtrace(e.backtrace.clone)
            entity_set = context.endpoint.entity_set
            new_error.backtrace.insert(1, entity_set._defined_at_) if entity_set.respond_to?(:_defined_at_)
            raise new_error
          else
            raise e
          end
        end
      end
    end

    def od_next_link_skiptoken(token = nil)
      @od_next_link_skiptoken = token.to_s if token
      @od_next_link_skiptoken
    end

    private

    def od_init_args_type
      @od_init_args_type ||= 
        if od_after_init_parameters.any? { |type| [:key, :keyreq, :keyrest].include?(type) }
          :keyword
        elsif od_after_init_parameters.any? { |type| [:req, :opt, :rest].include?(type) }
          :positional
        else
          :none
        end
    end

    def od_after_init_parameters
      @od_after_init_parameters ||= method(:od_after_init).parameters.map(&:first)
    end
  end
end
