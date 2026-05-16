require 'rails_helper'

RSpec.describe Accounting::VatGridQuery, type: :query do
  include_context 'with_open_fiscal_year'

  let!(:journal)  { create(:journal, :purchase) }
  let!(:account)  { create(:account, code: '451000', label_fr: 'TVA à reverser') }
  let!(:account2) { create(:account, code: '411000', label_fr: 'TVA à récupérer') }

  let(:period_start) { Date.new(2025, 1, 1) }
  let(:period_end)   { Date.new(2025, 3, 31) }

  def create_posted_entry_with_vat(entry_date:, vat_code:, vat_amount:, debit: true)
    entry = create(:journal_entry, :draft, journal: journal, fiscal_year: fiscal_year,
                   entry_date: entry_date)
    ApplicationRecord.connection.execute('SET CONSTRAINTS enforce_double_entry DEFERRED')
    account_used = debit ? account : account2
    create(:journal_entry_line, journal_entry: entry,
           account: account_used,
           debit: debit ? BigDecimal('1000.00') : BigDecimal('0'),
           credit: debit ? BigDecimal('0') : BigDecimal('1000.00'),
           vat_code: vat_code, vat_amount: vat_amount)
    entry.post!
    entry
  end

  describe '.call' do
    context 'avec des lignes TVA dans la période' do
      before do
        create_posted_entry_with_vat(entry_date: Date.new(2025, 1, 15),
                                     vat_code: 1, vat_amount: BigDecimal('210.00'))
        create_posted_entry_with_vat(entry_date: Date.new(2025, 2, 20),
                                     vat_code: 1, vat_amount: BigDecimal('105.00'))
        create_posted_entry_with_vat(entry_date: Date.new(2025, 3, 10),
                                     vat_code: 54, vat_amount: BigDecimal('315.00'),
                                     debit: false)
      end

      subject(:result) do
        described_class.call(fiscal_year_id: fiscal_year.id,
                             period_start: period_start,
                             period_end: period_end)
      end

      it 'retourne un hash indexé par code grille à deux chiffres' do
        expect(result).to be_a(Hash)
        expect(result.keys).to include('01', '54')
      end

      it 'additionne les montants pour le même code' do
        expect(result['01']).to eq(BigDecimal('315.00'))
      end

      it 'retourne le bon montant pour un code unique' do
        expect(result['54']).to eq(BigDecimal('315.00'))
      end

      it 'ne retourne pas les codes à zéro ou absents' do
        expect(result.keys).not_to include('02', '03')
      end
    end

    context 'hors période' do
      before do
        create_posted_entry_with_vat(entry_date: Date.new(2024, 12, 31),
                                     vat_code: 1, vat_amount: BigDecimal('500.00'))
      end

      it 'retourne un hash vide' do
        result = described_class.call(fiscal_year_id: fiscal_year.id,
                                      period_start: period_start,
                                      period_end: period_end)
        expect(result).to eq({})
      end
    end

    context 'lignes sans vat_code' do
      before do
        entry = create(:journal_entry, :draft, journal: journal, fiscal_year: fiscal_year,
                       entry_date: Date.new(2025, 1, 15))
        ApplicationRecord.connection.execute('SET CONSTRAINTS enforce_double_entry DEFERRED')
        create(:journal_entry_line, journal_entry: entry, account: account,
               debit: BigDecimal('500.00'), credit: BigDecimal('0'),
               vat_code: nil, vat_amount: nil)
        entry.post!
      end

      it 'ignore les lignes sans vat_code' do
        result = described_class.call(fiscal_year_id: fiscal_year.id,
                                      period_start: period_start,
                                      period_end: period_end)
        expect(result).to eq({})
      end
    end

    context 'écritures en brouillon exclues' do
      before do
        entry = create(:journal_entry, :draft, journal: journal, fiscal_year: fiscal_year,
                       entry_date: Date.new(2025, 2, 1))
        ApplicationRecord.connection.execute('SET CONSTRAINTS enforce_double_entry DEFERRED')
        create(:journal_entry_line, journal_entry: entry, account: account,
               debit: BigDecimal('1000.00'), credit: BigDecimal('0'),
               vat_code: 1, vat_amount: BigDecimal('210.00'))
      end

      it 'exclut les écritures non validées' do
        result = described_class.call(fiscal_year_id: fiscal_year.id,
                                      period_start: period_start,
                                      period_end: period_end)
        expect(result).to eq({})
      end
    end
  end
end
