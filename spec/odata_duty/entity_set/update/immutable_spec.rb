require 'spec_helper'

class ImmutableOrderEntity < OdataDuty::EntityType
  property_ref 'id', String, computed: false
  property 'account_number', String, mutability: :immutable
  property 'note', String
  property 'created_at', DateTime, mutability: :computed
end

class ImmutableOrderSet < OdataDuty::EntitySet
  entity_type ImmutableOrderEntity

  def create(input)
    OpenStruct.new(id: '1', account_number: input.account_number, note: input.note,
                   created_at: input.created_at)
  end

  def update(id, input)
    OpenStruct.new(id: id, account_number: input.account_number, note: input.note)
  end
end

class ImmutableOrderSchema < OdataDuty::Schema
  base_url 'http://localhost:3000/api'
  entity_sets [ImmutableOrderSet]
end

RSpec.describe OdataDuty::EntitySet, 'immutable properties' do
  subject(:schema) { ImmutableOrderSchema }

  describe 'on create' do
    let(:response) do
      Oj.load(schema.create('ImmutableOrder', context: Context.new,
                                              query_options: { 'account_number' => 'A-100',
                                                               'note' => 'x',
                                                               'created_at' =>
                                                                 '2021-01-01T00:00:00Z' }))
    end

    it 'coerces an immutable property and ignores a computed one' do
      expect(response).to include('account_number' => 'A-100', 'note' => 'x',
                                  'created_at' => nil)
    end
  end

  describe 'on update' do
    let(:response) do
      Oj.load(schema.update("ImmutableOrder('1')", context: Context.new,
                                                   query_options: { 'account_number' => 'A-999',
                                                                    'note' => 'done' }))
    end

    it 'silently drops an immutable property while read_write flows through' do
      expect(response).to include('account_number' => nil, 'note' => 'done')
    end

    it 'does not raise InvalidType for a wrong-typed immutable value' do
      expect do
        schema.update("ImmutableOrder('1')", context: Context.new,
                                             query_options: { 'account_number' => 12_345 })
      end.not_to raise_error
    end
  end
end
