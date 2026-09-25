require 'rails_helper'

RSpec.describe Accounting::RecurringInvoice, type: :model do
  include_context 'with_open_fiscal_year'

  let(:source) { create(:invoice, :posted, fiscal_year: fiscal_year) }

  def recurring(**attrs) = build(:recurring_invoice, source_invoice: source, **attrs)

  describe 'associations and enums' do
    it { should belong_to(:source_invoice).class_name('Accounting::Invoice') }
    it { should have_many(:generated_invoices).class_name('Accounting::Invoice').dependent(:nullify) }
    it { should define_enum_for(:frequency).with_values(monthly: 0, quarterly: 1, yearly: 2) }
  end

  describe 'validations' do
    it 'is valid with a source invoice, a frequency and a first date' do
      expect(recurring).to be_valid
    end

    it { expect(recurring(start_on: nil)).not_to be_valid }

    it 'rejects an end date before the first date' do
      expect(recurring(end_on: Date.new(2026, 1, 30))).not_to be_valid
    end

    it 'accepts an end date on the first date' do
      expect(recurring(end_on: Date.new(2026, 1, 31))).to be_valid
    end

    it 'is active with no run yet by default' do
      expect(described_class.new).to have_attributes(active: true, runs_count: 0)
    end

    it 'only takes an issued invoice as its source' do
      draft  = create(:invoice, fiscal_year: fiscal_year)
      credit = create(:invoice, :posted, fiscal_year: fiscal_year, document_type: :credit_note)

      expect(build(:recurring_invoice, source_invoice: draft)).not_to be_valid
      expect(build(:recurring_invoice, source_invoice: credit)).not_to be_valid
    end

    it 'still accepts changes after its source has been cancelled' do
      rec = recurring.tap(&:save!)
      source.update_columns(status: Accounting::Invoice.statuses[:cancelled])

      expect(rec.reload.update(active: false)).to be true
    end
  end

  describe '#next_run_on' do
    it 'is the first date before any run' do
      expect(recurring.next_run_on).to eq(Date.new(2026, 1, 31))
    end

    it 'keeps the day of the month without drifting after a short month' do
      dates = (0..4).map { |n| recurring(runs_count: n).next_run_on }

      expect(dates).to eq([ '2026-01-31', '2026-02-28', '2026-03-31', '2026-04-30', '2026-05-31' ].map { |d| Date.parse(d) })
    end

    it 'steps by three months when quarterly' do
      dates = (0..2).map { |n| recurring(frequency: :quarterly, start_on: Date.new(2026, 1, 15), runs_count: n).next_run_on }
      expect(dates).to eq([ '2026-01-15', '2026-04-15', '2026-07-15' ].map { |d| Date.parse(d) })
    end

    it 'steps by a year when yearly, including a 29 February' do
      dates = (0..4).map { |n| recurring(frequency: :yearly, start_on: Date.new(2028, 2, 29), runs_count: n).next_run_on }
      expect(dates).to eq([ '2028-02-29', '2029-02-28', '2030-02-28', '2031-02-28', '2032-02-29' ].map { |d| Date.parse(d) })
    end
  end

  describe '#due?' do
    it 'is due on and after its next run date' do
      rec = recurring
      expect(rec.due?(Date.new(2026, 1, 30))).to be false
      expect(rec.due?(Date.new(2026, 1, 31))).to be true
      expect(rec.due?(Date.new(2026, 6, 1))).to be true
    end

    it 'is never due when paused' do
      expect(recurring(active: false).due?(Date.new(2030, 1, 1))).to be false
    end

    it 'is not due once its next run date is after the end date' do
      rec = recurring(end_on: Date.new(2026, 3, 31), runs_count: 3) # next run: 30 April

      expect(rec.due?(Date.new(2026, 5, 1))).to be false
    end

    it 'is still due on its last date' do
      rec = recurring(end_on: Date.new(2026, 3, 31), runs_count: 2) # next run: 31 March
      expect(rec.due?(Date.new(2026, 4, 5))).to be true
    end
  end

  describe '#status' do
    it 'tells active, paused and ended apart' do
      expect(recurring.status).to eq(:active)
      expect(recurring(active: false).status).to eq(:paused)
      expect(recurring(end_on: Date.new(2026, 3, 31), runs_count: 3).status).to eq(:ended)
    end
  end

  describe '#resume!' do
    it 'reactivates the recurrence and skips the dates that came and went while it was paused' do
      rec = create(:recurring_invoice, source_invoice: source, start_on: Date.new(2026, 1, 1), runs_count: 1, active: false) # next was 1 February

      rec.resume!(on: Date.new(2026, 5, 10))

      expect(rec.reload).to have_attributes(active: true, next_run_on: Date.new(2026, 6, 1))
      expect(rec.due?(Date.new(2026, 5, 31))).to be false
    end

    it 'keeps a next date that is today or later' do
      rec = create(:recurring_invoice, source_invoice: source, start_on: Date.new(2026, 5, 10), active: false)

      rec.resume!(on: Date.new(2026, 5, 10))

      expect(rec.reload).to have_attributes(active: true, runs_count: 0, next_run_on: Date.new(2026, 5, 10))
    end
  end

  describe '#pending_drafts_count' do
    it 'counts the generated invoices that are still drafts' do
      rec = create(:recurring_invoice, source_invoice: source)
      create(:invoice, fiscal_year: fiscal_year, recurring_invoice: rec)
      create(:invoice, :posted, fiscal_year: fiscal_year, recurring_invoice: rec)

      expect(rec.pending_drafts_count).to eq(1)
    end
  end
end
