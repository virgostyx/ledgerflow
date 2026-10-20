require 'rails_helper'

# The VAT grids a posted invoice must produce, case by case (spec/fixtures/vat_cases.yml, from docs/dev/VAT_grid_target.md).
# A rule change cannot break one of these without this spec saying which case.
RSpec.describe 'VAT declaration cases', type: :service do
  include_context 'with_open_fiscal_year'
  include_context 'with_pcmn_accounts'

  let!(:purchase_journal) { create(:journal, :purchase) }
  let!(:sale_journal)     { create(:journal, :sale) }
  let(:partner)           { create(:partner) }

  cases = YAML.load_file(Rails.root.join('spec/fixtures/vat_cases.yml')).fetch('cases')

  it 'has cases' do
    expect(cases).not_to be_empty
  end

  cases.each do |c|
    it "declares #{c['name']}" do
      account = Accounting::Account.find_by(code: c['account']) || create(:account, code: c['account'], label_fr: c['name'], entity: entity)
      customer = c['type'] == 'customer'
      invoice = create(:invoice, invoice_type: c['type'].to_sym, partner: partner, fiscal_year: fiscal_year,
                       journal: customer ? sale_journal : purchase_journal, vat_treatment: :domestic)
      create(:invoice_line, invoice: invoice, account: account, quantity: 1, unit_price: c['unit_price'], vat_rate: c['vat_rate'], position: 1)
      invoice.compute_totals
      invoice.save!
      Accounting::PostInvoice.call(invoice: invoice)

      grids = Accounting::VatGridQuery.call(fiscal_year_id: fiscal_year.id, period_start: fiscal_year.start_date, period_end: fiscal_year.end_date)
      expect(grids).to eq(c['grids'].transform_values { |v| BigDecimal(v.to_s) })
    end
  end
end
