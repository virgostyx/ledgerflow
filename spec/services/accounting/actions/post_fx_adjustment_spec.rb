require 'rails_helper'

RSpec.describe Accounting::Actions::PostFxAdjustment, type: :service do
  include_context 'with_open_fiscal_year'
  include_context 'with_pcmn_accounts'

  let!(:misc_journal) { create(:journal) }
  let(:supplier_partner) { create(:partner, :supplier) }

  def line(account:, debit: 0, credit: 0, partner: nil, currency: 'EUR')
    entry = create(:journal_entry, status: :posted, journal: misc_journal, fiscal_year: fiscal_year)
    ApplicationRecord.connection.execute('SET CONSTRAINTS enforce_double_entry DEFERRED')
    create(:journal_entry_line, journal_entry: entry, account: account, partner: partner,
           debit: BigDecimal(debit.to_s), credit: BigDecimal(credit.to_s), currency: currency)
  end

  describe 'a pure EUR group (no foreign-currency line)' do
    it 'is a no-op even when unbalanced' do
      a = line(account: account_400, debit: 100, partner: supplier_partner)
      b = line(account: account_400, credit: 90, partner: supplier_partner)

      ctx = LightService::Context.make(lines: [ a, b ])
      described_class.execute(ctx)

      expect(ctx).to be_success
      expect(ctx.lines).to eq([ a, b ])
      expect(Accounting::JournalEntry.count).to eq(2)
    end
  end

  describe 'a foreign-currency group that already balances (rate unchanged)' do
    it 'is a no-op' do
      a = line(account: account_400, debit: 100, partner: supplier_partner, currency: 'USD')
      b = line(account: account_400, credit: 100, partner: supplier_partner)

      ctx = LightService::Context.make(lines: [ a, b ])
      described_class.execute(ctx)

      expect(ctx).to be_success
      expect(ctx.lines).to eq([ a, b ])
    end
  end

  describe 'a foreign-currency invoice paid for more EUR than invoiced (gain)' do
    it 'posts a gain to 751100 and tops up the trade account to balance' do
      invoice_line = line(account: account_400, debit: 920, partner: supplier_partner, currency: 'USD')
      payment_line = line(account: account_400, credit: 950, partner: supplier_partner)

      ctx = LightService::Context.make(lines: [ invoice_line, payment_line ])
      described_class.execute(ctx)

      expect(ctx).to be_success
      expect(ctx.lines.size).to eq(3)
      adjustment_line = (ctx.lines - [ invoice_line, payment_line ]).first
      expect(adjustment_line.account).to eq(account_400)
      expect(adjustment_line.debit).to eq(BigDecimal('30.00'))

      gain_line = Accounting::JournalEntryLine.find_by(account: account_751100)
      expect(gain_line.credit).to eq(BigDecimal('30.00'))
    end
  end

  describe 'a foreign-currency invoice paid for less EUR than invoiced (loss)' do
    it 'posts a loss to 651200 and tops up the trade account to balance' do
      invoice_line = line(account: account_400, debit: 920, partner: supplier_partner, currency: 'USD')
      payment_line = line(account: account_400, credit: 900, partner: supplier_partner)

      ctx = LightService::Context.make(lines: [ invoice_line, payment_line ])
      described_class.execute(ctx)

      expect(ctx).to be_success
      adjustment_line = (ctx.lines - [ invoice_line, payment_line ]).first
      expect(adjustment_line.account).to eq(account_400)
      expect(adjustment_line.credit).to eq(BigDecimal('20.00'))

      loss_line = Accounting::JournalEntryLine.find_by(account: account_651200)
      expect(loss_line.debit).to eq(BigDecimal('20.00'))
    end
  end
end
