module OdataDuty
  # Generated verb text shared between MCP tool descriptions (McpServerBuilder) and the `$oas2`
  # operation `summary` (oas2/*_path.rb), keyed by operation, so the two contracts can't drift.
  module OperationVerbs
    extend self

    def list(name) = "List #{name} records"
    def count(name) = "Count #{name} records"
    def create(name) = "Create a new #{name} record"
    def get(name) = "Get a single #{name} record by ID"
    def update(name) = "Update an existing #{name} record"
    def delete(name) = "Delete an existing #{name} record"
  end
end
