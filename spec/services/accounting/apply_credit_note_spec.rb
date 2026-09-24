require 'rails_helper'

RSpec.describe Accounting::ApplyCreditNote, type: :service do
  include_context 'with_open_fiscal_year'
  include_context 'with_pcmn_accounts'

  let!(:sale_journal)     { create(:journal, :sale) }
  let!(:purchase_journal) { create(:journal, :purchase) }
  let(:partner)           { create(:partner) }

  def post(type:, account:, unit_price:, credited: nil)
    inv = create(:invoice, invoice_type: type, partner: partner, fiscal_year: fiscal_year,
                 journal: type == :customer ? sale_journal : purchase_journal,
                 document_type: credited ? :credit_note : :invoice, credited_invoice: credited)
    create(:invoice_line, invoice: inv, account: account, quantity: 1, unit_price: unit_price, vat_rate: '21.00', position: 1)
    Accounting::PostInvoice.call(invoice: inv).invoice.reload
  end

  { customer: :account_700, supplier: :account_604 }.each do |type, account_name|
    context "on a #{type} invoice" do
      let(:account)  { send(account_name) }
      let!(:original) { post(type: type, account: account, unit_price: '1000.00') }

      it 'settles both documents when the credit note covers the whole invoice' do
        note = post(type: type, account: account, unit_price: '1000.00', credited: original)
        result = described_class.call(credit_note: note)

        expect(result).to be_success
        expect(original.reload).to be_paid
        expect(note.reload).to be_paid
      end

      it 'leaves the invoice partially paid when the credit note is partial' do
        note = post(type: type, account: account, unit_price: '400.00', credited: original)
        described_class.call(credit_note: note)

        expect(note.reload).to be_paid
        expect(original.reload).to be_partially_paid
        expect(Accounting::LineAllocation.sum(:amount)).to eq(BigDecimal('484.00'))
      end
    end
  end

  it 'fails for a credit note without a credited invoice' do
    note = post(type: :customer, account: account_700, unit_price: '100.00')
    note.update_columns(document_type: Accounting::Invoice.document_types[:credit_note])

    expect(described_class.call(credit_note: note)).to be_failure
  end

  it 'fails when the credit note has already been applied' do
    original = post(type: :customer, account: account_700, unit_price: '1000.00')
    note = post(type: :customer, account: account_700, unit_price: '400.00', credited: original)
    described_class.call(credit_note: note)

    expect(described_class.call(credit_note: note)).to be_failure
  end

  it 'refuses to apply when receipts were already booked on the invoice, leaving the credit note open' do
    original = post(type: :customer, account: account_700, unit_price: '1000.00')
    note = post(type: :customer, account: account_700, unit_price: '100.00', credited: original)
    receipt = create(:journal_entry, journal: create(:journal, :cash), fiscal_year: fiscal_year, status: :draft)
    ApplicationRecord.connection.execute('SET CONSTRAINTS enforce_double_entry DEFERRED')
    create(:journal_entry_line, journal_entry: receipt, account: account_400, partner: partner,
           invoice: original, credit: BigDecimal('1210'), debit: BigDecimal('0'))
    receipt.update_columns(status: Accounting::JournalEntry.statuses[:posted])

    result = described_class.call(credit_note: note)

    expect(result).to be_failure
    expect(Accounting::LineAllocation.count).to eq(0)
    expect(note.reload).to be_posted
  end
end
