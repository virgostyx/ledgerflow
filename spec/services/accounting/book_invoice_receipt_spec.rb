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

  it 'refuses an overpayment, changing nothing' do
    tx.update_columns(amount: BigDecimal('1500'))

    expect { expect(book).to be_failure }.not_to change(Accounting::JournalEntry, :count)
    expect(tx.reload).to be_pending
    expect(invoice.reload).to be_posted
  end

  it 'refuses a receipt above what remains after a partial payment' do
    tx.update_columns(amount: BigDecimal('500'))
    book
    too_much = create(:bank_transaction, bank_account: bank_account, amount: BigDecimal('800'))

    expect(book(transaction: too_much)).to be_failure
  end

  it 'refuses an invoice that is not an open customer invoice' do
    invoice.update_columns(status: Accounting::Invoice.statuses[:paid])
    expect(book).to be_failure
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
end
