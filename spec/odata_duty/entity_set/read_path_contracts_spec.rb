require 'spec_helper'

class ReadPathEntity < OdataDuty::EntityType
  property_ref 'id', Integer

  property 'profile_url', String
  def profile_url
    od_context.od_full_url("Profiles(#{object.id})")
  end
end

class ReadPathPeopleSet < OdataDuty::EntitySet
  entity_type ReadPathEntity

  def collection
    [OpenStruct.new(id: 1)]
  end

  def individual(id)
    [OpenStruct.new(id: 1)].find { |x| x.id == id }
  end
end

class ReadPathNoCollectionSet < OdataDuty::EntitySet
  entity_type ReadPathEntity

  def individual(id)
    [OpenStruct.new(id: 1)].find { |x| x.id == id }
  end
end

class ReadPathNoIndividualSet < OdataDuty::EntitySet
  entity_type ReadPathEntity

  def collection
    [OpenStruct.new(id: 1)]
  end
end

class ReadPathContractsSchema < OdataDuty::Schema
  base_url 'https://example.org/odata'
  entity_sets [ReadPathPeopleSet, ReadPathNoCollectionSet, ReadPathNoIndividualSet]
end

RSpec.describe OdataDuty::EntitySet, 'read-path contracts' do
  subject(:schema) { ReadPathContractsSchema }

  describe 'missing implementations' do
    it 'raises NoImplementationError naming the set when collection is undefined' do
      expect { schema.execute('ReadPathNoCollection', context: Context.new) }
        .to raise_error(OdataDuty::NoImplementationError,
                        'collection not implemented for ReadPathNoCollectionSet')
    end

    it 'raises NoImplementationError naming the set when individual is undefined' do
      expect { schema.execute('ReadPathNoIndividual(1)', context: Context.new) }
        .to raise_error(OdataDuty::NoImplementationError,
                        'individual not implemented for ReadPathNoIndividualSet')
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

  describe 'property methods reading od_context during response mapping' do
    it 'renders od_full_url in the collection JSON' do
      json = schema.execute('ReadPathPeople', context: Context.new)
      response = Oj.load(json)
      expect(response['value'].first['profile_url'])
        .to eq('https://example.org/odata/Profiles(1)')
    end

    it 'renders od_full_url in the individual JSON' do
      json = schema.execute('ReadPathPeople(1)', context: Context.new)
      response = Oj.load(json)
      expect(response['profile_url']).to eq('https://example.org/odata/Profiles(1)')
    end
  end
end
