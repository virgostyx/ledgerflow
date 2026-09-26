require 'rails_helper'

RSpec.describe Accounting::ImportOpeningBalances, type: :service do
  include_context 'with_open_fiscal_year'

  let!(:misc_journal) { create(:journal, journal_type: :misc, code: 'OD', sequence_prefix: 'OD') }
  let!(:receivable)   { create(:account, code: '400000', account_class: 4, account_type: :asset, normal_balance: :debit, reconcilable: true) }
  let!(:payable)      { create(:account, code: '440000', account_class: 4, account_type: :liability, normal_balance: :credit, reconcilable: true) }
  let!(:transit)      { create(:account, code: '499000', account_class: 4, account_type: :asset, normal_balance: :debit) }
  let!(:bank)         { create(:account, code: '550000', account_class: 5, account_type: :asset, normal_balance: :debit) }
  let!(:capital)      { create(:account, code: '100000', account_class: 1, account_type: :equity, normal_balance: :credit) }
  let!(:expense)      { create(:account, code: '604000', account_class: 6, account_type: :expense, normal_balance: :debit) }

  let(:balances) do
    <<~CSV
      account_code,debit,credit
      550000,5000.00,0
      400000,1200.00,0
      440000,0,700.00
      100000,0,5500.00
    CSV
  end
  let(:invoices) do
    <<~CSV
      type,partner_name,partner_vat,number,invoice_date,due_date,open_amount
      customer,Acme SA,BE0123456749,2025-0101,2025-11-15,2025-12-15,700.00
      customer,Beta SRL,,2025-0102,2025-12-01,2025-12-31,500.00
      supplier,Fournisseur NV,BE0202239951,F-77,2025-12-10,2026-01-10,700.00
    CSV
  end
  let(:dry_run) { false }

  subject(:result) do
    described_class.call(fiscal_year: fiscal_year, balances_csv: balances, invoices_csv: invoices, dry_run: dry_run)
  end

  def net_balance(account)
    Accounting::JournalEntryLine.where(account: account).sum('debit - credit')
  end

  describe 'a valid import' do
    it 'succeeds and summarises' do
      expect(result).to be_success
      expect(result[:summary]).to include(invoices: 3, partners_created: 3)
    end

    it 'posts one entry per open invoice plus one balance entry, all opening entries in the misc journal' do
      expect { result }.to change(Accounting::JournalEntry, :count).by(4)
      entries = Accounting::JournalEntry.where(source_type: 'Accounting::OpeningBalance')
      expect(entries.count).to eq(4)
      expect(entries).to all(be_posted)
      expect(entries.map(&:journal).uniq).to eq([ misc_journal ])
      expect(entries.map(&:entry_date).uniq).to eq([ fiscal_year.start_date ])
    end

    it 'creates posted invoices without lines, linked to their own entry' do
      result
      invoice = Accounting::Invoice.find_by!(invoice_number: '2025-0101')
      expect(invoice).to be_posted
      expect(invoice.lines).to be_empty
      expect(invoice.total_incl_vat).to eq(BigDecimal('700'))
      expect(invoice.due_date).to eq(Date.new(2025, 12, 15))
      expect(invoice.invoice_date).to eq(Date.new(2025, 11, 15))
      expect(invoice.journal_entry.lines.find_by(account: receivable)).to have_attributes(
        debit: BigDecimal('700'), partner_id: invoice.partner_id, invoice_id: invoice.id
      )
      expect(invoice).to be_opening
    end

    it 'books supplier invoices on the payable account and keeps the source number as external_ref' do
      result
      invoice = Accounting::Invoice.find_by!(invoice_number: 'F-77')
      expect(invoice).to be_supplier
      expect(invoice.external_ref).to eq('F-77')
      expect(invoice.journal_entry.lines.find_by(account: payable)).to have_attributes(credit: BigDecimal('700'), invoice_id: invoice.id)
    end

    it 'leaves the ledger with the file balances and the transit account at zero' do
      result
      expect(net_balance(bank)).to eq(5000)
      expect(net_balance(receivable)).to eq(1200)
      expect(net_balance(payable)).to eq(-700)
      expect(net_balance(capital)).to eq(-5500)
      expect(net_balance(transit)).to eq(0)
    end

    it 'gives customer invoices their full remaining amount' do
      result
      expect(Accounting::Invoice.find_by!(invoice_number: '2025-0102').remaining_amount).to eq(BigDecimal('500'))
    end

    it 'shows the open items per partner in the aged balance' do
      result
      rows = Accounting::AgedBalanceQuery.new(kind: :customer, as_of: fiscal_year.start_date + 30.days).call
      expect(rows.to_h { |r| [ r.partner_name, r.total ] }).to eq('Acme SA' => 700, 'Beta SRL' => 500)
    end

    it 'reuses partners matched by VAT number, then by name (case-insensitive)' do
      by_vat  = create(:partner, name: 'Old name', vat_number: 'BE0123456749')
      by_name = create(:partner, name: 'BETA srl', vat_number: nil)
      expect(result[:summary][:partners_created]).to eq(1)
      expect(Accounting::Invoice.find_by!(invoice_number: '2025-0101').partner).to eq(by_vat)
      expect(Accounting::Invoice.find_by!(invoice_number: '2025-0102').partner).to eq(by_name)
    end

    it 'accepts semicolons and decimal commas' do
      csv = "account_code;debit;credit\n550000;5.000,00;0\n400000;1.200,00;0\n440000;0;700,00\n100000;0;5.500,00\n"
      inv = "type;partner_name;partner_vat;number;invoice_date;due_date;open_amount\n" \
            "customer;Acme SA;;A1;2025-11-15;2025-12-15;1.200,00\nsupplier;Fournisseur NV;;F1;2025-12-10;2026-01-10;700,00\n"
      res = described_class.call(fiscal_year: fiscal_year, balances_csv: csv, invoices_csv: inv)
      expect(res).to be_success
    end
  end

  describe 'settling an opening invoice' do
    let(:bank_journal) { create(:journal, :bank, default_account: bank) }
    let(:bank_account) { create(:bank_account, journal: bank_journal) }
    let(:tx)           { create(:bank_transaction, bank_account: bank_account, amount: BigDecimal('700')) }

    it 'pays it through a bank receipt, netting its open balance' do
      result
      invoice = Accounting::Invoice.find_by!(invoice_number: '2025-0101')
      booked = Accounting::BookInvoiceReceipt.call(transaction: tx, invoice: invoice, fiscal_year: fiscal_year)
      expect(booked).to be_success
      expect(invoice.reload).to be_paid
      rows = Accounting::AgedBalanceQuery.new(kind: :customer, as_of: Date.current + 1.year).call
      expect(rows.to_h { |r| [ r.partner_name, r.total ] }).to eq('Acme SA' => 0, 'Beta SRL' => 500)
    end
  end

  describe 'dry run' do
    let(:dry_run) { true }

    it 'reports the summary and writes nothing' do
      expect(result).to be_success
      expect(result[:summary]).to include(invoices: 3)
      expect(Accounting::JournalEntry.count).to eq(0)
      expect(Accounting::Invoice.count).to eq(0)
      expect(Accounting::Partner.count).to eq(0)
    end
  end

  shared_examples 'a refused import' do |message|
    it "refuses with #{message.inspect} and writes nothing" do
      expect(result).to be_failure
      expect(result[:errors].join(' ')).to match(message)
      expect(Accounting::JournalEntry.count).to eq(0)
      expect(Accounting::Invoice.count).to eq(0)
      expect(Accounting::Partner.count).to eq(0)
    end
  end

  context 'with an unbalanced file' do
    let(:balances) { "account_code,debit,credit\n550000,5000,0\n400000,1200,0\n440000,0,700\n100000,0,5000\n" }
    it_behaves_like 'a refused import', /not balanced/i
  end

  context 'with an unknown account' do
    let(:balances) { "account_code,debit,credit\n999999,100,0\n100000,0,100\n" }
    it_behaves_like 'a refused import', /999999.*unknown/i
  end

  context 'with an income statement account' do
    let(:balances) { "account_code,debit,credit\n604000,100,0\n100000,0,100\n" }
    it_behaves_like 'a refused import', /604000.*class 1 to 5/i
  end

  context 'when customer invoices do not add up to account 400000' do
    let(:invoices) { "type,partner_name,partner_vat,number,invoice_date,due_date,open_amount\ncustomer,Acme SA,,1,2025-11-15,2025-12-15,100\nsupplier,Fournisseur NV,,F1,2025-12-10,2026-01-10,700\n" }
    it_behaves_like 'a refused import', /400000.*1200.*100/
  end

  context 'when supplier invoices do not add up to account 440000' do
    let(:invoices) { "type,partner_name,partner_vat,number,invoice_date,due_date,open_amount\ncustomer,Acme SA,,1,2025-11-15,2025-12-15,1200\n" }
    it_behaves_like 'a refused import', /440000.*700.*0/
  end

  context 'with duplicate invoice numbers in the file' do
    let(:invoices) do
      "type,partner_name,partner_vat,number,invoice_date,due_date,open_amount\n" \
      "customer,Acme SA,,X1,2025-11-15,2025-12-15,600\ncustomer,Acme SA,,X1,2025-11-16,2025-12-16,600\nsupplier,Fournisseur NV,,F1,2025-12-10,2026-01-10,700\n"
    end
    it_behaves_like 'a refused import', /duplicate.*X1/i
  end

  context 'with an invoice number that already exists' do
    before { create(:invoice, :customer, invoice_number: '2025-0101', fiscal_year: fiscal_year, partner: create(:partner)) }

    it 'refuses' do
      expect(result).to be_failure
      expect(result[:errors].join(' ')).to match(/2025-0101.*already exists/i)
    end
  end

  context 'with a bad date or amount' do
    let(:invoices) do
      "type,partner_name,partner_vat,number,invoice_date,due_date,open_amount\n" \
      "customer,Acme SA,,1,not-a-date,2025-12-15,1200\nsupplier,Fournisseur NV,,F1,2025-12-10,2025-01-10,-5\n"
    end
    it_behaves_like 'a refused import', /line 2.*invoice_date/i
  end

  context 'when the fiscal year is not the first one' do
    before do
      create(:fiscal_year, year: fiscal_year.year - 1, start_date: fiscal_year.start_date - 1.year,
                           end_date: fiscal_year.start_date - 1.day, status: :closed)
    end
    it_behaves_like 'a refused import', /first fiscal year/i
  end

  context 'when the fiscal year is closed' do
    before { fiscal_year.update_columns(status: Accounting::FiscalYear.statuses[:closed]) }
    it_behaves_like 'a refused import', /open/i
  end

  context 'when the opening has already been imported' do
    it 'refuses a second import' do
      described_class.call(fiscal_year: fiscal_year, balances_csv: balances, invoices_csv: invoices)
      second = described_class.call(fiscal_year: fiscal_year, balances_csv: balances, invoices_csv: invoices)
      expect(second).to be_failure
      expect(second[:errors].join(' ')).to match(/already/i)
    end
  end

  context 'without an active misc journal' do
    before { misc_journal.update_columns(active: false) }
    it_behaves_like 'a refused import', /misc journal/i
  end
end
