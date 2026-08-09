require 'spec_helper'

module OdataDuty
  RSpec.describe SchemaBuilder::EnumType, 'type-level and member-level description' do
    def build_enum_with_description(description)
      schema = SchemaBuilder.build(namespace: 'SampleSpace', host: 'localhost') do |s|
        s.add_enum_type(name: 'Gender', description: description) do |e|
          e.member 'Male'
          e.member 'Female'
        end
      end
      schema.types.fetch('Gender')
    end

    it 'raises InvalidDescriptionError naming the type for an empty string' do
      expect { build_enum_with_description('') }
        .to raise_error(InvalidDescriptionError,
                        'Gender: description must be a non-empty string')
    end

    it 'raises InvalidDescriptionError for a whitespace-only string' do
      expect { build_enum_with_description('   ') }
        .to raise_error(InvalidDescriptionError,
                        'Gender: description must be a non-empty string')
    end

    it 'raises InvalidDescriptionError for a value that does not respond to to_str' do
      expect { build_enum_with_description(123) }
        .to raise_error(InvalidDescriptionError,
                        'Gender: description must be a non-empty string')
    end

    describe 'member-level description' do
      def build_member_with_description(description)
        schema = SchemaBuilder.build(namespace: 'SampleSpace', host: 'localhost') do |s|
          s.add_enum_type(name: 'Gender') do |e|
            e.member 'Male', description: description
          end
        end
        schema.types.fetch('Gender').members.first
      end

      it 'raises InvalidDescriptionError naming the member for an empty string' do
        expect { build_member_with_description('') }
          .to raise_error(InvalidDescriptionError,
                          'Male: description must be a non-empty string')
      end

      it 'raises InvalidDescriptionError for a whitespace-only string' do
        expect { build_member_with_description('   ') }
          .to raise_error(InvalidDescriptionError,
                          'Male: description must be a non-empty string')
      end

      it 'raises InvalidDescriptionError for a value that does not respond to to_str' do
        expect { build_member_with_description(123) }
          .to raise_error(InvalidDescriptionError,
                          'Male: description must be a non-empty string')
      end
    end
  end
end
