require 'spec_helper'

class BuilderWriteContextResolver < OdataDuty::SetResolver
  def create(input)
    OpenStruct.new(id: input.id, name: input.name,
                   created_via: context.od_full_url("audit/#{input.id}"))
  end

  def update(id, input)
    return nil unless id == 'known'

    OpenStruct.new(id: id, name: input.name,
                   created_via: context.od_full_url("audit/#{id}"))
  end

  def delete(id)
    return nil unless context.od_full_url("audit/#{id}").end_with?("audit/#{id}")

    true
  end
end

module OdataDuty
  RSpec.describe SchemaBuilder::EntitySet, 'threads request context into write hooks' do
    subject(:schema) do
      SchemaBuilder.build(namespace: 'SampleSpace', host: 'localhost', base_path: '/api') do |s|
        entity = s.add_entity_type(name: 'BuilderWriteContext') do |et|
          et.property_ref 'id', String, computed: false
          et.property 'name', String
          et.property 'created_via', String
        end

        s.add_entity_set(name: 'BuilderWriteContext', entity_type: entity,
                         resolver: 'BuilderWriteContextResolver')
      end
    end

    describe '#create' do
      let(:response) do
        json = schema.create('BuilderWriteContext', context: Context.new,
                                                    query_options: { 'id' => '7',
                                                                     'name' => 'Ada' })
        Oj.load(json)
      end

      it 'exposes the live context to the create hook and reflects it in the record' do
        expect(response).to include('created_via' => 'https://localhost/api/audit/7')
      end
    end

    describe '#update' do
      let(:response) do
        json = schema.update("BuilderWriteContext('known')", context: Context.new,
                                                             query_options: { 'name' => 'Grace' })
        Oj.load(json)
      end

      it 'exposes the live context to the update hook and reflects it in the record' do
        expect(response).to include('created_via' => 'https://localhost/api/audit/known')
      end

      it 'raises ResourceNotFoundError naming the missing id' do
        expect do
          schema.update("BuilderWriteContext('missing')", context: Context.new,
                                                          query_options: {})
        end.to raise_error(ResourceNotFoundError, 'No such entity missing')
      end
    end

    describe '#delete' do
      it 'exposes the live context to the delete hook' do
        expect do
          schema.delete("BuilderWriteContext('anything')", context: Context.new,
                                                           query_options: {})
        end.not_to raise_error
      end
    end
  end
end
