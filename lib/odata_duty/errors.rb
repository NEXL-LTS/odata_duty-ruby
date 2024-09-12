module OdataDuty
  class Error < StandardError; end

  class PropertyAlreadyDefinedError < ArgumentError; end

  class ServerError < Error; end
  class NoImplementationError < ServerError; end
  class InvalidValue < ServerError; end

  class ClientError < Error; end

  class ResourceNotFoundError < ClientError; end
  class UnknownPropertyError < ClientError; end
  class UnknownCollectionError < ClientError; end
  class InvalidFilterValue < ClientError; end
  class InvalidPropertyReferenceValue < ClientError; end
  class InvalidType < ClientError; end
  class NoSuchPropertyError < ClientError; end
end
