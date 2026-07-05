require 'spec_helper'

class BossChainResolver < OdataDuty::SetResolver
  def od_after_init
    alice = OpenStruct.new(id: 1, boss: nil)
    @records = [alice, OpenStruct.new(id: 2, boss: alice)]
  end

  def collection
    @records
  end
end

class ReplyChainResolver < OdataDuty::SetResolver
  def od_after_init
    original = OpenStruct.new(body: 'first!', in_reply_to: nil)
    reply = OpenStruct.new(body: 'actually...', in_reply_to: original)
    @records = [OpenStruct.new(id: 1, latest_comment: reply)]
  end

  def collection
    @records
  end
end

module OdataDuty
  RSpec.describe SchemaBuilder::EntitySet, 'self-referencing entity types' do
    subject(:schema) do
      SchemaBuilder.build(namespace: 'HR', host: 'localhost') do |s|
        manager = s.add_entity_type(name: 'Manager') do |et|
          et.property_ref 'id', Integer
          et.property 'boss', et, nullable: true
        end
        s.add_entity_set(name: 'Managers', entity_type: manager, resolver: 'BossChainResolver')
      end
    end

    it 'declares the self-reference once in $metadata' do
      xml = schema.metadata_xml
      expect(xml).to include('<Property Name="boss" Nullable="true" Type="HR.Manager" />')
      expect(xml.scan('<EntityType Name="Manager">').size).to eq(1)
    end

    it 'returns self-referenced values nested in payloads, ending where the data ends' do
      json = schema.execute('Managers', context: Context.new, query_options: {})
      bosses = Oj.load(json).fetch('value').map { |manager| manager['boss'] }
      expect(bosses).to eq([nil, { 'id' => 1, 'boss' => nil }])
    end
  end

  RSpec.describe SchemaBuilder::EntitySet, 'self-containing complex types' do
    subject(:schema) do
      SchemaBuilder.build(namespace: 'Forum', host: 'localhost') do |s|
        comment = s.add_complex_type(name: 'Comment') do |ct|
          ct.property 'body', String
          ct.property 'in_reply_to', ct, nullable: true
        end
        post = s.add_entity_type(name: 'Post') do |et|
          et.property_ref 'id', Integer
          et.property 'latest_comment', comment, nullable: true
        end
        s.add_entity_set(name: 'Posts', entity_type: post, resolver: 'ReplyChainResolver')
      end
    end

    it 'declares the complex type that contains itself once' do
      xml = schema.metadata_xml
      expect(xml)
        .to include('<Property Name="in_reply_to" Nullable="true" Type="Forum.Comment" />')
      expect(xml.scan('<ComplexType Name="Comment">').size).to eq(1)
    end

    it 'returns recursively nested complex values, ending where the data ends' do
      json = schema.execute('Posts', context: Context.new, query_options: {})
      comment = Oj.load(json).fetch('value').first.fetch('latest_comment')
      expect(comment).to eq('body' => 'actually...',
                            'in_reply_to' => { 'body' => 'first!', 'in_reply_to' => nil })
    end
  end
end
