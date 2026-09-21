require 'rails_helper'

RSpec.describe Accounting::LetterLines, type: :service do
  include_context 'with_open_fiscal_year'
  include_context 'with_pcmn_accounts'

  let(:supplier) { create(:partner, :supplier) }
  let(:other)    { create(:partner, :supplier) }
  let(:od)       { create(:journal, :cash) }

  # A posted one-sided entry pair is enough for lettering: the double-entry check is deferred, as in the factories.
  def line(account:, debit: 0, credit: 0, partner: nil, status: :posted)
    entry = create(:journal_entry, status: status, journal: od, fiscal_year: fiscal_year)
    ApplicationRecord.connection.execute('SET CONSTRAINTS enforce_double_entry DEFERRED')
    create(:journal_entry_line, journal_entry: entry, account: account, partner: partner,
           debit: BigDecimal(debit.to_s), credit: BigDecimal(credit.to_s))
  end

  describe 'a balanced group' do
    let!(:credit_line) { line(account: account_440, credit: 121, partner: supplier) }
    let!(:debit_line)  { line(account: account_440, debit: 121, partner: supplier) }
    subject(:result)   { described_class.call(lines: [ credit_line, debit_line ]) }

    it 'succeeds and creates one lettering' do
      expect { result }.to change(Accounting::Lettering, :count).by(1)
      expect(result).to be_success
    end

    it 'stamps every line with the same lettering' do
      result
      letterings = [ credit_line, debit_line ].map { |l| l.reload.lettering }
      expect(letterings.uniq.size).to eq(1)
      expect(letterings.first).to have_attributes(account: account_440, partner: supplier, code: 'AA',
                                                  lettered_on: Date.current)
    end

    it 'gives the next code to the next group on the same account' do
      result
      a = line(account: account_440, credit: 10, partner: supplier)
      b = line(account: account_440, debit: 10, partner: supplier)
      described_class.call(lines: [ a, b ])
      expect(a.reload.lettering.code).to eq('AB')
    end

    it 'balances across several lines' do
      third = line(account: account_440, debit: 21, partner: supplier)
      fourth = line(account: account_440, credit: 21, partner: supplier)
      expect(described_class.call(lines: [ credit_line, debit_line, third, fourth ])).to be_success
    end
  end

  describe 'refusals (nothing is written)' do
    def expect_refusal(lines, message)
      result = nil
      expect { result = described_class.call(lines: lines) }.not_to change(Accounting::Lettering, :count)
      expect(result).to be_failure
      expect(result.message).to match(message)
      expect(lines.map { |l| l.reload.lettering_id }).to all(be_nil)
    end

    it 'refuses fewer than two lines' do
      expect_refusal([ line(account: account_440, credit: 5, partner: supplier) ], /at least two/i)
    end

    it 'refuses an unbalanced group' do
      expect_refusal([ line(account: account_440, credit: 121, partner: supplier),
                       line(account: account_440, debit: 100, partner: supplier) ], /balance/i)
    end

    it 'refuses lines from different accounts' do
      expect_refusal([ line(account: account_440, credit: 50, partner: supplier),
                       line(account: account_570, debit: 50) ], /same account/i)
    end

    it 'refuses different partners on a third-party account' do
      expect_refusal([ line(account: account_440, credit: 50, partner: supplier),
                       line(account: account_440, debit: 50, partner: other) ], /same partner/i)
    end

    it 'refuses a line that is already lettered' do
      a = line(account: account_440, credit: 50, partner: supplier)
      b = line(account: account_440, debit: 50, partner: supplier)
      described_class.call(lines: [ a, b ])
      c = line(account: account_440, credit: 50, partner: supplier)
      result = nil
      expect { result = described_class.call(lines: [ a.reload, c ]) }.not_to change(Accounting::Lettering, :count)
      expect(result).to be_failure
      expect(result.message).to match(/already lettered/i)
      expect(c.reload.lettering_id).to be_nil
    end

    it 'refuses lines of a draft entry' do
      expect_refusal([ line(account: account_570, credit: 50, status: :draft),
                       line(account: account_570, debit: 50) ], /posted/i)
    end
  end

  describe 'lines with partial allocations' do
    it 'refuses to letter a partly allocated line without the rest of its group' do
      credit_line = line(account: account_440, credit: 100, partner: supplier)
      payment     = line(account: account_440, debit: 40, partner: supplier)
      Accounting::AllocateLines.call(lines: [ credit_line, payment ])
      other = line(account: account_440, debit: 100, partner: supplier)

      result = described_class.call(lines: [ credit_line.reload, other ])
      expect(result).to be_failure
      expect(result.message).to eq('A partly settled line can only be lettered with its whole allocation group')
    end
  end

  describe 'accounts without a partner (580000 style)' do
    it 'letters lines with no partner' do
      transit = create(:account, code: '580000', account_class: 5)
      a = line(account: transit, credit: 300)
      b = line(account: transit, debit: 300)
      expect(described_class.call(lines: [ a, b ])).to be_success
      expect(a.reload.lettering.partner).to be_nil
    end
  end

  describe 'supplier invoice settled from the cash journal' do
    let(:purchase_journal) { create(:journal, :purchase) }
    let(:invoice) do
      create(:invoice, :with_lines, invoice_type: :supplier, partner: supplier,
             fiscal_year: fiscal_year, journal: purchase_journal)
    end
    let(:payable_line) do
      Accounting::PostInvoice.call(invoice: invoice)
      invoice.reload.journal_entry.lines.find_by!(account: account_440)
    end
    let(:cash_line) { line(account: account_440, debit: payable_line.credit, partner: supplier) }

    it 'carries the supplier on the invoice payable line' do
      expect(payable_line.partner).to eq(supplier)
    end

    it 'marks the invoice paid when its payable line is lettered' do
      expect(described_class.call(lines: [ payable_line, cash_line ])).to be_success
      expect(invoice.reload).to be_paid
    end

    it 'leaves a non-invoice group alone' do
      expect { described_class.call(lines: [ line(account: account_440, credit: 5, partner: supplier),
                                             line(account: account_440, debit: 5, partner: supplier) ]) }
        .not_to raise_error
    end
  end
end
