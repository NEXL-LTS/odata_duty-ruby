require 'spec_helper'

class NonInsertableOrderEntity < OdataDuty::EntityType
  property_ref 'id', String, computed: false
  property 'status', String, mutability: :non_insertable
  property 'note', String
end

class NonInsertableOrderSet < OdataDuty::EntitySet
  entity_type NonInsertableOrderEntity

  def create(input)
    OpenStruct.new(id: '1', status: input.status, note: input.note)
  end

  def update(id, input)
    OpenStruct.new(id: id, status: input.status, note: input.note)
  end
end

class NonInsertableOrderSchema < OdataDuty::Schema
  base_url 'http://localhost:3000/api'
  entity_sets [NonInsertableOrderSet]
end

RSpec.describe OdataDuty::EntitySet, 'non_insertable properties' do
  subject(:schema) { NonInsertableOrderSchema }

  describe 'on create' do
    let(:response) do
      Oj.load(schema.create('NonInsertableOrder', context: Context.new,
                                                  query_options: { 'status' => 'open',
                                                                   'note' => 'x' }))
    end

    it 'drops a non_insertable property and reads back nil while read_write flows through' do
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

    it 'coerces a non_insertable property and keeps it present while read_write flows through' do
      expect(response).to include('status' => 'closed', 'note' => 'done')
    end
  end
end
