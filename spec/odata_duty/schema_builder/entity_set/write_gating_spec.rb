require 'spec_helper'

class WriteGatingPeopleResolver < OdataDuty::SetResolver
  def collection
    [OpenStruct.new(id: '1')]
  end

  def create(params)
    params
  end

  def update(id, _params)
    OpenStruct.new(id: id)
  end

  def delete(id)
    OpenStruct.new(id: id)
  end
end

class WriteGatingReadOnlyResolver < OdataDuty::SetResolver
  def collection
    [OpenStruct.new(id: '1')]
  end
end

module OdataDuty
  RSpec.describe SchemaBuilder::EntitySet, 'write-capability gating and endpoint resolution' do
    subject(:schema) do
      SchemaBuilder.build(namespace: 'Space', scheme: 'http', host: 'localhost',
                          base_path: '/api') do |s|
        entity = s.add_entity_type(name: 'WriteGating') do |et|
          et.property_ref 'id', String, computed: false
          et.property 'string', String
        end

        s.add_entity_set(name: 'People', entity_type: entity,
                         resolver: 'WriteGatingPeopleResolver')
        s.add_entity_set(name: 'ReadOnly', entity_type: entity,
                         resolver: 'WriteGatingReadOnlyResolver')
      end
    end

    describe 'unknown endpoint' do
      it 'raises UnknownPropertyError listing every registered set url' do
        expect { schema.execute('Nope', context: Context.new, query_options: {}) }
          .to raise_error(UnknownPropertyError,
                          'No endpoint Nope found in ["People", "ReadOnly"]')
      end
    end

    describe 'create on a set without a create method' do
      it 'raises NoImplementationError naming the set url' do
        expect { schema.create('ReadOnly', context: Context.new, query_options: {}) }
          .to raise_error(NoImplementationError, 'create not implemented for ReadOnly')
      end

      it 'names the bare set url even when the request url carries brackets' do
        expect { schema.create('ReadOnly(1)', context: Context.new, query_options: {}) }
          .to raise_error(NoImplementationError, 'create not implemented for ReadOnly')
      end
    end

    describe 'update on a set without an update method' do
      it 'raises NoImplementationError naming the set url' do
        expect { schema.update("ReadOnly('1')", context: Context.new, query_options: {}) }
          .to raise_error(NoImplementationError, 'update not implemented for ReadOnly')
      end
    end

    describe 'delete on a set without a delete method' do
      it 'raises NoImplementationError naming the set url' do
        expect { schema.delete("ReadOnly('1')", context: Context.new, query_options: {}) }
          .to raise_error(NoImplementationError, 'delete not implemented for ReadOnly')
      end
    end

    describe 'successful delete envelope' do
      it 'returns exactly the metadata context anchor with no other keys' do
        result = schema.delete("People('bob')", context: Context.new, query_options: {})
        expect(result).to eq('{"@odata.context":"http://localhost/api/$metadata"}')
      end
    end
  end
end
