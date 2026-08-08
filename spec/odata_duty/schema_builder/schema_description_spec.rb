require 'spec_helper'

class SchemaBuilderDescGadgetResolver < OdataDuty::SetResolver
  def collection
    []
  end
end

module OdataDuty
  RSpec.describe SchemaBuilder::Schema, 'schema description validation' do
    def build_with_description(description)
      SchemaBuilder.build(namespace: 'SampleSpace', host: 'localhost') do |s|
        s.title = 'Sample Service'
        s.version = '1.0'
        s.description = description
        entity = s.add_entity_type(name: 'DescGadget') { |et| et.property_ref 'id', String }
        s.add_entity_set(name: 'DescGadgets', entity_type: entity,
                         resolver: 'SchemaBuilderDescGadgetResolver')
      end
    end

    it 'reads back the exact description that was assigned on the schema' do
      schema = build_with_description('Directory of people attending the annual conference')
      expect(schema.description)
        .to eq('Directory of people attending the annual conference')
    end

    it 'renders the Core Description annotation on the Schema element' do
      xml = build_with_description('Directory of people attending the annual conference')
            .metadata_xml
      expect(xml).to include(
        '<Annotation Term="Org.OData.Core.V1.Description" ' \
        'String="Directory of people attending the annual conference" />'
      )
    end

    it 'renders the schema Description annotation after Version and Title' do
      xml = build_with_description('Directory description').metadata_xml
      version_index = xml.index('SampleSpace.Version')
      title_index = xml.index('SampleSpace.Title')
      description_index = xml.index('Org.OData.Core.V1.Description')
      expect(version_index).to be < title_index
      expect(title_index).to be < description_index
    end

    it 'treats omitted description as no description' do
      schema = SchemaBuilder.build(namespace: 'SampleSpace', host: 'localhost') { |s| s }
      expect(schema.description).to be_nil
    end

    it 'treats description = nil the same as omitted' do
      expect { build_with_description(nil) }.not_to raise_error
      expect(build_with_description(nil).description).to be_nil
    end

    it 'omits the Description annotation entirely when no description is assigned' do
      schema = SchemaBuilder.build(namespace: 'SampleSpace', host: 'localhost') { |s| s }
      expect(schema.metadata_xml).not_to include('Org.OData.Core.V1.Description')
    end

    it 'raises InvalidDescriptionError naming the schema for an empty string' do
      expect { build_with_description('') }
        .to raise_error(InvalidDescriptionError,
                        'SampleSpace: description must be a non-empty string')
    end

    it 'raises InvalidDescriptionError for a whitespace-only string' do
      expect { build_with_description('   ') }
        .to raise_error(InvalidDescriptionError,
                        'SampleSpace: description must be a non-empty string')
    end

    it 'raises InvalidDescriptionError for a value that does not respond to to_str' do
      expect { build_with_description(123) }
        .to raise_error(InvalidDescriptionError,
                        'SampleSpace: description must be a non-empty string')
    end
  end
end
