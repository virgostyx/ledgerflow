require 'rails_helper'

RSpec.describe Accounting::RuleValidation, type: :model do
  include_context 'with entity'

  def attrs(overrides = {})
    { rule_key: 'vat_declaration', validated_by_name: 'Jane Doe', validated_by_title: 'Chartered accountant, Doe & Co',
      validated_on: Date.current, reference: 'letter of 2026-10-30' }.merge(overrides)
  end

  it 'is valid with who, in what capacity, when and where it is written' do
    expect(described_class.new(attrs)).to be_valid
  end

  it 'refuses an unknown rule' do
    expect(described_class.new(attrs(rule_key: 'nope'))).not_to be_valid
  end

  %i[validated_by_name validated_by_title reference validated_on].each do |field|
    it "requires #{field}" do
      expect(described_class.new(attrs(field => nil))).not_to be_valid
    end
  end

  it 'refuses a date in the future' do
    expect(described_class.new(attrs(validated_on: Date.tomorrow))).not_to be_valid
  end

  describe '.validated?' do
    it 'is false without a validation' do
      expect(described_class.validated?('vat_declaration')).to be false
    end

    it 'is true while a validation is in force, per rule' do
      described_class.create!(attrs)
      expect(described_class.validated?('vat_declaration')).to be true
      expect(described_class.validated?('annual_accounts')).to be false
    end

    it 'is false once revoked' do
      described_class.create!(attrs).revoke!
      expect(described_class.validated?('vat_declaration')).to be false
    end
  end

  it 'allows only one validation in force per rule' do
    described_class.create!(attrs)
    expect { described_class.create!(attrs) }.to raise_error(ActiveRecord::RecordNotUnique)
  end
end
