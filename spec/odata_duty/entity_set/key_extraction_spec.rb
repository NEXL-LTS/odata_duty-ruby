require 'spec_helper'

class KeyExtractionEntity < OdataDuty::EntityType
  property_ref 'id', String, computed: false
  property 'echoed_id', String
end

class KeyExtractionSet < OdataDuty::EntitySet
  entity_type KeyExtractionEntity

  RECORDS = ['bob', "it''s", 'a"b', 'b'].map { |id| OpenStruct.new(id: id) }

  def find(id)
    KeyExtractionSet::RECORDS.find { |r| r.id == id }
  end

  def individual(id)
    record = find(id)
    return nil unless record

    OpenStruct.new(id: record.id, echoed_id: record.id)
  end

  def update(id, _input)
    return nil unless find(id)

    OpenStruct.new(id: id, echoed_id: id)
  end

  def delete(id)
    find(id)
  end
end

class KeyExtractionRootSet < OdataDuty::EntitySet
  entity_type KeyExtractionEntity
  url ''

  def individual(id)
    return nil unless id == 'bob'

    OpenStruct.new(id: id, echoed_id: id)
  end
end

class KeyExtractionSchema < OdataDuty::Schema
  base_url 'https://example.org/odata'
  entity_sets [KeyExtractionSet, KeyExtractionRootSet]
end

RSpec.describe OdataDuty::EntitySet, 'key extraction from the URL brackets' do
  subject(:schema) { KeyExtractionSchema }

  def individual(bracketed)
    Oj.load(schema.execute("KeyExtraction#{bracketed}", context: Context.new))
  end

  describe 'the individual GET path' do
    it 'resolves the same entity whether the key is single-quoted, double-quoted, or bare' do
      expect(individual("('bob')")['id']).to eq('bob')
      expect(individual('("bob")')['id']).to eq('bob')
      expect(individual('(bob)')['id']).to eq('bob')
    end

    it 'strips exactly one pair of double quotes and preserves interior double quotes' do
      expect(individual('("a"b")')['id']).to eq('a"b')
    end

    it 'strips exactly one pair of single quotes and preserves interior doubled quotes' do
      expect(individual("('it''s')")['id']).to eq("it''s")
    end

    it 'keys off the last open bracket when the key itself contains one' do
      expect(individual("('a(b')")['id']).to eq('b')
    end

    it 'extracts the key for a set mounted at the empty root url' do
      json = schema.execute('(bob)', context: Context.new)
      expect(Oj.load(json)['id']).to eq('bob')
    end
  end

  describe 'update extracts the key identically to the GET path' do
    it 'echoes the same single-quoted key GET would resolve' do
      json = schema.update("KeyExtraction('bob')", context: Context.new, query_options: {})
      expect(Oj.load(json)['echoed_id']).to eq('bob')
    end

    it 'echoes the interior-quote-preserving key GET would resolve' do
      json = schema.update("KeyExtraction('it''s')", context: Context.new, query_options: {})
      expect(Oj.load(json)['echoed_id']).to eq("it''s")
    end
  end

  describe 'delete extracts the key identically to the GET path' do
    it 'finds the entity with the double-quote-stripped, interior-preserving key' do
      expect do
        schema.delete('KeyExtraction("a"b")', context: Context.new, query_options: {})
      end.not_to raise_error
    end

    it 'raises for a key that after extraction matches no entity' do
      expect do
        schema.delete("KeyExtraction('nope')", context: Context.new, query_options: {})
      end.to raise_error(OdataDuty::ResourceNotFoundError)
    end
  end
end
