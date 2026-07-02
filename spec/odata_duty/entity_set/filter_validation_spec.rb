require 'spec_helper'

class FilterValidationEntity < OdataDuty::EntityType
  property_ref 'id', String
  property 'name', String
end

class FilterValidationSet < OdataDuty::EntitySet
  entity_type FilterValidationEntity

  def od_after_init
    @records = [OpenStruct.new(id: '1', name: 'a')]
  end

  def od_filter_eq(property_name, value)
    @records = @records.select { |r| r.public_send(property_name) == value }
  end

  def collection
    @records
  end
end

class FilterValidationSchema < OdataDuty::Schema
  base_url 'http://localhost:3000/api'
  entity_sets [FilterValidationSet]
end

RSpec.describe OdataDuty::EntitySet, 'filter validation errors' do
  subject(:schema) { FilterValidationSchema }

  def execute(filter)
    schema.execute('FilterValidation', context: Context.new,
                                       query_options: { '$filter' => filter })
  end

  it 'rejects arithmetic operators' do
    expect { execute('id add 1 eq 2') }
      .to raise_error(OdataDuty::NotYetSupportedError, /arithmetic operators/)
  end

  it 'rejects nested property filtering' do
    expect { execute('address/city eq \'x\'') }
      .to raise_error(OdataDuty::NotYetSupportedError, /nested property filtering/)
  end
end
