require 'spec_helper'

class InvalidMcpIdNonAsciiPropertyType < OdataDuty::EntityType
  property_ref :id, Integer
  property :日本語, String
end

class InvalidMcpIdNonAsciiPropertySet < OdataDuty::EntitySet
  entity_type InvalidMcpIdNonAsciiPropertyType
  name 'People'
  url 'People'

  def create(params)
    params
  end
end

class InvalidMcpIdNonAsciiPropertySchema < OdataDuty::Schema
  base_url 'http://localhost:3000/api'
  entity_sets [InvalidMcpIdNonAsciiPropertySet]
end

LONG_MCP_PROPERTY_NAME = "n#{'a' * 64}".freeze

class InvalidMcpIdLongPropertyType < OdataDuty::EntityType
  property_ref :id, Integer
  property LONG_MCP_PROPERTY_NAME.to_sym, String
end

class InvalidMcpIdLongPropertySet < OdataDuty::EntitySet
  entity_type InvalidMcpIdLongPropertyType
  name 'People'
  url 'People'

  def create(params)
    params
  end
end

class InvalidMcpIdLongPropertySchema < OdataDuty::Schema
  base_url 'http://localhost:3000/api'
  entity_sets [InvalidMcpIdLongPropertySet]
end

LONG_MCP_ENTITY_SET_NAME = "ThisIsAnExtremelyLong#{'Set' * 20}".freeze

class InvalidMcpIdLongToolNameEntityType < OdataDuty::EntityType
  property_ref :id, Integer
end

class InvalidMcpIdLongToolNameSet < OdataDuty::EntitySet
  entity_type InvalidMcpIdLongToolNameEntityType
  name LONG_MCP_ENTITY_SET_NAME
  url LONG_MCP_ENTITY_SET_NAME

  def collection
    []
  end
end

class InvalidMcpIdLongToolNameSchema < OdataDuty::Schema
  base_url 'http://localhost:3000/api'
  entity_sets [InvalidMcpIdLongToolNameSet]
end

class InvalidMcpIdCollisionEntityType < OdataDuty::EntityType
  property_ref :odata_select, String
end

class InvalidMcpIdCollisionSet < OdataDuty::EntitySet
  entity_type InvalidMcpIdCollisionEntityType
  name 'People'
  url 'People'

  def individual(id)
    OpenStruct.new(odata_select: id)
  end
end

class InvalidMcpIdCollisionSchema < OdataDuty::Schema
  base_url 'http://localhost:3000/api'
  entity_sets [InvalidMcpIdCollisionSet]
end

class InvalidMcpIdNonAsciiKeyType < OdataDuty::EntityType
  property_ref :日本語, String
end

class InvalidMcpIdNonAsciiKeySet < OdataDuty::EntitySet
  entity_type InvalidMcpIdNonAsciiKeyType
  name 'People'
  url 'People'

  def individual(id)
    OpenStruct.new(日本語: id)
  end

  def update(id, _params)
    OpenStruct.new(日本語: id)
  end

  def delete(id)
    OpenStruct.new(日本語: id)
  end
end

class InvalidMcpIdNonAsciiKeySchema < OdataDuty::Schema
  base_url 'http://localhost:3000/api'
  entity_sets [InvalidMcpIdNonAsciiKeySet]
end

class InvalidMcpIdNonAsciiKeyUpdateOnlySet < OdataDuty::EntitySet
  entity_type InvalidMcpIdNonAsciiKeyType
  name 'People'
  url 'People'

  def update(id, _params)
    OpenStruct.new(日本語: id)
  end
end

class InvalidMcpIdNonAsciiKeyUpdateOnlySchema < OdataDuty::Schema
  base_url 'http://localhost:3000/api'
  entity_sets [InvalidMcpIdNonAsciiKeyUpdateOnlySet]
end

class InvalidMcpIdValidWidgetType < OdataDuty::EntityType
  property_ref :id, String
  property :name, String
