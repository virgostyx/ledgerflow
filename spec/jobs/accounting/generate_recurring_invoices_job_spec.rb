require 'rails_helper'
require 'fugit' # loaded on demand by Solid Queue

RSpec.describe Accounting::GenerateRecurringInvoicesJob, type: :job do
  # A job runs with no tenant: every entity gets its own recurring invoice, built inside its tenant.
  def recurring_in(entity, start_on: Date.new(2026, 3, 1))
    ActsAsTenant.with_tenant(entity) do
      fiscal_year = create(:fiscal_year, year: 2026, start_date: Date.new(2026, 1, 1), end_date: Date.new(2026, 12, 31), status: :open)
      source = create(:invoice, :posted, fiscal_year: fiscal_year, journal: create(:journal, :sale), partner: create(:partner),
                      invoice_date: Date.new(2026, 1, 10), due_date: Date.new(2026, 2, 9))
      create(:invoice_line, invoice: source, account: create(:account), unit_price: '100.00', vat_rate: '21.00', position: 1)
      create(:recurring_invoice, source_invoice: source, start_on: start_on)
    end
  end

  def drafts_of(entity) = ActsAsTenant.with_tenant(entity) { Accounting::Invoice.draft.where.not(recurring_invoice_id: nil).count }

  let!(:other_active_entity) { create(:entity) } # other entities can exist: the job must not depend on being alone
  let!(:entity_a) { create(:entity) }
  let!(:entity_b) { create(:entity) }

  it 'generates the due drafts of every active entity, each in its own tenant' do
    recurring_in(entity_a)
    recurring_in(entity_b)

    described_class.perform_now(Date.new(2026, 3, 1))

    expect([ drafts_of(entity_a), drafts_of(entity_b) ]).to eq([ 1, 1 ])
  end

  it 'leaves an inactive entity alone' do
    recurring_in(entity_a)
    entity_a.update!(active: false)

    described_class.perform_now(Date.new(2026, 3, 1))

    expect(drafts_of(entity_a)).to eq(0)
  end

  it 'does not generate what is not due yet' do
    recurring_in(entity_a, start_on: Date.new(2026, 5, 1))

    described_class.perform_now(Date.new(2026, 3, 1))

    expect(drafts_of(entity_a)).to eq(0)
  end

  it 'keeps going for the other entities when one of them fails' do
    recurring_in(entity_a)
    recurring_in(entity_b)
    allow(Accounting::RunRecurringInvoices).to receive(:call).and_wrap_original do |original, **args|
      raise StandardError, 'boom' if ActsAsTenant.current_tenant == entity_a # this entity only, whatever the order

      original.call(**args)
    end

    expect { described_class.perform_now(Date.new(2026, 3, 1)) }.not_to raise_error
    expect([ drafts_of(entity_a), drafts_of(entity_b) ]).to eq([ 0, 1 ])
  end

  it 'runs for today by default' do
    expect(Accounting::RunRecurringInvoices).to receive(:call).with(on: Date.current).at_least(:once).and_call_original
    described_class.perform_now
  end

  describe 'its schedule' do
    let(:schedule) { YAML.load_file(Rails.root.join('config/recurring.yml')).fetch('production').fetch('generate_recurring_invoices') }

    it 'runs this job every day in production' do
      expect(schedule['class']).to eq('Accounting::GenerateRecurringInvoicesJob')
      cron = Fugit.parse(schedule['schedule'], multi: :fail) # what Solid Queue does with it
      expect(cron).to be_a(Fugit::Cron)
      expect(cron.original).to eq('0 5 * * *')
    end
  end
end
