require 'rails_helper'

RSpec.describe Accounting::UnletterLines, type: :service do
  include_context 'with_open_fiscal_year'
  include_context 'with_pcmn_accounts'

  let(:supplier)         { create(:partner, :supplier) }
  let(:purchase_journal) { create(:journal, :purchase) }
  let(:cash_journal)     { create(:journal, :cash) }
  let(:invoice) do
    create(:invoice, :with_lines, invoice_type: :supplier, partner: supplier, fiscal_year: fiscal_year, journal: purchase_journal)
  end
  let(:payable_line) do
    Accounting::PostInvoice.call(invoice: invoice)
    invoice.reload.journal_entry.lines.find_by!(account: account_440)
  end
  let!(:cash_line) do
    payable_line
    entry = create(:journal_entry, status: :posted, journal: cash_journal, fiscal_year: fiscal_year, reference: 'CSH/0001')
    ApplicationRecord.connection.execute('SET CONSTRAINTS enforce_double_entry DEFERRED')
    create(:journal_entry_line, journal_entry: entry, account: account_440, partner: supplier, debit: payable_line.credit)
  end
  let(:lettering) do
    Accounting::LetterLines.call(lines: [ payable_line, cash_line ]).lettering
  end

  it 'removes the lettering and frees its lines' do
    lettering
    expect { described_class.call(lettering: lettering) }.to change(Accounting::Lettering, :count).by(-1)
    expect([ payable_line, cash_line ].map { |l| l.reload.lettering_id }).to all(be_nil)
  end

  it 'reopens an invoice that the lettering had paid' do
    lettering
    expect(invoice.reload).to be_paid

    expect(described_class.call(lettering: lettering)).to be_success
    expect(invoice.reload).to be_posted
  end

  it 'keeps an invoice paid when it belongs to a payment batch' do
    lettering
    settlement = create(:journal_entry, journal: cash_journal, fiscal_year: fiscal_year, reference: 'BNQ/0001')
    batch = create(:payment_batch, :executed, journal_entry: settlement)
    create(:payment_batch_line, payment_batch: batch, invoice: invoice, amount: payable_line.credit)

    expect(described_class.call(lettering: lettering)).to be_success
    expect(invoice.reload).to be_paid
  end
end
