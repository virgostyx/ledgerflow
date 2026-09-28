require "rails_helper"

# R10 listing annuel des clients assujettis (docs/dev/reports/spec.md §10): Belgian customers
# whose annual HTVA turnover exceeds the threshold — VAT number, name, HTVA, VAT — with
# anomalies for a missing or invalid VAT number.
RSpec.describe Accounting::AnnualCustomerListingQuery, type: :query, bullet_strict: true do
  include_context "with_open_fiscal_year"
  include_context "with_pcmn_accounts"

  let(:valid_vat)   { "BE0403170701" }
  let!(:journal)    { create(:journal, :sale) }
  let(:acme)        { create(:partner, name: "Acme", vat_number: valid_vat, country: "BE") }
  let(:query)       { described_class.new(fiscal_year: fiscal_year, threshold: 250) }

  def sale(partner, amount, rate: 21, treatment: :domestic, credit_note: false, date: fiscal_year.start_date + 5)
    inv = create(:invoice, :customer, partner: partner, fiscal_year: fiscal_year, invoice_date: date,
                 vat_treatment: treatment, document_type: credit_note ? :credit_note : :invoice, status: :draft)
    create(:invoice_line, invoice: inv, account: account_700, unit_price: amount, quantity: 1, vat_rate: rate)
    result = Accounting::PostInvoice.call(invoice: inv)
    raise result.message if result.failure?
    inv
  end

  it "lists a Belgian customer above the threshold with HTVA and VAT amounts" do
    sale(acme, 1000)
    row = query.call.rows.find { |r| r.partner_name == "Acme" }
    expect(row).to have_attributes(vat_number: valid_vat, amount_excl_vat: 1000, vat_amount: 210, anomalies: [])
  end

  it "leaves out a customer at or under the threshold" do
    sale(acme, 250)
    expect(query.call.rows).to be_empty
  end

  it "nets credit notes and leaves out non-domestic sales" do
    sale(acme, 1000)
    sale(acme, 200, credit_note: true)
    sale(acme, 5000, rate: 0, treatment: :intracom_goods)
    expect(query.call.rows.find { |r| r.partner_name == "Acme" }.amount_excl_vat).to eq(800)
  end

  it "flags a missing and an invalid VAT number" do
    no_vat  = create(:partner, name: "NoVat", vat_number: nil, country: "BE")
    bad_vat = create(:partner, name: "BadVat", vat_number: "BE0403170702", country: "BE")
    sale(no_vat, 600)
    sale(bad_vat, 600)
    rows = query.call.rows.index_by(&:partner_name)
    expect(rows["NoVat"].anomalies).to eq([ :no_vat_number ])
    expect(rows["BadVat"].anomalies).to eq([ :invalid_vat_number ])
  end

  it "compares the listed total with the domestic sale base grids (00-03) of the year" do
    sale(acme, 1000)
    sale(create(:partner, name: "Private", vat_number: nil, country: "BE"), 100) # under threshold, not listed
    result = query.call
    expect(result.listed_total).to eq(1000)
    expect(result.grids_total).to eq(1100)
    expect(result.rows).not_to be_empty
    expect(result.exceeds_grids?).to be(false)
  end

  describe "isolation" do
    let(:rows_from_other_entity) do
      ActsAsTenant.with_tenant(create(:entity)) { create(:partner, name: "Other", vat_number: valid_vat) }
      query.call.rows
    end
    it_behaves_like "entity scoped report"
  end
end
