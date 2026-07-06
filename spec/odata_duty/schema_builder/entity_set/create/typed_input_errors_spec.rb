require 'spec_helper'

class ReadsUndefinedPropertyResolver < OdataDuty::SetResolver
  def create(input)
    input.nickname
  end
end

class AccessorWithArgumentResolver < OdataDuty::SetResolver
  def create(input)
    input.first_name('unexpected')
  end
end

module OdataDuty
  RSpec.describe SchemaBuilder::EntitySet, 'typed input error contracts' do
    subject(:schema) do
      SchemaBuilder.build(namespace: 'SampleSpace', host: 'localhost', base_path: '') do |s|
        entity = s.add_entity_type(name: 'TypedInputErrorsEntity') do |et|
          et.property_ref 'id', String, computed: false
          et.property 'first_name', String
        end

        s.add_entity_set(name: 'ReadsUndefinedProperty', entity_type: entity,
                         resolver: 'ReadsUndefinedPropertyResolver')
        s.add_entity_set(name: 'AccessorWithArgument', entity_type: entity,
                         resolver: 'AccessorWithArgumentResolver')
      end
    end

    def create(name)
      schema.create(name, context: Context.new, query_options: { 'id' => '1' })
    end

    it 'raises NoSuchPropertyError with an exact message when reading an undefined property' do
      expect { create('ReadsUndefinedProperty') }
        .to raise_error(OdataDuty::NoSuchPropertyError, "No such property 'nickname'")
    end

    it 'raises NoSuchPropertyError when a property accessor is called with an argument' do
      expect { create('AccessorWithArgument') }
        .to raise_error(OdataDuty::NoSuchPropertyError)
    end
  end
end
