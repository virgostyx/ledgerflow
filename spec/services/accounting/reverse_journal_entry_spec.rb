require 'rails_helper'

RSpec.describe Accounting::ReverseJournalEntry, type: :service do
  include_context 'with_open_fiscal_year'

  let(:entry) { create(:journal_entry, :with_balanced_lines, fiscal_year: fiscal_year) }

  before { Accounting::PostJournalEntry.call(entry: entry) }

  subject(:result) { described_class.call(entry: entry.reload) }

  describe 'success' do
    it 'succeeds' do
      expect(result).to be_success
    end

    it 'marks the original entry as reversed' do
      expect { result }.to change { entry.reload.status }.from('posted').to('reversed')
    end

    it 'creates a posted entry linked to the original' do
      reversal = result[:reversal]
      expect(reversal).to be_posted
      expect(reversal.reversal_of_id).to eq(entry.id)
      expect(reversal.journal_id).to eq(entry.journal_id)
      expect(reversal.fiscal_year_id).to eq(entry.fiscal_year_id)
    end

    it 'swaps debit and credit on every line' do
      original = entry.lines.map { |l| [ l.account_id, l.debit, l.credit ] }
      swapped  = result[:reversal].lines.map { |l| [ l.account_id, l.credit, l.debit ] }
      expect(swapped).to match_array(original)
    end

    it 'does not copy VAT data (the VAT grids only count posted entries)' do
      entry.lines.update_all(vat_code: 1, vat_amount: 21)
      expect(result[:reversal].lines.pluck(:vat_code, :vat_amount).uniq).to eq([ [ nil, nil ] ])
    end

    it 'brings the net balance of every account back to zero' do
      result
      nets = entry.lines.map { |l| l.account.reload }.map { |a| a.balance_debit - a.balance_credit }
      expect(nets).to all(eq(0))
    end

    it 'writes an audit log on the original entry' do
      result
      expect(Accounting::AuditLog.for_record(entry).for_action('reverse_entry')).to exist
    end
  end

  describe 'failures' do
    it 'refuses a draft entry' do
      draft = create(:journal_entry, :with_balanced_lines, fiscal_year: fiscal_year)
      expect(described_class.call(entry: draft)).to be_failure
    end

    it 'refuses an already reversed entry' do
      described_class.call(entry: entry.reload)
      expect(described_class.call(entry: entry.reload)).to be_failure
    end

    it 'refuses when the fiscal year is closed' do
      fiscal_year.update_columns(status: Accounting::FiscalYear.statuses[:closed])
      expect(result).to be_failure
    end

    it 'refuses when a line is lettered' do
      lettering = create(:lettering, account: entry.lines.first.account)
      entry.lines.first.update_columns(lettering_id: lettering.id)
      expect(result).to be_failure
    end

    it 'refuses when a line has partial allocations' do
      line = entry.lines.first
      other = create(:journal_entry_line, journal_entry: entry, account: line.account, debit: 0, credit: 5)
      Accounting::LineAllocation.create!(debit_line: line, credit_line: other, amount: 1, allocated_on: Date.current)
      expect(result).to be_failure
    end

    it 'refuses an entry generated from another document' do
      entry.update_columns(source_type: 'Accounting::Invoice', source_id: 1)
      expect(result).to be_failure
    end

    it 'changes nothing when it fails' do
      entry.update_columns(source_type: 'Accounting::Invoice', source_id: 1)
      expect { result }.not_to change { Accounting::JournalEntry.count }
    end
  end
end
