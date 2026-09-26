require 'rails_helper'

RSpec.describe Accounting::PaymentReminderJob, type: :job do
  include_context 'with_open_fiscal_year'
  include_context 'with_pcmn_accounts'

  let!(:sale_journal) { create(:journal, :sale) }
  let(:partner) { create(:partner) }
  let(:invoice) do
    inv = create(:invoice, invoice_type: :customer, partner: partner, fiscal_year: fiscal_year, journal: sale_journal, due_date: Date.current - 10)
    create(:invoice_line, invoice: inv, account: account_700, quantity: 1, unit_price: '100.00', vat_rate: '21.00', position: 1)
    Accounting::PostInvoice.call(invoice: inv).invoice.reload
  end
  let!(:reminder) do
    create(:payment_reminder, partner: partner, recipient: 'accounts@client.example').tap { |r| r.items.create!(invoice: invoice, amount_due: 121) }
  end

  before { ActionMailer::Base.deliveries.clear }

  # A real job runs with no tenant set.
  def run_job(id = reminder.id) = ActsAsTenant.without_tenant { described_class.perform_now(id) }

  it 'delivers the reminder with the PDF of its invoice and marks it sent' do
    run_job

    expect(ActionMailer::Base.deliveries.size).to eq(1)
    expect(ActionMailer::Base.deliveries.first.to).to eq([ 'accounts@client.example' ])
    expect(ActionMailer::Base.deliveries.first.attachments.size).to eq(1)
    expect(reminder.reload).to be_sent
    expect(reminder.sent_at).to be_within(1.minute).of(Time.current)
  end

  it 'records the failure and its reason when the delivery raises' do
    allow_any_instance_of(ActionMailer::MessageDelivery).to receive(:deliver_now).and_raise(StandardError, 'SMTP down')
    run_job

    expect(reminder.reload).to be_failed
    expect(reminder.error).to eq('SMTP down')
  end

  it 'does nothing for a reminder that is not waiting to be sent' do
    reminder.update!(status: :sent)
    run_job
    expect(ActionMailer::Base.deliveries).to be_empty
  end
end
