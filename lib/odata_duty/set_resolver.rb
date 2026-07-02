module OdataDuty
  class SetResolver
    attr_reader :context

    def initialize(context:, init_args:)
      @context = context
      return unless respond_to?(:od_after_init)

      begin
        call_od_after_init(init_args)
      rescue StandardError => e
        insert_at = e.is_a?(InitArgsMismatchError) ? 1 : 2
        # :nocov: builder entity_set always defines _defined_at_; guard is defensive
        if entity_set.respond_to?(:_defined_at_)
          e.backtrace.insert(insert_at, entity_set._defined_at_)
        end
        # :nocov:
        raise e
      end
    end

    def od_next_link_skiptoken(token = nil)
      @od_next_link_skiptoken = token.to_s if token
      @od_next_link_skiptoken
    end

    private

    def call_od_after_init(init_args)
      if init_args == :_od_none_
        od_after_init
      elsif od_init_args_type == :keyword
        od_after_init(**init_args)
      else
        od_after_init(*Array(init_args))
      end
    rescue ArgumentError => e
      handle_init_args_error(e)
    end

    def handle_init_args_error(arg_error)
      raise arg_error unless arg_error.backtrace[0].include?("od_after_init'")

      err = InitArgsMismatchError.new(arg_error.message)
      err.set_backtrace(arg_error.backtrace.clone)

      raise err
    end

    def od_init_args_type
      @od_init_args_type ||=
        if od_after_init_parameters.any? { |type| %i[key keyreq keyrest].include?(type) }
          :keyword
        elsif od_after_init_parameters.any? { |type| %i[req opt rest].include?(type) }
          :positional
        else
          :none
        end
    end

    def od_after_init_parameters
      @od_after_init_parameters ||= method(:od_after_init).parameters.map(&:first)
    end

    def entity_set
      context.endpoint.entity_set
    end
  end
end
