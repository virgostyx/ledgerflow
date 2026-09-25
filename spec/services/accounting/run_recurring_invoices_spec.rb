require 'rails_helper'

RSpec.describe Accounting::RunRecurringInvoices, type: :service do
  include_context 'with_open_fiscal_year'
  include_context 'with_pcmn_accounts'

  let!(:sale_journal) { create(:journal, :sale) }
  let(:partner) { create(:partner, name: 'Retainer client') }

  # An issued invoice dated 10 January 2026, due 30 days later, with a single line.
  let!(:source) do
    inv = create(:invoice, invoice_type: :customer, partner: partner, fiscal_year: fiscal_year, journal: sale_journal,
                 invoice_date: Date.new(2026, 1, 10), due_date: Date.new(2026, 2, 9), description: 'Monthly retainer')
    create(:invoice_line, invoice: inv, account: account_700, description: 'Retainer', quantity: 1, unit_price: '1000.00', vat_rate: '21.00', position: 1)
    Accounting::PostInvoice.call(invoice: inv).invoice.reload
  end

  def recurring(**attrs) = create(:recurring_invoice, source_invoice: source, **attrs)

  describe 'a recurrence that is due' do
    let!(:rec) { recurring(start_on: Date.new(2026, 3, 1)) }

    it 'generates a draft dated on the run date, keeping the payment interval, and links it' do
      result = described_class.call(on: Date.new(2026, 3, 1))

      draft = result[:generated].sole
      expect(draft).to be_draft
      expect(draft).to have_attributes(invoice_date: Date.new(2026, 3, 1), due_date: Date.new(2026, 3, 31), partner: partner,
                                       recurring_invoice: rec, invoice_number: nil, journal_entry: nil)
      expect(draft.lines.map(&:description)).to eq([ 'Retainer' ])
    end

    it 'moves the schedule on and records the run' do
      described_class.call(on: Date.new(2026, 3, 1))

      expect(rec.reload).to have_attributes(runs_count: 1, last_run_on: Date.new(2026, 3, 1), last_error: nil,
                                            next_run_on: Date.new(2026, 4, 1))
    end

    it 'never posts what it generates' do
      described_class.call(on: Date.new(2026, 3, 1))
      expect(Accounting::Invoice.where(recurring_invoice: rec).pluck(:status).uniq).to eq([ 'draft' ])
    end

    it 'does nothing before the first date' do
      expect { described_class.call(on: Date.new(2026, 2, 28)) }.not_to change(Accounting::Invoice, :count)
    end

    it 'does not generate the same draft twice on the same day' do
      described_class.call(on: Date.new(2026, 3, 1))

      expect { described_class.call(on: Date.new(2026, 3, 1)) }.not_to change(Accounting::Invoice, :count)
    end

    it 'generates the next one when its date comes' do
      described_class.call(on: Date.new(2026, 3, 1))

      result = described_class.call(on: Date.new(2026, 4, 2))
      expect(result[:generated].sole.invoice_date).to eq(Date.new(2026, 4, 1))
    end
  end

  describe 'a recurrence that must not run' do
    it 'skips a paused one' do
      recurring(start_on: Date.new(2026, 3, 1), active: false)
      expect { described_class.call(on: Date.new(2026, 6, 1)) }.not_to change(Accounting::Invoice, :count)
    end

    it 'skips one whose end date has passed' do
      recurring(start_on: Date.new(2026, 1, 1), end_on: Date.new(2026, 1, 31), runs_count: 1)
      expect { described_class.call(on: Date.new(2026, 6, 1)) }.not_to change(Accounting::Invoice, :count)
    end
  end

  describe 'catching up' do
    it 'generates one draft for each date that was missed, in order' do
      rec = recurring(start_on: Date.new(2026, 1, 1))
      result = described_class.call(on: Date.new(2026, 4, 15))

      expect(result[:generated].map(&:invoice_date)).to eq([ '2026-01-01', '2026-02-01', '2026-03-01', '2026-04-01' ].map { |d| Date.parse(d) })
      expect(rec.reload.runs_count).to eq(4)
    end

    it 'stops at a cap per recurrence and run, the rest following at the next run' do
      stub_const('Accounting::RunRecurringInvoices::MAX_CATCH_UP', 2)
      rec = recurring(start_on: Date.new(2026, 1, 1))

      expect(described_class.call(on: Date.new(2026, 6, 1))[:generated].size).to eq(2)
      expect(rec.reload.runs_count).to eq(2)

      expect(described_class.call(on: Date.new(2026, 6, 2))[:generated].size).to eq(2)
      expect(rec.reload.runs_count).to eq(4)
    end
  end

  describe 'a recurrence that fails' do
    it 'records the error, generates nothing and does not move on when the source has been cancelled' do
      rec = recurring(start_on: Date.new(2026, 3, 1))
      source.update_columns(status: Accounting::Invoice.statuses[:cancelled])

      result = described_class.call(on: Date.new(2026, 3, 1))

      expect(result[:generated]).to be_empty
      expect(result[:failed]).to eq([ rec ])
      expect(rec.reload).to have_attributes(runs_count: 0, last_error: a_string_including('cancelled'))
    end

    it 'records the error when the date is in no open fiscal year' do
      rec = recurring(start_on: Date.new(2031, 3, 1))
      described_class.call(on: Date.new(2031, 3, 1))

      expect(rec.reload.last_error).to be_present
      expect(rec.runs_count).to eq(0)
    end

    it 'does not stop the other recurrences' do
      broken = recurring(start_on: Date.new(2031, 3, 1))
      fine   = recurring(start_on: Date.new(2026, 3, 1))

      described_class.call(on: Date.new(2031, 3, 1))

      expect(fine.reload.runs_count).to be >= 1
      expect(broken.reload.last_error).to be_present
    end

    it 'clears the error once a later run succeeds' do
      rec = recurring(start_on: Date.new(2026, 3, 1))
      source.update_columns(status: Accounting::Invoice.statuses[:cancelled])
      described_class.call(on: Date.new(2026, 3, 1))
      source.update_columns(status: Accounting::Invoice.statuses[:posted])

      described_class.call(on: Date.new(2026, 3, 2))

      expect(rec.reload).to have_attributes(last_error: nil, runs_count: 1)
    end

    it 'leaves no draft behind when the generation fails half way' do
      rec = recurring(start_on: Date.new(2026, 3, 1))
      allow_any_instance_of(Accounting::RecurringInvoice).to receive(:update!).and_raise(StandardError, 'boom')

      expect { described_class.call(on: Date.new(2026, 3, 1)) }.not_to change(Accounting::Invoice, :count)
      expect(rec.reload.runs_count).to eq(0)
    end
  end

  it 'works for a recurring purchase too' do
    purchase_journal = create(:journal, :purchase)
    inv = create(:invoice, invoice_type: :supplier, partner: create(:partner, :supplier), fiscal_year: fiscal_year, journal: purchase_journal,
                 invoice_date: Date.new(2026, 1, 5), due_date: Date.new(2026, 1, 20))
    create(:invoice_line, invoice: inv, account: account_604, unit_price: '300.00', vat_rate: '21.00', position: 1)
    supplier_source = Accounting::PostInvoice.call(invoice: inv).invoice.reload
    create(:recurring_invoice, source_invoice: supplier_source, start_on: Date.new(2026, 2, 5))

    draft = described_class.call(on: Date.new(2026, 2, 5))[:generated].sole

    expect(draft).to have_attributes(invoice_type: 'supplier', invoice_date: Date.new(2026, 2, 5), due_date: Date.new(2026, 2, 20))
  end
end
