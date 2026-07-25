require 'spec_helper'

# Builder DSL only; the class DSL is a sibling task.
BuilderDispatchContext = Struct.new(:marker)

class BuilderDispatchUsersResolver < OdataDuty::SetResolver
  RECORDS = [OpenStruct.new(id: '1', name: 'Alice'),
             OpenStruct.new(id: '2', name: 'Bob')].freeze

  def collection
    RECORDS.map { |r| OpenStruct.new(id: r.id, name: "#{r.name}-#{context.marker}") }
  end

  def individual(id)
    found = RECORDS.find { |r| r.id == id }
    found && OpenStruct.new(id: found.id, name: "#{found.name}-#{context.marker}")
  end

  def count
    context.marker && RECORDS.count
  end

  def create(input)
    OpenStruct.new(id: '3', name: "#{input.name}-#{context.marker}")
  end

  def update(id, input)
    return nil unless RECORDS.any? { |r| r.id == id }

    OpenStruct.new(id: id, name: "#{input.name}-#{context.marker}")
  end

  def delete(id)
    (context.marker && RECORDS.any? { |r| r.id == id }) || nil
  end
end

class BuilderConfirmedDeleteResolver < OdataDuty::SetResolver
  def delete(id)
    context.query_options.key?('confirm') ? id : nil
  end
end

module OdataDuty
  RSpec.describe SchemaBuilder::Schema, 'builder-DSL request-dispatch entry points' do
    subject(:schema) do
      SchemaBuilder.build(namespace: 'Dispatch', scheme: 'http', host: 'localhost:3000',
                          base_path: '/api') do |s|
        entity = s.add_entity_type(name: 'BuilderDispatch') do |et|
          et.property_ref 'id', String, computed: false
          et.property 'name', String
        end

        s.add_entity_set(name: 'BuilderDispatchUsers', entity_type: entity,
                         resolver: 'BuilderDispatchUsersResolver')
        s.add_entity_set(name: 'BuilderConfirmedDelete', entity_type: entity,
                         resolver: 'BuilderConfirmedDeleteResolver')
      end
    end

    let(:context) { BuilderDispatchContext.new('ctx') }

    describe '#execute routes the same URL family to distinct results' do
      it 'routes the bare set name to the collection, passing the caller context through' do
        response = Oj.load(schema.execute('BuilderDispatchUsers', context: context))
        expect(response['value'].map { |r| r['name'] }).to eq(%w[Alice-ctx Bob-ctx])
      end

      it 'routes a keyed URL to the matching individual, passing the caller context through' do
        response = Oj.load(schema.execute("BuilderDispatchUsers('2')", context: context))
        expect(response).to include('id' => '2', 'name' => 'Bob-ctx')
      end

      it 'routes the $count suffix to the count, passing the caller context through' do
        expect(schema.execute('BuilderDispatchUsers/$count', context: context)).to eq(2)
      end

      it 'raises UnknownPropertyError for an unknown entity set' do
        expect do
          schema.execute('NoSuchSet', context: context)
        end.to raise_error(OdataDuty::UnknownPropertyError)
      end

      it 'raises ResourceNotFoundError for a missing individual' do
        expect do
          schema.execute("BuilderDispatchUsers('999')", context: context)
        end.to raise_error(OdataDuty::ResourceNotFoundError)
      end

      it 'propagates UnknownPropertyError for an unknown $select property' do
        expect do
          schema.execute('BuilderDispatchUsers', context: context,
                                                 query_options: { '$select' => 'nope' })
        end.to raise_error(OdataDuty::UnknownPropertyError)
      end

      it 'defaults query_options to an empty hash when omitted' do
        response = Oj.load(schema.execute('BuilderDispatchUsers', context: context))
        expect(response).to have_key('value')
      end

      it 'reads the $select query option when supplied' do
        response = Oj.load(schema.execute('BuilderDispatchUsers', context: context,
                                                                  query_options: {
                                                                    '$select' => 'name'
                                                                  }))
        expect(response['value'].first).not_to have_key('id')
      end
    end

    describe '#create returns the created entity' do
      it 'returns the created payload, passing body and caller context through' do
        json = schema.create('BuilderDispatchUsers', context: context,
                                                     query_options: { 'name' => 'Carol' })
        expect(Oj.load(json)).to include('id' => '3', 'name' => 'Carol-ctx')
      end

      it 'defaults query_options so an omitted body reads its fields as nil' do
        json = schema.create('BuilderDispatchUsers', context: context)
        expect(Oj.load(json)).to include('id' => '3', 'name' => '-ctx')
      end

      it 'propagates InvalidType for a body value of the wrong type' do
        expect do
          schema.create('BuilderDispatchUsers', context: context,
                                                query_options: { 'name' => 1 })
        end.to raise_error(OdataDuty::InvalidType)
      end
    end

    describe '#update partial-merges and returns the updated entity' do
      it 'returns the updated payload, passing body and caller context through' do
        json = schema.update("BuilderDispatchUsers('1')", context: context,
                                                          query_options: { 'name' => 'Alice X' })
        expect(Oj.load(json)).to include('id' => '1', 'name' => 'Alice X-ctx')
      end

      it 'reads omitted body fields as nil when query_options defaults' do
        json = schema.update("BuilderDispatchUsers('1')", context: context)
        expect(Oj.load(json)).to include('id' => '1', 'name' => '-ctx')
      end

      it 'raises ResourceNotFoundError for a missing individual' do
        expect do
          schema.update("BuilderDispatchUsers('999')", context: context, query_options: {})
        end.to raise_error(OdataDuty::ResourceNotFoundError)
      end
    end

    describe '#delete removes and returns no entity payload' do
      it 'removes the entity for a known key, observing the caller context' do
        result = schema.delete("BuilderDispatchUsers('1')", context: context, query_options: {})
        expect(Oj.load(result)).not_to include('id')
      end

      it 'succeeds when query_options defaults to an empty hash' do
        expect do
          schema.delete("BuilderDispatchUsers('2')", context: context)
        end.not_to raise_error
      end

      it 'raises ResourceNotFoundError for a missing individual' do
        expect do
          schema.delete("BuilderDispatchUsers('999')", context: context, query_options: {})
        end.to raise_error(OdataDuty::ResourceNotFoundError)
      end

      it 'threads query options to the resolver, which deletes only when confirm is present' do
        result = schema.delete("BuilderConfirmedDelete('1')", context: context,
                                                              query_options: { 'confirm' => 'y' })
        expect(Oj.load(result)).to eq('@odata.context' => 'http://localhost:3000/api/$metadata')
      end

      it 'raises ResourceNotFoundError when the confirm option is absent' do
        expect do
          schema.delete("BuilderConfirmedDelete('1')", context: context, query_options: {})
        end.to raise_error(OdataDuty::ResourceNotFoundError)
      end
    end
  end
end
