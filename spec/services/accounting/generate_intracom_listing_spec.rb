require 'rails_helper'

RSpec.describe Accounting::GenerateIntracomListing, type: :service do
  include_context 'with_open_fiscal_year'
  include_context 'with_pcmn_accounts'

  let!(:sale_journal) { create(:journal, :sale) }
  let(:fr_partner) { create(:partner, vat_number: 'FR32123456789', country: 'FR') }

  let(:period_start) { Date.new(2025, 1, 1) }
  let(:period_end)   { Date.new(2025, 3, 31) }

  before do
    inv = create(:invoice, invoice_type: :customer, partner: fr_partner, fiscal_year: fiscal_year,
                 journal: sale_journal, vat_treatment: :intracom_goods, invoice_date: Date.new(2025, 2, 1))
    create(:invoice_line, invoice: inv, account: account_700, quantity: 1, unit_price: '1000.00', vat_rate: '21.00', position: 1)
    inv.compute_totals
    inv.save!
    Accounting::PostInvoice.call(invoice: inv)
  end

  describe '.call — chemin de succès' do
    subject(:result) do
      described_class.call(fiscal_year_id: fiscal_year.id, period_start: period_start, period_end: period_end)
    end

    it 'retourne un contexte de succès' do
      expect(result).to be_success
    end

    it 'crée un IntracomListing' do
      expect { result }.to change(Accounting::IntracomListing, :count).by(1)
    end

    it 'crée une ligne par partenaire/code avec le bon montant' do
      result
      listing = Accounting::IntracomListing.last
      line = listing.lines.first
      expect(line.partner).to eq(fr_partner)
      expect(line.code).to eq('L')
      expect(line.amount).to eq(BigDecimal('1000.00'))
    end

    it 'associe la déclaration à l année fiscale et à la période' do
      result
      listing = Accounting::IntracomListing.last
      expect(listing.fiscal_year).to eq(fiscal_year)
      expect(listing.period_start).to eq(period_start)
      expect(listing.period_end).to eq(period_end)
    end
  end

  describe '.call — sans vente intracommunautaire dans la période' do
    it 'retourne un contexte de succès sans lignes' do
      result = described_class.call(fiscal_year_id: fiscal_year.id,
                                    period_start: Date.new(2025, 4, 1), period_end: Date.new(2025, 6, 30))
      expect(result).to be_success
      expect(result[:intracom_listing].lines).to be_empty
    end
  end

  describe '.call — unexpected error' do
    it 'returns a failure context with the error message' do
      allow(ApplicationRecord).to receive(:transaction).and_raise(StandardError, 'DB connection lost')
      result = described_class.call(fiscal_year_id: fiscal_year.id, period_start: period_start, period_end: period_end)
      expect(result).to be_failure
      expect(result.message).to include('DB connection lost')
    end
  end
end
