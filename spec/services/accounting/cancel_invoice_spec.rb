require 'rails_helper'

RSpec.describe Accounting::CancelInvoice, type: :service do
  include_context 'with_open_fiscal_year'
  include_context 'with_pcmn_accounts'

  let!(:purchase_journal) { create(:journal, :purchase) }
  let(:invoice) { create(:invoice, :with_lines, invoice_type: :supplier, fiscal_year: fiscal_year, journal: purchase_journal) }

  before { Accounting::PostInvoice.call(invoice: invoice) }

  subject(:result) { described_class.call(invoice: invoice.reload) }

  describe 'success' do
    it 'succeeds' do
      expect(result).to be_success
    end

    it 'marks the invoice as cancelled and keeps its number' do
      number = invoice.reload.invoice_number
      result
      expect(invoice.reload).to be_cancelled
      expect(invoice.invoice_number).to eq(number)
    end

    it 'reverses the invoice entry' do
      entry = invoice.reload.journal_entry
      result
      expect(entry.reload).to be_reversed
      expect(entry.reversal).to be_posted
    end
  end

  describe 'failures' do
    it 'refuses a draft invoice' do
      draft = create(:invoice, :with_lines, invoice_type: :supplier, fiscal_year: fiscal_year, journal: purchase_journal)
      expect(described_class.call(invoice: draft)).to be_failure
    end

    it 'refuses a paid invoice' do
      invoice.update_columns(status: Accounting::Invoice.statuses[:paid])
      expect(result).to be_failure
    end

    it 'refuses an invoice in an active payment batch' do
      create(:payment_batch_line, invoice: invoice.reload)
      expect(result).to be_failure
      expect(invoice.reload).to be_posted
    end

    it 'refuses when the entry has lettered lines' do
      line = invoice.reload.journal_entry.lines.first
      line.update_columns(lettering_id: create(:lettering, account: line.account).id)
      expect(result).to be_failure
      expect(invoice.reload).to be_posted
    end

    it 'refuses when the fiscal year is closed and leaves everything untouched' do
      fiscal_year.update_columns(status: Accounting::FiscalYear.statuses[:closed])
      expect { result }.not_to change { Accounting::JournalEntry.count }
      expect(result).to be_failure
      expect(invoice.reload).to be_posted
    end
  end
end
