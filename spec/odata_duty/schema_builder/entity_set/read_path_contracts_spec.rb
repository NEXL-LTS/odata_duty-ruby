require 'spec_helper'

class ReadPathContractsSupportsResolver < OdataDuty::SetResolver
  def collection
    [OpenStruct.new(id: 1)]
  end

  def individual(id)
    [OpenStruct.new(id: 1)].find { |x| x.id == id }
  end
end

class ReadPathContractsNoCollectionResolver < OdataDuty::SetResolver
  def individual(id)
    [OpenStruct.new(id: 1)].find { |x| x.id == id }
  end
end

class ReadPathContractsNoIndividualResolver < OdataDuty::SetResolver
  def collection
    [OpenStruct.new(id: 1)]
  end
end

module OdataDuty
  RSpec.describe SchemaBuilder::EntitySet, 'read-path contracts' do
    subject(:schema) do
      SchemaBuilder.build(namespace: 'Space', host: 'example.org', base_path: '/odata') do |s|
        entity = s.add_entity_type(name: 'ReadPathContract') do |et|
          et.property_ref 'id', Integer
        end

        s.add_entity_set(name: 'ReadPathPeople', entity_type: entity,
                         resolver: 'ReadPathContractsSupportsResolver')
        s.add_entity_set(name: 'ReadPathNoCollection', entity_type: entity,
                         resolver: 'ReadPathContractsNoCollectionResolver')
        s.add_entity_set(name: 'ReadPathNoIndividual', entity_type: entity,
                         resolver: 'ReadPathContractsNoIndividualResolver')
      end
    end

    describe 'missing implementations' do
      it 'raises NoImplementationError naming the resolver when collection is undefined' do
        expect { schema.execute('ReadPathNoCollection', context: Context.new) }
          .to raise_error(OdataDuty::NoImplementationError,
                          'collection not implemented for ReadPathContractsNoCollectionResolver')
      end

      it 'raises NoImplementationError naming the resolver when individual is undefined' do
        expect { schema.execute('ReadPathNoIndividual(1)', context: Context.new) }
          .to raise_error(OdataDuty::NoImplementationError,
                          'individual not implemented for ReadPathContractsNoIndividualResolver')
      end
    end

    describe 'individual lookup failures' do
      it 'raises ResourceNotFoundError naming the missing id' do
        expect { schema.execute('ReadPathPeople(999)', context: Context.new) }
          .to raise_error(OdataDuty::ResourceNotFoundError, 'No such entity 999')
      end

      it 'raises InvalidPropertyReferenceValue when the id fails key coercion' do
        expect { schema.execute("ReadPathPeople('abc')", context: Context.new) }
          .to raise_error(OdataDuty::InvalidPropertyReferenceValue,
                          /\AInvalid individual id : .*abc/)
      end
    end
  end
end
