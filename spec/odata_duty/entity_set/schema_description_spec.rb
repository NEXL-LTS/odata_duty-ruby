require 'spec_helper'

class SchemaDescGadgetEntity < OdataDuty::EntityType
  property_ref 'id', String
end

class SchemaDescGadgetSet < OdataDuty::EntitySet
  entity_type SchemaDescGadgetEntity
  name 'Gadgets'
  url 'Gadgets'

  def collection
    []
  end
end

class SchemaDescSchema < OdataDuty::Schema
  namespace 'SchemaDescSpace'
  title 'Schema Description Service'
  version '1.0'
  description 'Directory of people attending the annual conference'
  base_url 'http://localhost:3000/api'
  entity_sets [SchemaDescGadgetSet]
end

RSpec.describe OdataDuty::Schema, 'schema description validation' do
  it 'reads back the exact description that was declared on the schema' do
    expect(SchemaDescSchema.description)
      .to eq('Directory of people attending the annual conference')
  end

  it 'renders the Core Description annotation on the Schema element' do
    expect(SchemaDescSchema.metadata_xml).to include(
      '<Annotation Term="Org.OData.Core.V1.Description" ' \
      'String="Directory of people attending the annual conference" />'
    )
  end

  it 'renders the schema Description annotation after Version and Title' do
    xml = SchemaDescSchema.metadata_xml
    version_index = xml.index('SchemaDescSpace.Version')
    title_index = xml.index('SchemaDescSpace.Title')
    description_index = xml.index('Org.OData.Core.V1.Description')
    expect(version_index).to be < title_index
    expect(title_index).to be < description_index
  end

  it 'treats omitted description as no description' do
    schema = Class.new(OdataDuty::Schema) do
      namespace 'NoDescSpace'
      base_url 'http://localhost:3000/api'
      entity_sets [SchemaDescGadgetSet]
    end

    expect(schema.description).to be_nil
  end

  it 'treats description nil the same as omitted' do
    schema = Class.new(OdataDuty::Schema) do
      namespace 'NilDescSpace'
      base_url 'http://localhost:3000/api'
      entity_sets [SchemaDescGadgetSet]
      description nil
    end

    expect(schema.description).to be_nil
  end

  it 'omits the Description annotation entirely when no description is declared' do
    schema = Class.new(OdataDuty::Schema) do
      namespace 'NoDescAnnotationSpace'
      base_url 'http://localhost:3000/api'
      entity_sets [SchemaDescGadgetSet]
    end

    expect(schema.metadata_xml).not_to include('Org.OData.Core.V1.Description')
  end

  it 'raises InvalidDescriptionError naming the schema for an empty string' do
    expect do
      Class.new(OdataDuty::Schema) do
        namespace 'BadDescSpace'
        description ''
      end
    end.to raise_error(OdataDuty::InvalidDescriptionError,
                       'BadDescSpace: description must be a non-empty string')
  end

  it 'raises InvalidDescriptionError for a whitespace-only string' do
    expect do
      Class.new(OdataDuty::Schema) do
        namespace 'BadDescSpace'
        description '   '
      end
    end.to raise_error(OdataDuty::InvalidDescriptionError,
                       'BadDescSpace: description must be a non-empty string')
  end

  it 'raises InvalidDescriptionError for a value that does not respond to to_str' do
    expect do
      Class.new(OdataDuty::Schema) do
        namespace 'BadDescSpace'
        description :people
      end
    end.to raise_error(OdataDuty::InvalidDescriptionError,
                       'BadDescSpace: description must be a non-empty string')
  end

  it 'raises InvalidDescriptionError for false rather than treating it as omitted' do
    expect do
      Class.new(OdataDuty::Schema) do
        namespace 'BadDescSpace'
        description false
      end
    end.to raise_error(OdataDuty::InvalidDescriptionError,
                       'BadDescSpace: description must be a non-empty string')
  end
end
