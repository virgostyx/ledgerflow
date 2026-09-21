require 'rails_helper'

RSpec.describe Accounting::AllocateLines, type: :service do
  include_context 'with_open_fiscal_year'
  include_context 'with_pcmn_accounts'

  let(:supplier) { create(:partner, :supplier) }
  let(:journal)  { create(:journal, :cash) }

  def line(debit: 0, credit: 0, partner: supplier, account: account_440, status: :posted, invoice: nil, days_ago: 0)
    entry = create(:journal_entry, status: status, journal: journal, fiscal_year: fiscal_year, entry_date: Date.current - days_ago)
    ApplicationRecord.connection.execute('SET CONSTRAINTS enforce_double_entry DEFERRED')
    create(:journal_entry_line, journal_entry: entry, account: account, partner: partner, invoice: invoice,
           debit: BigDecimal(debit.to_s), credit: BigDecimal(credit.to_s))
  end

  # A posted supplier invoice whose payable line is the returned credit line.
  def invoice_line(amount, days_ago: 0)
    invoice_line = line(credit: amount, days_ago: days_ago)
    invoice = create(:invoice, :posted, :supplier, fiscal_year: fiscal_year, partner: supplier,
                     journal_entry: invoice_line.journal_entry, due_date: Date.current - days_ago)
    invoice_line.update_columns(invoice_id: invoice.id)
    [ invoice_line, invoice ]
  end

  describe 'a payment smaller than the invoice' do
    let!(:invoice_pair) { invoice_line(1000) }
    let(:credit_line)   { invoice_pair.first }
    let(:invoice)       { invoice_pair.last }
    let!(:payment)      { line(debit: 600) }
    subject(:result)    { described_class.call(lines: [ credit_line, payment ]) }

    it 'allocates the payment and leaves the residual open' do
      expect(result).to be_success
      expect(Accounting::LineAllocation.count).to eq(1)
      expect(Accounting::LineAllocation.first).to have_attributes(amount: BigDecimal('600'), debit_line: payment, credit_line: credit_line)
      expect(credit_line.reload.open_amount).to eq(BigDecimal('400'))
      expect(payment.reload.open_amount).to eq(0)
    end

    it 'does not letter anything and marks the invoice partially paid' do
      result
      expect(Accounting::Lettering.count).to eq(0)
      expect(invoice.reload).to be_partially_paid
    end

    it 'settles and letters the group when the balance is paid, marking the invoice paid' do
      result
      final = line(debit: 400)
      expect(described_class.call(lines: [ credit_line.reload, final ])).to be_success

      expect(Accounting::Lettering.count).to eq(1)
      expect([ credit_line, payment, final ].map { |l| l.reload.lettering_id }.uniq.size).to eq(1)
      expect(invoice.reload).to be_paid
    end
  end

  describe 'a payment covering several invoices' do
    let!(:old_pair) { invoice_line(500, days_ago: 40) }
    let!(:new_pair) { invoice_line(400, days_ago: 10) }
    let!(:payment)  { line(debit: 600) }

    it 'settles the oldest due date first' do
      result = described_class.call(lines: [ new_pair.first, payment, old_pair.first ])

      expect(result).to be_success
      expect(old_pair.first.reload.open_amount).to eq(0)
      expect(new_pair.first.reload.open_amount).to eq(BigDecimal('300'))
      expect(old_pair.last.reload).to be_paid
      expect(new_pair.last.reload).to be_partially_paid
    end
  end

  describe 'an overpayment' do
    it 'marks the invoice paid but letters nothing while the payment keeps a residual' do
      credit_line, invoice = invoice_line(100)
      payment = line(debit: 150)

      expect(described_class.call(lines: [ credit_line, payment ])).to be_success
      expect(credit_line.reload.open_amount).to eq(0)
      expect(payment.reload.open_amount).to eq(BigDecimal('50'))
      expect(Accounting::Lettering.count).to eq(0)
      expect(invoice.reload).to be_paid
    end
  end

  describe 'validation' do
    let(:credit_line) { line(credit: 100) }
    let(:debit_line)  { line(debit: 40) }

    it 'needs at least two lines' do
      expect(described_class.call(lines: [ credit_line ]).message).to eq('Select at least two lines')
    end

    it 'needs a debit and a credit line' do
      other = line(credit: 10)
      expect(described_class.call(lines: [ credit_line, other ]).message).to eq('Select at least one debit and one credit line')
    end

    it 'rejects draft entries' do
      expect(described_class.call(lines: [ credit_line, line(debit: 40, status: :draft) ]).message)
        .to eq('Only lines of posted entries can be allocated')
    end

    it 'rejects lettered lines' do
      credit_line.update_columns(lettering_id: create(:lettering, account: account_440).id)
      expect(described_class.call(lines: [ credit_line, debit_line ]).message).to eq('A line is already lettered')
    end

    it 'rejects different accounts' do
      expect(described_class.call(lines: [ credit_line, line(debit: 40, account: account_400) ]).message)
        .to eq('Lines must be on the same account')
    end

    it 'rejects different partners' do
      expect(described_class.call(lines: [ credit_line, line(debit: 40, partner: create(:partner)) ]).message)
        .to eq('Lines must have the same partner')
    end

    it 'rejects a line with nothing left to allocate' do
      described_class.call(lines: [ credit_line, debit_line ])
      again = line(credit: 10)
      expect(described_class.call(lines: [ debit_line.reload, again ]).message).to eq('A line has nothing left to allocate')
    end

    it 'creates nothing on failure' do
      expect { described_class.call(lines: [ credit_line, line(debit: 40, status: :draft) ]) }
        .not_to change(Accounting::LineAllocation, :count)
    end
  end
end
