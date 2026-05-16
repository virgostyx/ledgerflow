require 'rails_helper'

RSpec.describe Accounting::GenerateVatReturn, type: :service do
  include_context 'with_open_fiscal_year'

  let!(:journal) { create(:journal, :purchase) }
  let!(:account) { create(:account, code: '451000', label_fr: 'TVA à reverser') }

  let(:period_start) { Date.new(2025, 1, 1) }
  let(:period_end)   { Date.new(2025, 3, 31) }

  before do
    entry = create(:journal_entry, :draft, journal: journal, fiscal_year: fiscal_year,
                   entry_date: Date.new(2025, 2, 15))
    ApplicationRecord.connection.execute('SET CONSTRAINTS enforce_double_entry DEFERRED')
    create(:journal_entry_line, journal_entry: entry, account: account,
           debit: BigDecimal('1000.00'), credit: BigDecimal('0'),
           vat_code: 1, vat_amount: BigDecimal('210.00'))
    entry.post!
  end

  describe '.call — chemin de succès' do
    subject(:result) do
      described_class.call(
        fiscal_year_id: fiscal_year.id,
        period_start:   period_start,
        period_end:     period_end,
        period_type:    :quarterly
      )
    end

    it 'retourne un contexte de succès' do
      expect(result).to be_success
    end

    it 'crée une VatDeclaration' do
      expect { result }.to change(Accounting::VatDeclaration, :count).by(1)
    end

    it 'stocke les grilles calculées' do
      result
      decl = Accounting::VatDeclaration.last
      expect(decl.grids['01']).to eq('210.00')
    end

    it 'associe la déclaration à l année fiscale' do
      result
      decl = Accounting::VatDeclaration.last
      expect(decl.fiscal_year).to eq(fiscal_year)
    end

    it 'définit la période correctement' do
      result
      decl = Accounting::VatDeclaration.last
      expect(decl.period_start).to eq(period_start)
      expect(decl.period_end).to  eq(period_end)
      expect(decl.period_type).to eq('quarterly')
    end

    it 'expose la déclaration dans le contexte' do
      expect(result[:vat_declaration]).to be_a(Accounting::VatDeclaration)
    end
  end

  describe '.call — sans lignes TVA dans la période' do
    subject(:result) do
      described_class.call(
        fiscal_year_id: fiscal_year.id,
        period_start:   Date.new(2025, 4, 1),
        period_end:     Date.new(2025, 6, 30),
        period_type:    :quarterly
      )
    end

    it 'retourne un contexte de succès avec grilles vides' do
      expect(result).to be_success
      expect(result[:vat_declaration].grids).to eq({})
    end
  end
end
