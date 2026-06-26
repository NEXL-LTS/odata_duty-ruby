require 'spec_helper'

class DeleteMetadataTestEntity < OdataDuty::EntityType
  property_ref 'id', String
  property 'name', String
end

class DeletableMetadataSet < OdataDuty::EntitySet
  entity_type DeleteMetadataTestEntity

  def delete(id)
    id
  end
end

class ReadOnlyDeleteMetadataSet < OdataDuty::EntitySet
  entity_type DeleteMetadataTestEntity
end

class DeleteMetadataTestSchema < OdataDuty::Schema
  base_url 'http://localhost:3000/api'
  entity_sets [DeletableMetadataSet, ReadOnlyDeleteMetadataSet]
end

RSpec.describe OdataDuty::EntitySet, 'DeleteRestrictions metadata' do
  subject(:metadata_xml) { DeleteMetadataTestSchema.metadata_xml }

  describe '#metadata' do
    it 'includes DeleteRestrictions annotation for non-deletable entity sets' do
      read_only_xml = metadata_xml.split('<EntitySet Name="ReadOnlyDeleteMetadata"')[1]
                                  .split('</EntitySet>')[0]
      expect(read_only_xml).to include('Term="Capabilities.DeleteRestrictions"')
      expect(read_only_xml).to include('Property="Deletable" Bool="false"')
    end

    it 'does not include DeleteRestrictions annotation for deletable entity sets' do
      deletable_xml = metadata_xml.split('<EntitySet Name="DeletableMetadata"')[1]
                                  .split('</EntitySet>')[0]
      expect(deletable_xml).not_to include('Capabilities.DeleteRestrictions')
    end
  end
end
