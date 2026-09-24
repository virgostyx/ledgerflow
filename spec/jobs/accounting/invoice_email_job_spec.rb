require 'rails_helper'

RSpec.describe Accounting::InvoiceEmailJob, type: :job do
  include_context 'with_open_fiscal_year'
  include_context 'with_pcmn_accounts'

  let!(:sale_journal) { create(:journal, :sale) }
  let(:invoice) do
    inv = create(:invoice, invoice_type: :customer, partner: create(:partner), fiscal_year: fiscal_year, journal: sale_journal)
    create(:invoice_line, invoice: inv, account: account_700, quantity: 1, unit_price: '100.00', vat_rate: '21.00', position: 1)
    Accounting::PostInvoice.call(invoice: inv).invoice.reload
  end
  let!(:email) { create(:invoice_email, invoice: invoice, recipient: 'accounts@client.example') }

  before { ActionMailer::Base.deliveries.clear }

  # A real job runs with no tenant set.
  def run_job(id = email.id) = ActsAsTenant.without_tenant { described_class.perform_now(id) }

  it 'delivers the e-mail with its PDF and marks it sent' do
    run_job

    expect(ActionMailer::Base.deliveries.size).to eq(1)
    expect(ActionMailer::Base.deliveries.first.to).to eq([ 'accounts@client.example' ])
    expect(ActionMailer::Base.deliveries.first.attachments.size).to eq(1)
    expect(email.reload).to be_sent
    expect(email.sent_at).to be_within(1.minute).of(Time.current)
    expect(email.error).to be_nil
  end

  it 'marks the e-mail failed and keeps the error when the delivery raises' do
    delivery = instance_double(ActionMailer::MessageDelivery)
    allow(Accounting::InvoiceMailer).to receive(:invoice_email).and_return(delivery)
    allow(delivery).to receive(:deliver_now).and_raise(Net::SMTPAuthenticationError, 'bad credentials')

    expect { run_job }.not_to raise_error

    expect(email.reload).to be_failed
    expect(email.error).to include('bad credentials')
    expect(email.sent_at).to be_nil
  end

  it 'does not send an e-mail that is not queued any more' do
    email.update!(status: :sent, sent_at: 1.day.ago)
    run_job

    expect(ActionMailer::Base.deliveries).to be_empty
  end
end
