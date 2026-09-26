require 'rails_helper'

RSpec.describe 'Posting credit notes', type: :service do
  include_context 'with_open_fiscal_year'
  include_context 'with_pcmn_accounts'

  let!(:purchase_journal) { create(:journal, :purchase) }
  let!(:sale_journal)     { create(:journal, :sale) }
  let(:partner)           { create(:partner) }

  def build_and_post(type:, account:, unit_price:, vat_rate: '21.00', document_type: :invoice, credited: nil,
                     vat_treatment: :domestic, invoice_partner: partner, quantity: 1)
    inv = create(:invoice, invoice_type: type, partner: invoice_partner, fiscal_year: fiscal_year,
                 journal: type == :customer ? sale_journal : purchase_journal,
                 vat_treatment: vat_treatment, document_type: document_type, credited_invoice: credited)
    create(:invoice_line, invoice: inv, account: account, quantity: quantity, unit_price: unit_price,
           vat_rate: vat_rate, position: 1)
    inv.compute_totals
    inv.save!
    Accounting::PostInvoice.call(invoice: inv)
    inv.reload
  end

  def balanced?(entry)
    entry.lines.sum(:debit) == entry.lines.sum(:credit)
  end

  describe 'customer credit note (domestic)' do
    let(:original) { build_and_post(type: :customer, account: account_700, unit_price: '1000.00') }
    subject(:note) do
      build_and_post(type: :customer, account: account_700, unit_price: '400.00',
                     document_type: :credit_note, credited: original)
    end

    it 'posts and is numbered from the sales journal sequence' do
      expect(note).to be_posted
      expect(note.invoice_number).to be_present
    end

    it 'credits the receivable with the total incl. VAT' do
      line = note.journal_entry.lines.find { |l| l.account == account_400 }
      expect([ line.debit, line.credit ]).to eq([ BigDecimal('0'), BigDecimal('484.00') ])
    end

    it 'debits revenue and output VAT' do
      entry = note.journal_entry
      revenue = entry.lines.find { |l| l.account == account_700 }
      vat     = entry.lines.find { |l| l.account == account_451 }
      expect(revenue.debit).to eq(BigDecimal('400.00'))
      expect(vat.debit).to eq(BigDecimal('84.00'))
    end

    it 'reports the base in grid 49 and the VAT in grid 64, both positive' do
      entry = note.journal_entry
      revenue = entry.lines.find { |l| l.account == account_700 }
      vat     = entry.lines.find { |l| l.account == account_451 }
      expect([ revenue.vat_code, revenue.vat_amount ]).to eq([ 49, BigDecimal('400.00') ])
      expect([ vat.vat_code, vat.vat_amount ]).to eq([ 64, BigDecimal('84.00') ])
    end

    it 'is balanced' do
      expect(balanced?(note.journal_entry)).to be true
    end

    it 'leaves grids 03 and 54 untouched and fills 49 and 64' do
      original; note
      grids = Accounting::VatGridQuery.call(fiscal_year_id: fiscal_year.id,
                                            period_start: Date.current.beginning_of_year, period_end: Date.current.end_of_year)
      expect(grids.slice('03', '54', '49', '64')).to eq('03' => 1000, '54' => 210, '49' => 400, '64' => 84)
    end
  end

  describe 'customer credit note on an intracommunity sale' do
    let(:eu_partner) { create(:partner, vat_number: 'FR32123456789', country: 'FR') }
    let(:original) do
      build_and_post(type: :customer, account: account_700, unit_price: '1000.00',
                     vat_treatment: :intracom_goods, invoice_partner: eu_partner)
    end
    subject(:note) do
      build_and_post(type: :customer, account: account_700, unit_price: '400.00',
                     vat_treatment: :intracom_goods, invoice_partner: eu_partner,
                     document_type: :credit_note, credited: original)
    end

    it 'reports the base in grid 48 (credit notes on grids 44 and 46)' do
      line = note.journal_entry.lines.find { |l| l.account == account_700 }
      expect([ line.vat_code, line.vat_amount ]).to eq([ 48, BigDecimal('400.00') ])
    end
  end

  describe 'supplier credit note (domestic)' do
    let(:original) { build_and_post(type: :supplier, account: account_604, unit_price: '1000.00') }
    subject(:note) do
      build_and_post(type: :supplier, account: account_604, unit_price: '400.00',
                     document_type: :credit_note, credited: original)
    end

    it 'debits the payable and credits expense and recoverable VAT' do
      entry = note.journal_entry
      expect(entry.lines.find { |l| l.account == account_440 }.debit).to eq(BigDecimal('484.00'))
      expect(entry.lines.find { |l| l.account == account_604 }.credit).to eq(BigDecimal('400.00'))
      expect(entry.lines.find { |l| l.account == account_411 }.credit).to eq(BigDecimal('84.00'))
    end

    it 'nets the base in grid 81 and reports the VAT to reverse in grid 63' do
      entry = note.journal_entry
      expense = entry.lines.find { |l| l.account == account_604 }
      vat     = entry.lines.find { |l| l.account == account_411 }
      expect([ expense.vat_code, expense.vat_amount ]).to eq([ 81, BigDecimal('-400.00') ])
      expect([ vat.vat_code, vat.vat_amount ]).to eq([ 63, BigDecimal('84.00') ])
    end

    it 'fills grid 85 with the base and leaves grid 59 as deducted on the invoice' do
      original; note
      grids = Accounting::VatGridQuery.call(fiscal_year_id: fiscal_year.id,
                                            period_start: Date.current.beginning_of_year, period_end: Date.current.end_of_year)
      expect(grids.slice('81', '85', '59', '63')).to eq('81' => 600, '85' => 400, '59' => 210, '63' => 84)
    end

    it 'is balanced' do
      expect(balanced?(note.journal_entry)).to be true
    end
  end

  describe 'supplier credit note with a prorata' do
    before { entity.update!(vat_prorata_rate: '50.00') }
    let(:original) { build_and_post(type: :supplier, account: account_604, unit_price: '1000.00') }
    subject(:note) do
      build_and_post(type: :supplier, account: account_604, unit_price: '400.00',
                     document_type: :credit_note, credited: original)
    end

    it 'nets the non-deductible VAT in 81 but keeps it out of grid 85' do
      original; note
      grids = Accounting::VatGridQuery.call(fiscal_year_id: fiscal_year.id,
                                            period_start: Date.current.beginning_of_year, period_end: Date.current.end_of_year)
      expect(grids.slice('81', '85', '63')).to eq('81' => 1000 + 105 - 400 - 42, '85' => 400, '63' => 42)
    end
  end

  describe 'supplier credit note under reverse charge with a prorata' do
    let(:eu_partner) { create(:partner, vat_number: 'FR32123456789', country: 'FR') }
    before { entity.update!(vat_prorata_rate: '50.00') }

    let(:original) do
      build_and_post(type: :supplier, account: account_604, unit_price: '1000.00',
                     vat_treatment: :intracom_services, invoice_partner: eu_partner)
    end
    subject(:note) do
      build_and_post(type: :supplier, account: account_604, unit_price: '1000.00',
                     vat_treatment: :intracom_services, invoice_partner: eu_partner,
                     document_type: :credit_note, credited: original)
    end

    it 'debits the self-assessed VAT and credits the deductible and non-deductible shares' do
      entry = note.journal_entry
      expect(entry.lines.find { |l| l.account == account_451 }.debit).to eq(BigDecimal('210.00'))
      expect(entry.lines.find { |l| l.account == account_411 }.credit).to eq(BigDecimal('105.00'))
      expect(entry.lines.find { |l| l.account == account_640400 }.credit).to eq(BigDecimal('105.00'))
    end

    it 'is balanced' do
      expect(balanced?(note.journal_entry)).to be true
    end

    it 'regularizes in grids 62 (due VAT recovered) and 61 (deduction reversed), not in 55/59' do
      entry = note.journal_entry
      due        = entry.lines.find { |l| l.account == account_451 }
      deductible = entry.lines.find { |l| l.account == account_411 }
      expect([ due.vat_code, due.vat_amount ]).to eq([ 62, BigDecimal('210.00') ])
      expect([ deductible.vat_code, deductible.vat_amount ]).to eq([ 61, BigDecimal('105.00') ])
    end

    it 'reports the base in grid 84 and nets grid 88 to zero' do
      original; note
      grids = Accounting::VatGridQuery.call(fiscal_year_id: fiscal_year.id,
                                            period_start: Date.current.beginning_of_year, period_end: Date.current.end_of_year)
      expect(grids.slice('88', '84', '81', '55')).to eq('88' => 0, '84' => 1000, '81' => 0, '55' => 210)
    end
  end

  describe 'credit note on a foreign-currency invoice' do
    let(:original) do
      inv = create(:invoice, invoice_type: :customer, partner: partner, fiscal_year: fiscal_year,
                   journal: sale_journal, currency: 'USD', exchange_rate: BigDecimal('0.9'))
      create(:invoice_line, invoice: inv, account: account_700, quantity: 1, unit_price: '1000.00',
             vat_rate: '21.00', position: 1)
      inv.compute_totals
      inv.save!
      Accounting::PostInvoice.call(invoice: inv)
      inv.reload
    end

    it 'keeps the original currency and rate on the credit note lines' do
      note = create(:invoice, invoice_type: :customer, partner: partner, fiscal_year: fiscal_year,
                    journal: sale_journal, currency: 'USD', exchange_rate: BigDecimal('0.9'),
                    document_type: :credit_note, credited_invoice: original)
      create(:invoice_line, invoice: note, account: account_700, quantity: 1, unit_price: '100.00',
             vat_rate: '21.00', position: 1)
      Accounting::PostInvoice.call(invoice: note)
      line = note.reload.journal_entry.lines.find { |l| l.account == account_400 }
      expect(line.credit).to eq(BigDecimal('108.90')) # 121 USD * 0.9
      expect(line.currency).to eq('USD')
    end
  end

  describe 'credited amount cap' do
    let(:original) { build_and_post(type: :customer, account: account_700, unit_price: '1000.00') }

    it 'refuses a credit note above the credited invoice total' do
      note = build_and_post(type: :customer, account: account_700, unit_price: '1001.00',
                            document_type: :credit_note, credited: original)
      expect(note).to be_draft
    end

    it 'refuses a second credit note that would exceed what remains to credit' do
      build_and_post(type: :customer, account: account_700, unit_price: '700.00',
                     document_type: :credit_note, credited: original)
      second = build_and_post(type: :customer, account: account_700, unit_price: '400.00',
                              document_type: :credit_note, credited: original)
      expect(second).to be_draft
    end

    it 'accepts credit notes up to the invoice total' do
      build_and_post(type: :customer, account: account_700, unit_price: '700.00',
                     document_type: :credit_note, credited: original)
      second = build_and_post(type: :customer, account: account_700, unit_price: '300.00',
                              document_type: :credit_note, credited: original)
      expect(second).to be_posted
    end
  end
end
