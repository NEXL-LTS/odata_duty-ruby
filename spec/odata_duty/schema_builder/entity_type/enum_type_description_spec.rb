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

    it 'reads back the exact description declared on an enum type' do
      enum_type = build_enum_with_description('Gender as recorded at registration')
      expect(enum_type.description).to eq('Gender as recorded at registration')
    end

    it 'treats omitted description as no description on an enum type' do
      schema = SchemaBuilder.build(namespace: 'SampleSpace', host: 'localhost') do |s|
        s.add_enum_type(name: 'Undescribed') { |e| e.member 'One' }
      end
      expect(schema.types.fetch('Undescribed').description).to be_nil
    end

    it 'treats description: nil the same as omitted on an enum type' do
      expect(build_enum_with_description(nil).description).to be_nil
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

      it 'reads back the exact description declared on a member' do
        member = build_member_with_description('Recorded as male')
        expect(member.description).to eq('Recorded as male')
      end

      it 'treats omitted description as no description on a member' do
        schema = SchemaBuilder.build(namespace: 'SampleSpace', host: 'localhost') do |s|
          s.add_enum_type(name: 'Undescribed') { |e| e.member 'One' }
        end
        expect(schema.types.fetch('Undescribed').members.first.description).to be_nil
      end

      it 'treats description: nil the same as omitted on a member' do
        expect(build_member_with_description(nil).description).to be_nil
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
