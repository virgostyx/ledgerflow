require 'rails_helper'

RSpec.describe Accounting::IntracomListingQuery, type: :query do
  include_context 'with_open_fiscal_year'
  include_context 'with_pcmn_accounts'

  let!(:sale_journal) { create(:journal, :sale) }
  let(:fr_partner) { create(:partner, vat_number: 'FR32123456789', country: 'FR') }
  let(:de_partner) { create(:partner, vat_number: 'DE123456789', country: 'DE') }

  def post_sale(partner:, vat_treatment:, unit_price:, invoice_date: Date.new(2025, 2, 15))
    inv = create(:invoice, invoice_type: :customer, partner: partner, fiscal_year: fiscal_year,
                 journal: sale_journal, vat_treatment: vat_treatment, invoice_date: invoice_date)
    create(:invoice_line, invoice: inv, account: account_700, quantity: 1, unit_price: unit_price, vat_rate: '21.00', position: 1)
    inv.compute_totals
    inv.save!
    Accounting::PostInvoice.call(invoice: inv)
  end

  describe '.call' do
    it "déduit les notes de crédit du total du partenaire" do
      original = post_sale(partner: fr_partner, vat_treatment: :intracom_goods, unit_price: '1000.00').invoice
      note = create(:invoice, invoice_type: :customer, partner: fr_partner, fiscal_year: fiscal_year,
                    journal: sale_journal, vat_treatment: :intracom_goods, invoice_date: Date.new(2025, 2, 20),
                    document_type: :credit_note, credited_invoice: original)
      create(:invoice_line, invoice: note, account: account_700, quantity: 1, unit_price: '300.00',
             vat_rate: '21.00', position: 1)
      Accounting::PostInvoice.call(invoice: note)

      result = described_class.call(fiscal_year_id: fiscal_year.id,
                                    period_start: Date.new(2025, 1, 1), period_end: Date.new(2025, 3, 31))
      expect(result[[ fr_partner.id, 'L' ]]).to eq(BigDecimal('700.00'))
    end

    it "additionne les livraisons de biens intracommunautaires par partenaire, avec le code L" do
      post_sale(partner: fr_partner, vat_treatment: :intracom_goods, unit_price: '1000.00')
      post_sale(partner: fr_partner, vat_treatment: :intracom_goods, unit_price: '500.00')

      result = described_class.call(fiscal_year_id: fiscal_year.id,
                                    period_start: Date.new(2025, 1, 1), period_end: Date.new(2025, 3, 31))
      expect(result[[ fr_partner.id, 'L' ]]).to eq(BigDecimal('1500.00'))
    end

    it "sépare les services (code S) des biens (code L) pour un même partenaire" do
      post_sale(partner: de_partner, vat_treatment: :intracom_goods, unit_price: '1000.00')
      post_sale(partner: de_partner, vat_treatment: :intracom_services, unit_price: '300.00')

      result = described_class.call(fiscal_year_id: fiscal_year.id,
                                    period_start: Date.new(2025, 1, 1), period_end: Date.new(2025, 3, 31))
      expect(result[[ de_partner.id, 'L' ]]).to eq(BigDecimal('1000.00'))
      expect(result[[ de_partner.id, 'S' ]]).to eq(BigDecimal('300.00'))
    end

    it "exclut les factures hors période" do
      post_sale(partner: fr_partner, vat_treatment: :intracom_goods, unit_price: '1000.00',
                invoice_date: Date.new(2025, 6, 1))

      result = described_class.call(fiscal_year_id: fiscal_year.id,
                                    period_start: Date.new(2025, 1, 1), period_end: Date.new(2025, 3, 31))
      expect(result).to be_empty
    end

    it "exclut les ventes domestiques et exemptées/exportées" do
      post_sale(partner: fr_partner, vat_treatment: :domestic, unit_price: '1000.00')
      post_sale(partner: fr_partner, vat_treatment: :exempt, unit_price: '400.00')

      result = described_class.call(fiscal_year_id: fiscal_year.id,
                                    period_start: Date.new(2025, 1, 1), period_end: Date.new(2025, 3, 31))
      expect(result).to be_empty
    end
  end
end
