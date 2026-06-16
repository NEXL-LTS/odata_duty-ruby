require 'spec_helper'

class CreateMetadataTestEntity < OdataDuty::EntityType
  property_ref 'id', String
  property 'name', String
end

class WritableMetadataSet < OdataDuty::EntitySet
  entity_type CreateMetadataTestEntity

  def create(params)
    params
  end
end

class ReadOnlyMetadataSet < OdataDuty::EntitySet
  entity_type CreateMetadataTestEntity
end

class CreateMetadataTestSchema < OdataDuty::Schema
  base_url 'http://localhost:3000/api'
  entity_sets [WritableMetadataSet, ReadOnlyMetadataSet]
end

RSpec.describe OdataDuty::EntitySet, 'InsertRestrictions metadata' do
  subject(:metadata_xml) { CreateMetadataTestSchema.metadata_xml }

  describe '#metadata' do
    it 'includes InsertRestrictions annotation for read-only entity sets' do
      read_only_xml = metadata_xml.split('<EntitySet Name="ReadOnlyMetadata"')[1]
                                  .split('</EntitySet>')[0]
      expect(read_only_xml).to include('Term="Capabilities.InsertRestrictions"')
      expect(read_only_xml).to include('Property="Insertable" Bool="false"')
    end

    it 'does not include InsertRestrictions annotation for writable entity sets' do
      writable_xml = metadata_xml.split('<EntitySet Name="WritableMetadata"')[1]
                                 .split('</EntitySet>')[0]
      expect(writable_xml).not_to include('Capabilities.InsertRestrictions')
    end
  end
end
