require 'rails_helper'

RSpec.describe Seeders::PcmnSeeder do
  include_context 'with entity'

  before { allow($stdout).to receive(:puts) }

  it 'adds an account missing from an entity that already has the chart, without touching the others' do
    described_class.call(entity: entity)
    Accounting::Account.find_by!(code: Accounting::AccountCodes::RESULT).destroy!
    kept = Accounting::Account.find_by!(code: '700000').tap { |a| a.update!(label_fr: 'Renamed by the user') }

    expect { described_class.call(entity: entity) }.to change { Accounting::Account.where(code: Accounting::AccountCodes::RESULT).count }.from(0).to(1)
    expect(kept.reload.label_fr).to eq('Renamed by the user')
  end

  %w[ASBL SRL].each do |legal_form|
    it "includes every account the app looks up by code, in the #{legal_form} chart" do
      described_class.call(entity: create(:entity, legal_form: legal_form).tap { |e| ActsAsTenant.current_tenant = e })
      wanted = Accounting::AccountCodes.constants.map { |c| Accounting::AccountCodes.const_get(c) }

      expect(wanted - Accounting::Account.pluck(:code)).to be_empty
    end
  end
end
