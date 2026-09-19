require 'rails_helper'

RSpec.describe Accounting::BookInvoiceReceipt, type: :service do
  include_context 'with_open_fiscal_year'

  let!(:bank_gl)     { create(:account, code: '550000', label_fr: 'Banque', account_class: 5, account_type: :asset, normal_balance: :debit) }
  let!(:receivable)  { create(:account, code: '400000', label_fr: 'Clients', account_type: :asset, normal_balance: :debit) }
  let!(:bank_journal) { create(:journal, :bank, default_account: bank_gl) }
  let(:bank_account)  { create(:bank_account, journal: bank_journal) }
  let(:invoice) do
    create(:invoice, :customer, :posted, fiscal_year: fiscal_year).tap { |i| i.update_columns(total_incl_vat: BigDecimal('1210')) }
  end
  let(:tx) { create(:bank_transaction, bank_account: bank_account, amount: BigDecimal('1210')) }

  def book(transaction: tx)
    described_class.call(transaction: transaction, invoice: invoice, fiscal_year: fiscal_year)
  end

  it 'reconciles the transaction, books bank/receivable with the partner, and pays the invoice' do
    expect(book).to be_success

    expect(tx.reload).to be_reconciled
    expect(invoice.reload).to be_paid
    lines = tx.journal_entry.lines
    expect(lines.find_by(account: bank_gl).debit).to eq(BigDecimal('1210'))
    expect(lines.find_by(account: receivable)).to have_attributes(credit: BigDecimal('1210'), partner_id: invoice.partner_id)
  end

  it 'books a partial payment and leaves the invoice open with the remaining balance' do
    tx.update_columns(amount: BigDecimal('500'))

    expect(book).to be_success

    expect(tx.reload).to be_reconciled
    expect(invoice.reload).to be_posted
    expect(invoice.paid_amount).to eq(BigDecimal('500'))
    expect(invoice.remaining_amount).to eq(BigDecimal('710'))
  end

  it 'pays the invoice once successive receipts cover the total' do
    tx.update_columns(amount: BigDecimal('500'))
    book
    second = create(:bank_transaction, bank_account: bank_account, amount: BigDecimal('710'))

    expect(book(transaction: second)).to be_success

    expect(invoice.reload).to be_paid
    expect(invoice.remaining_amount).to eq(0)
  end

  it 'books an overpayment in full, pays the invoice and leaves the excess on the receivable' do
    tx.update_columns(amount: BigDecimal('1500'))

    expect(book).to be_success

    expect(invoice.reload).to be_paid
    expect(invoice.remaining_amount).to eq(0)
    expect(invoice.overpaid_amount).to eq(BigDecimal('290'))
    expect(tx.journal_entry.lines.find_by(account: receivable).credit).to eq(BigDecimal('1500'))
  end

  it 'handles an overpayment that follows a partial payment' do
    tx.update_columns(amount: BigDecimal('500'))
    book
    second = create(:bank_transaction, bank_account: bank_account, amount: BigDecimal('800'))

    expect(book(transaction: second)).to be_success

    expect(invoice.reload).to be_paid
    expect(invoice.overpaid_amount).to eq(BigDecimal('90'))
  end

  it 'refuses an invoice that is not an open customer invoice' do
    invoice.update_columns(status: Accounting::Invoice.statuses[:paid])
    expect(book).to be_failure
    expect(tx.reload).to be_pending
  end

  it 'fails cleanly, changing nothing, when the receivable account is missing' do
    receivable.destroy!

    result = nil
    expect { result = book }.not_to change(Accounting::JournalEntry, :count)
    expect(result).to be_failure
    expect(result.message).to start_with('Error')
    expect(tx.reload).to be_pending
  end

  it 'refuses a debit' do
    tx.update_columns(amount: BigDecimal('-1210'))
    expect(book).to be_failure
  end

  it 'refuses an already reconciled transaction' do
    book
    expect(book).to be_failure
  end

  context 'grouped receipt (several invoices of one partner)' do
    let(:second) do
      create(:invoice, :customer, :posted, fiscal_year: fiscal_year, partner: invoice.partner)
        .tap { |i| i.update_columns(total_incl_vat: BigDecimal('300')) }
    end
    let(:group_tx) { create(:bank_transaction, bank_account: bank_account, amount: BigDecimal('1510')) }

    def book_group(transaction: group_tx, invoices: [ invoice, second ])
      described_class.call(transaction: transaction, invoices: invoices, fiscal_year: fiscal_year)
    end

    it 'books one entry with a receivable line per invoice and pays them all' do
      expect { expect(book_group).to be_success }.to change(Accounting::JournalEntry, :count).by(1)

      lines = group_tx.reload.journal_entry.lines
      expect(lines.find_by(account: bank_gl).debit).to eq(BigDecimal('1510'))
      expect(lines.find_by(invoice_id: invoice.id).credit).to eq(BigDecimal('1210'))
      expect(lines.find_by(invoice_id: second.id).credit).to eq(BigDecimal('300'))
      expect(invoice.reload).to be_paid
      expect(second.reload).to be_paid
    end

    it 'refuses when the amount is not the sum of the balances, changing nothing' do
      group_tx.update_columns(amount: BigDecimal('1500'))

      expect { expect(book_group).to be_failure }.not_to change(Accounting::JournalEntry, :count)
      expect(invoice.reload).to be_posted
    end

    it 'refuses invoices of different partners' do
      second.update_columns(partner_id: create(:partner).id)
      expect(book_group).to be_failure
    end

    it 'refuses a group containing an invoice that is not open' do
      second.update_columns(status: Accounting::Invoice.statuses[:paid])
      expect(book_group).to be_failure
    end
  end

  context 'manual allocation (explicit amount per invoice)' do
    let(:second) do
      create(:invoice, :customer, :posted, fiscal_year: fiscal_year, partner: invoice.partner)
        .tap { |i| i.update_columns(total_incl_vat: BigDecimal('300')) }
    end
    let(:tx_1200) { create(:bank_transaction, bank_account: bank_account, amount: BigDecimal('1200')) }

    def allocate(allocations, transaction: tx_1200)
      described_class.call(transaction: transaction, allocations: allocations, fiscal_year: fiscal_year)
    end

    it 'books each amount on its invoice; a fully covered invoice is paid, the other stays open' do
      expect(allocate([ [ invoice, BigDecimal('900') ], [ second, BigDecimal('300') ] ])).to be_success

      lines = tx_1200.reload.journal_entry.lines
      expect(lines.find_by(invoice_id: invoice.id).credit).to eq(BigDecimal('900'))
      expect(lines.find_by(invoice_id: second.id).credit).to eq(BigDecimal('300'))
      expect(invoice.reload).to be_posted
      expect(invoice.remaining_amount).to eq(BigDecimal('310'))
      expect(second.reload).to be_paid
    end

    it 'lets an allocation exceed the balance, leaving a credit on the partner' do
      tx_1200.update_columns(amount: BigDecimal('1600'))

      expect(allocate([ [ invoice, BigDecimal('1210') ], [ second, BigDecimal('390') ] ])).to be_success
      expect(second.reload.overpaid_amount).to eq(BigDecimal('90'))
    end

    it 'refuses allocations that do not add up to the transaction amount' do
      expect { expect(allocate([ [ invoice, BigDecimal('900') ], [ second, BigDecimal('200') ] ])).to be_failure }
        .not_to change(Accounting::JournalEntry, :count)
      expect(tx_1200.reload).to be_pending
    end

    it 'refuses a non-positive allocation' do
      expect(allocate([ [ invoice, BigDecimal('1300') ], [ second, BigDecimal('-100') ] ])).to be_failure
    end

    it 'refuses invoices of different partners' do
      second.update_columns(partner_id: create(:partner).id)
      expect(allocate([ [ invoice, BigDecimal('900') ], [ second, BigDecimal('300') ] ])).to be_failure
    end
  end
end
