require 'spec_helper'

class InvalidMcpIdBuilderResolver < OdataDuty::SetResolver
  def od_after_init
    @records = [OpenStruct.new(id: '1')]
  end

  def collection
    @records
  end

  def individual(id)
    @records.find { |r| r.id == id }
  end

  def create(params)
    params
  end
end

module OdataDuty
  RSpec.describe SchemaBuilder::EntitySet, 'to_mcp_server with an unsafe MCP identifier' do
    def schema_with_property(name:, property_name:)
      SchemaBuilder.build(namespace: 'SampleSpace', host: 'localhost', base_path: '') do |s|
        entity = s.add_entity_type(name: name) do |et|
          et.property_ref 'id', String
          et.property property_name, String
        end
        s.add_entity_set(name: 'People', entity_type: entity,
                         resolver: 'InvalidMcpIdBuilderResolver')
      end
    end

    it 'raises InvalidMcpIdentifierError for a non-ASCII property name reaching a tool schema' do
      schema = schema_with_property(name: 'NonAsciiPropertyEntity', property_name: '日本語')

      expect { schema.to_mcp_server }.to raise_error(
        OdataDuty::InvalidMcpIdentifierError,
        'NonAsciiPropertyEntity property "日本語" cannot be used as an MCP tool input key — ' \
        'it must match /\\A[a-zA-Z0-9_.-]{1,64}\\z/ (create_People)'
      )
    end

    it 'raises for a later invalid property even when an earlier one is valid' do
      schema = SchemaBuilder.build(namespace: 'SampleSpace', host: 'localhost',
                                   base_path: '') do |s|
        entity = s.add_entity_type(name: 'SecondPropertyEntity') do |et|
          et.property_ref 'id', String
          et.property 'ok', String
          et.property '日本語', String
        end
        s.add_entity_set(name: 'People', entity_type: entity,
                         resolver: 'InvalidMcpIdBuilderResolver')
      end

      expect { schema.to_mcp_server }.to raise_error(
        OdataDuty::InvalidMcpIdentifierError,
        'SecondPropertyEntity property "日本語" cannot be used as an MCP tool input key — ' \
        'it must match /\A[a-zA-Z0-9_.-]{1,64}\z/ (create_People)'
      )
    end

    it 'raises InvalidMcpIdentifierError for an over-64-character property name' do
      long_name = "n#{'a' * 64}"
      schema = schema_with_property(name: 'LongPropertyEntity', property_name: long_name)

      expect { schema.to_mcp_server }.to raise_error(
        OdataDuty::InvalidMcpIdentifierError,
        "LongPropertyEntity property \"#{long_name}\" cannot be used as an MCP tool input " \
        'key — it must match /\A[a-zA-Z0-9_.-]{1,64}\z/ (create_People)'
      )
    end

    it 'raises InvalidMcpIdentifierError when an entity-set name pushes a tool name over 64' do
      long_set_name = "ThisIsAnExtremelyLong#{'Set' * 20}"
      tool_name = "list_#{long_set_name}"
      schema = SchemaBuilder.build(namespace: 'SampleSpace', host: 'localhost',
                                   base_path: '') do |s|
        entity = s.add_entity_type(name: 'LongToolNameEntity') do |et|
          et.property_ref 'id', String
        end
        s.add_entity_set(name: long_set_name, entity_type: entity,
                         resolver: 'InvalidMcpIdBuilderResolver')
      end

      expect { schema.to_mcp_server }.to raise_error(
        OdataDuty::InvalidMcpIdentifierError,
        "tool name \"#{tool_name}\" is #{tool_name.length} characters — MCP tool names must " \
        'match /\A[a-zA-Z0-9_-]{1,64}\z/'
      )
    end

    it 'raises InvalidMcpIdentifierError when a property is named like a reserved query key' do
      schema = SchemaBuilder.build(namespace: 'SampleSpace', host: 'localhost',
                                   base_path: '') do |s|
        entity = s.add_entity_type(name: 'CollisionEntity') do |et|
          et.property_ref 'odata_select', String
        end
        s.add_entity_set(name: 'People', entity_type: entity,
                         resolver: 'InvalidMcpIdBuilderResolver')
      end

      expect { schema.to_mcp_server }.to raise_error(
        OdataDuty::InvalidMcpIdentifierError,
        'CollisionEntity property "odata_select" collides with the reserved odata_select ' \
        'query-option key in the get_People tool input schema'
      )
    end

    it 'builds normally for an already-valid, typically-named schema' do
      schema = schema_with_property(name: 'ValidWidgetEntity', property_name: 'name')

      expect { schema.to_mcp_server }.not_to raise_error
    end
  end
end
