module OdataDuty
  class Error < StandardError; end

  class PropertyAlreadyDefinedError < ArgumentError; end
  class InvalidNCNamesError < ArgumentError; end
  class InitArgsMismatchError < ArgumentError; end

  class RequestError < Error
    attr_reader :code, :target

    def initialize(message = 'Request Error', code: nil, target: nil)
      super(message)
      @code = code
      @target = target
    end

    def status
      :internal_server_error
    end
  end

  class ServerError < RequestError; end

  class NoImplementationError < ServerError
    def status
      :not_implemented
    end
  end

  class NotYetSupportedError < NoImplementationError; end
  class InvalidValue < ServerError; end

  class ClientError < RequestError
    def status
      :bad_request
    end
  end

  class ResourceNotFoundError < ClientError
    def status
      :not_found
    end
  end

  class UnknownPropertyError < ClientError; end
  class UnknownCollectionError < ClientError; end
  class InvalidFilterValue < ClientError; end
  class InvalidPropertyReferenceValue < ClientError; end
  class InvalidType < ClientError; end
  class NoSuchPropertyError < ClientError; end
  class InvalidQueryOptionError < ClientError; end
end
