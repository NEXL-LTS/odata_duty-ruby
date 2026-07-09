require 'spec_helper'

class KeyExtractionResolver < OdataDuty::SetResolver
  RECORDS = ['bob', "it''s", 'a"b', 'b'].map { |id| OpenStruct.new(id: id) }

  def find(id)
    KeyExtractionResolver::RECORDS.find { |r| r.id == id }
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

module OdataDuty
  RSpec.describe SchemaBuilder::EntitySet, 'key extraction from the URL brackets' do
    subject(:schema) do
      SchemaBuilder.build(namespace: 'SampleSpace', host: 'localhost', base_path: '') do |s|
        entity = s.add_entity_type(name: 'KeyExtractionEntity') do |et|
          et.property_ref 'id', String, computed: false
          et.property 'echoed_id', String
        end
        s.add_entity_set(name: 'KeyExtraction', entity_type: entity,
                         resolver: 'KeyExtractionResolver')
      end
    end

    def individual(bracketed)
      Oj.load(schema.execute("KeyExtraction#{bracketed}", context: Context.new))
    end

    describe 'the individual GET path' do
      it 'resolves the same entity for single-quoted, double-quoted, or bare keys' do
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
        end.to raise_error(ResourceNotFoundError)
      end
    end
  end
end
