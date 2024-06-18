module OdataDuty
  class Error < StandardError; end

  class ServerError < Error; end

  class InvalidValue < ServerError; end

  class ClientError < Error; end

  class ResourceNotFoundError < ClientError; end
  class NoImplementionError < ClientError; end
  class UnknownPropertyError < ClientError; end
  class UnknownCollectionError < ClientError; end
  class InvalidFilterValue < ClientError; end
  class InvalidPropertyReferenceValue < ClientError; end
end
