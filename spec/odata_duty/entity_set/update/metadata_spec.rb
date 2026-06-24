require 'spec_helper'

class UpdateMetadataTestEntity < OdataDuty::EntityType
  property_ref 'id', String
  property 'name', String
end

class UpdatableMetadataSet < OdataDuty::EntitySet
  entity_type UpdateMetadataTestEntity

  def update(id, params)
    [id, params]
  end
end

class ReadOnlyUpdateMetadataSet < OdataDuty::EntitySet
  entity_type UpdateMetadataTestEntity
end

class UpdateMetadataTestSchema < OdataDuty::Schema
  base_url 'http://localhost:3000/api'
  entity_sets [UpdatableMetadataSet, ReadOnlyUpdateMetadataSet]
end

RSpec.describe OdataDuty::EntitySet, 'UpdateRestrictions metadata' do
  subject(:metadata_xml) { UpdateMetadataTestSchema.metadata_xml }

  describe '#metadata' do
    it 'includes UpdateRestrictions annotation for read-only entity sets' do
      read_only_xml = metadata_xml.split('<EntitySet Name="ReadOnlyUpdateMetadata"')[1]
                                  .split('</EntitySet>')[0]
      expect(read_only_xml).to include('Term="Capabilities.UpdateRestrictions"')
      expect(read_only_xml).to include('Property="Updatable" Bool="false"')
    end

    it 'does not include UpdateRestrictions annotation for updatable entity sets' do
      updatable_xml = metadata_xml.split('<EntitySet Name="UpdatableMetadata"')[1]
                                  .split('</EntitySet>')[0]
      expect(updatable_xml).not_to include('Capabilities.UpdateRestrictions')
    end

    it 'includes both Insert and Update restrictions for read-only entity sets' do
      read_only_xml = metadata_xml.split('<EntitySet Name="ReadOnlyUpdateMetadata"')[1]
                                  .split('</EntitySet>')[0]
      expect(read_only_xml).to include('Term="Capabilities.InsertRestrictions"')
      expect(read_only_xml).to include('Term="Capabilities.UpdateRestrictions"')
    end
  end
end
