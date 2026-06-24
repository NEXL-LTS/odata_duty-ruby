require 'spec_helper'

class UpdatableMetadataResolver < OdataDuty::SetResolver
  def update(id, params)
    [id, params]
  end
end

class ReadOnlyUpdateMetadataResolver < OdataDuty::SetResolver
end

module OdataDuty
  RSpec.describe SchemaBuilder::EntitySet, 'UpdateRestrictions metadata' do
    subject(:metadata_xml) do
      SchemaBuilder.build(namespace: 'SampleSpace', host: 'localhost', base_path: '/api') do |s|
        entity = s.add_entity_type(name: 'UpdateMetadataTestEntity') do |et|
          et.property_ref 'id', String
          et.property 'name', String
        end

        s.add_entity_set(name: 'UpdatableMetadata', entity_type: entity,
                         resolver: 'UpdatableMetadataResolver')
        s.add_entity_set(name: 'ReadOnlyUpdateMetadata', entity_type: entity,
                         resolver: 'ReadOnlyUpdateMetadataResolver')
      end.metadata_xml
    end

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
end
