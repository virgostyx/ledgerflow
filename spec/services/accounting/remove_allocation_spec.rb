require 'rails_helper'

RSpec.describe Accounting::RemoveAllocation, type: :service do
  include_context 'with_open_fiscal_year'
  include_context 'with_pcmn_accounts'

  let(:supplier) { create(:partner, :supplier) }
  let(:journal)  { create(:journal, :cash) }

  def line(debit: 0, credit: 0)
    entry = create(:journal_entry, status: :posted, journal: journal, fiscal_year: fiscal_year)
    ApplicationRecord.connection.execute('SET CONSTRAINTS enforce_double_entry DEFERRED')
    create(:journal_entry_line, journal_entry: entry, account: account_440, partner: supplier,
           debit: BigDecimal(debit.to_s), credit: BigDecimal(credit.to_s))
  end

  let!(:credit_line) { line(credit: 1000) }
  let!(:invoice) do
    create(:invoice, :posted, :supplier, fiscal_year: fiscal_year, partner: supplier, journal_entry: credit_line.journal_entry)
  end
  let!(:payment) { line(debit: 600) }

  before { Accounting::AllocateLines.call(lines: [ credit_line, payment ]) }

  let(:allocation) { Accounting::LineAllocation.first }

  it 'removes the allocation and puts the invoice back to posted' do
    expect(invoice.reload).to be_partially_paid

    expect(described_class.call(allocation: allocation)).to be_success
    expect(Accounting::LineAllocation.count).to eq(0)
    expect(credit_line.reload.open_amount).to eq(BigDecimal('1000'))
    expect(invoice.reload).to be_posted
  end

  it 'keeps the invoice partially paid while another allocation remains' do
    more = line(debit: 100)
    Accounting::AllocateLines.call(lines: [ credit_line.reload, more ])

    described_class.call(allocation: Accounting::LineAllocation.find_by!(debit_line: more))
    expect(invoice.reload).to be_partially_paid
  end

  it 'cannot remove one allocation once the settled group is lettered' do
    rest = line(debit: 300)
    Accounting::AllocateLines.call(lines: [ credit_line.reload, rest ])
    expect(invoice.reload).to be_partially_paid

    final = line(debit: 100)
    Accounting::AllocateLines.call(lines: [ credit_line.reload, final ])
    expect(invoice.reload).to be_paid

    expect(described_class.call(allocation: Accounting::LineAllocation.first)).to be_failure
  end

  it 'refuses when a line is lettered' do
    allocation.credit_line.update_columns(lettering_id: create(:lettering, account: account_440).id)
    result = described_class.call(allocation: allocation)
    expect(result).to be_failure
    expect(result.message).to eq('Remove the lettering first')
  end
end
