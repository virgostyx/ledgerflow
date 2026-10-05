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

  it "gives an association the carry accounts of its own chart (120100 / 120200), and a company the defaults (140100 / 140200)" do
    asbl = create(:entity, legal_form: "ASBL").tap { |e| ActsAsTenant.current_tenant = e }
    described_class.call(entity: asbl)
    expect(asbl.reload).to have_attributes(closing_carry_account_code: "120100", closing_loss_account_code: "120200")
    expect(Accounting::Account.where(code: %w[120100 120200]).count).to eq(2)

    company = create(:entity, legal_form: "SRL").tap { |e| ActsAsTenant.current_tenant = e }
    described_class.call(entity: company)
    expect(company.reload).to have_attributes(closing_carry_account_code: "140100", closing_loss_account_code: "140200")
    expect(Accounting::Account.where(code: %w[140100 140200]).count).to eq(2)
  end

  it "does not move an association whose owner chose other accounts" do
    asbl = create(:entity, legal_form: "ASBL", closing_carry_account_code: "120100").tap { |e| ActsAsTenant.current_tenant = e }
    described_class.call(entity: asbl)
    expect(asbl.reload.closing_carry_account_code).to eq("120100")
    asbl.update!(closing_carry_account_code: "129999")
    described_class.call(entity: asbl)
    expect(asbl.reload.closing_carry_account_code).to eq("129999")
  end
end
