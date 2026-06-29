require 'spec_helper'

class NonInsertableOrderResolver < OdataDuty::SetResolver
  def create(input)
    OpenStruct.new(id: '1', status: input.status, note: input.note)
  end

  def update(id, input)
    OpenStruct.new(id: id, status: input.status, note: input.note)
  end
end

module OdataDuty
  RSpec.describe SchemaBuilder::EntitySet, 'non_insertable properties' do
    subject(:schema) do
      SchemaBuilder.build(namespace: 'SampleSpace', host: 'localhost', base_path: '') do |s|
        order = s.add_entity_type(name: 'NonInsertableOrderEntity') do |et|
          et.property_ref 'id', String, computed: false
          et.property 'status', String, mutability: :non_insertable
          et.property 'note', String
        end
        s.add_entity_set(name: 'NonInsertableOrder', entity_type: order,
                         resolver: 'NonInsertableOrderResolver')
      end
    end

    describe 'on create' do
      let(:response) do
        Oj.load(schema.create('NonInsertableOrder', context: Context.new,
                                                    query_options: { 'status' => 'open',
                                                                     'note' => 'x' }))
      end

      it 'drops a non_insertable property to nil while read_write flows through' do
        expect(response).to include('status' => nil, 'note' => 'x')
      end

      it 'does not raise InvalidType for a wrong-typed non_insertable value on create' do
        expect do
          schema.create('NonInsertableOrder', context: Context.new,
                                              query_options: { 'status' => 12_345 })
        end.not_to raise_error
      end
    end

    describe 'on update' do
      let(:response) do
        Oj.load(schema.update("NonInsertableOrder('1')", context: Context.new,
                                                         query_options: { 'status' => 'closed',
                                                                          'note' => 'done' }))
      end

      it 'coerces a non_insertable property and keeps it present on update' do
        expect(response).to include('status' => 'closed', 'note' => 'done')
      end
    end
  end
end
