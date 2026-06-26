require 'spec_helper'

class DeletableMetadataResolver < OdataDuty::SetResolver
  def delete(id)
    id
  end
end

class ReadOnlyDeleteMetadataResolver < OdataDuty::SetResolver
end

module OdataDuty
  RSpec.describe SchemaBuilder::EntitySet, 'DeleteRestrictions metadata' do
    subject(:metadata_xml) do
      SchemaBuilder.build(namespace: 'SampleSpace', host: 'localhost', base_path: '/api') do |s|
        entity = s.add_entity_type(name: 'DeleteMetadataTestEntity') do |et|
          et.property_ref 'id', String
          et.property 'name', String
        end

        s.add_entity_set(name: 'DeletableMetadata', entity_type: entity,
                         resolver: 'DeletableMetadataResolver')
        s.add_entity_set(name: 'ReadOnlyDeleteMetadata', entity_type: entity,
                         resolver: 'ReadOnlyDeleteMetadataResolver')
      end.metadata_xml
    end

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
end