end

class InvalidMcpIdValidSet < OdataDuty::EntitySet
  entity_type InvalidMcpIdValidWidgetType
  name 'Widgets'
  url 'Widgets'

  def collection
    []
  end

  def individual(id)
    OpenStruct.new(id: id, name: 'n')
  end

  def create(params)
    OpenStruct.new(id: 'new', name: params.name)
  end

  def update(id, params)
    OpenStruct.new(id: id, name: params.name)
  end

  def delete(id)
    OpenStruct.new(id: id, name: 'n')
  end
end

class InvalidMcpIdValidSchema < OdataDuty::Schema
  base_url 'http://localhost:3000/api'
  entity_sets [InvalidMcpIdValidSet]
end

RSpec.describe OdataDuty::Schema, 'to_mcp_server with an unsafe MCP identifier' do
  it 'raises InvalidMcpIdentifierError for a non-ASCII property name reaching a tool schema' do
    expect { InvalidMcpIdNonAsciiPropertySchema.to_mcp_server }.to raise_error(
      OdataDuty::InvalidMcpIdentifierError,
      'InvalidMcpIdNonAsciiPropertyType property "日本語" cannot be used as an MCP tool input ' \
      'key — it must match /\\A[a-zA-Z0-9_.-]{1,64}\\z/ (create_People)'
    )
  end

  it 'raises InvalidMcpIdentifierError for an over-64-character property name' do
    expect { InvalidMcpIdLongPropertySchema.to_mcp_server }.to raise_error(
      OdataDuty::InvalidMcpIdentifierError,
      "InvalidMcpIdLongPropertyType property \"#{LONG_MCP_PROPERTY_NAME}\" cannot be used as " \
      'an MCP tool input key — it must match /\A[a-zA-Z0-9_.-]{1,64}\z/ (create_People)'
    )
  end

  it 'raises InvalidMcpIdentifierError when an entity-set name pushes a tool name over 64' do
    tool_name = "list_#{LONG_MCP_ENTITY_SET_NAME}"

    expect { InvalidMcpIdLongToolNameSchema.to_mcp_server }.to raise_error(
      OdataDuty::InvalidMcpIdentifierError,
      "tool name \"#{tool_name}\" is #{tool_name.length} characters — MCP tool names must " \
      'match /\A[a-zA-Z0-9_-]{1,64}\z/'
    )
  end

  it 'raises InvalidMcpIdentifierError when a property is named like a reserved query key' do
    expect { InvalidMcpIdCollisionSchema.to_mcp_server }.to raise_error(
      OdataDuty::InvalidMcpIdentifierError,
      'InvalidMcpIdCollisionEntityType property "odata_select" collides with the reserved ' \
      'odata_select query-option key in the get_People tool input schema'
    )
  end

  it 'raises InvalidMcpIdentifierError for a non-ASCII key property reaching get_<Set>' do
    expect { InvalidMcpIdNonAsciiKeySchema.to_mcp_server }.to raise_error(
      OdataDuty::InvalidMcpIdentifierError,
      'InvalidMcpIdNonAsciiKeyType property "日本語" cannot be used as an MCP tool input ' \
      'key — it must match /\A[a-zA-Z0-9_.-]{1,64}\z/ (get_People)'
    )
  end

  it 'raises InvalidMcpIdentifierError for a non-ASCII key property reaching update_<Set>' do
    expect { InvalidMcpIdNonAsciiKeyUpdateOnlySchema.to_mcp_server }.to raise_error(
      OdataDuty::InvalidMcpIdentifierError,
      'InvalidMcpIdNonAsciiKeyType property "日本語" cannot be used as an MCP tool input ' \
      'key — it must match /\A[a-zA-Z0-9_.-]{1,64}\z/ (update_People)'
    )
  end

  it 'builds normally for an already-valid, typically-named schema' do
    expect { InvalidMcpIdValidSchema.to_mcp_server }.not_to raise_error
  end
end
