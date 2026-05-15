require 'rails_helper'

RSpec.describe Accounting::Actions::UpdateAccountBalances, type: :service do
  include_context 'with_open_fiscal_year'

  let(:entry) { create(:journal_entry, :with_balanced_lines, fiscal_year: fiscal_year) }

  describe '.execute' do
    it 'incrémente balance_debit du compte débité' do
      debit_line = entry.lines.find { |l| l.debit > 0 }
      expect {
        ctx = LightService::Context.make(entry: entry)
        described_class.execute(ctx)
      }.to change { debit_line.account.reload.balance_debit }
        .by(debit_line.debit)
    end

    it 'incrémente balance_credit du compte crédité' do
      credit_line = entry.lines.find { |l| l.credit > 0 }
      expect {
        ctx = LightService::Context.make(entry: entry)
        described_class.execute(ctx)
      }.to change { credit_line.account.reload.balance_credit }
        .by(credit_line.credit)
    end
  end
end
