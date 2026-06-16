require 'spec_helper'

class WritableMetadataResolver < OdataDuty::SetResolver
  def create(params)
    params
  end
end

class ReadOnlyMetadataResolver < OdataDuty::SetResolver
end

module OdataDuty
  RSpec.describe SchemaBuilder::EntitySet, 'InsertRestrictions metadata' do
    subject(:metadata_xml) do
      SchemaBuilder.build(namespace: 'SampleSpace', host: 'localhost', base_path: '/api') do |s|
        entity = s.add_entity_type(name: 'CreateMetadataTestEntity') do |et|
          et.property_ref 'id', String
          et.property 'name', String
        end

        s.add_entity_set(name: 'WritableMetadata', entity_type: entity,
                         resolver: 'WritableMetadataResolver')
        s.add_entity_set(name: 'ReadOnlyMetadata', entity_type: entity,
                         resolver: 'ReadOnlyMetadataResolver')
      end.metadata_xml
    end

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
end
