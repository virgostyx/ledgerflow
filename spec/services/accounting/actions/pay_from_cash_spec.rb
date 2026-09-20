require 'rails_helper'

RSpec.describe Accounting::PostInvoice, 'paid from cash', type: :service do
  include_context 'with_open_fiscal_year'
  include_context 'with_pcmn_accounts'

  let!(:purchase_journal) { create(:journal, :purchase) }
  let!(:cash_journal)     { create(:journal, :cash) }
  let(:invoice) do
    create(:invoice, :with_lines, invoice_type: :supplier, fiscal_year: fiscal_year,
                                  journal: purchase_journal, cash_journal: cash_journal)
  end

  subject(:result) { described_class.call(invoice: invoice) }

  it 'marks the invoice as paid' do
    expect(result).to be_success
    expect(invoice.reload).to be_paid
  end

  it 'books Dr 440000 / Cr cash account in the cash journal, dated on the invoice date' do
    result
    entry = Accounting::JournalEntry.find_by!(journal: cash_journal)
    expect(entry).to be_posted
    expect(entry.entry_date).to eq(invoice.invoice_date)
    debit  = entry.lines.find_by!(account: account_440)
    credit = entry.lines.find_by!(account: cash_journal.default_account)
    expect(debit.debit).to eq(invoice.reload.total_incl_vat)
    expect(debit.partner).to eq(invoice.partner)
    expect(credit.credit).to eq(invoice.total_incl_vat)
  end

  it 'letters the invoice payable line with the payment line' do
    result
    lines = Accounting::JournalEntryLine.where(account: account_440)
    expect(lines.count).to eq(2)
    expect(lines.map(&:lettering_id).uniq.size).to eq(1)
    expect(lines.first.lettering_id).to be_present
  end

  it 'does nothing extra without a cash journal' do
    invoice.update!(cash_journal: nil)
    expect { result }.not_to change { Accounting::JournalEntry.where(journal: cash_journal).count }
    expect(invoice.reload).to be_posted
  end

  it 'rolls the whole posting back if lettering fails' do
    allow(Accounting::LetterLines).to receive(:call)
      .and_return(LightService::Context.make.tap { |c| c.fail!('boom') })
    expect(result).to be_failure
    expect(invoice.reload).to be_draft
    expect(Accounting::JournalEntry.count).to eq(0)
  end
end
