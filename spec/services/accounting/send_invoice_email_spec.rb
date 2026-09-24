require 'rails_helper'

RSpec.describe Accounting::SendInvoiceEmail, type: :service do
  include_context 'with_open_fiscal_year'
  include_context 'with_pcmn_accounts'

  let!(:sale_journal)     { create(:journal, :sale) }
  let!(:purchase_journal) { create(:journal, :purchase) }
  let(:user)    { create(:user, :accountant) }
  let(:partner) { create(:partner, name: 'Sodexo Belgium') }

  around do |example|
    previous = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :test
    example.run
  ensure
    ActiveJob::Base.queue_adapter = previous
  end

  before { entity.update!(legal_name: 'Acme Consulting') }

  def posted(type: :customer, document_type: :invoice, credited: nil)
    inv = create(:invoice, invoice_type: type, partner: partner, fiscal_year: fiscal_year, document_type: document_type,
                 credited_invoice: credited, journal: type == :customer ? sale_journal : purchase_journal)
    create(:invoice_line, invoice: inv, account: type == :customer ? account_700 : account_604, quantity: 1,
           unit_price: '100.00', vat_rate: '21.00', position: 1)
    Accounting::PostInvoice.call(invoice: inv).invoice.reload
  end

  def call(invoice, recipient: 'accounts@sodexo.example')
    described_class.call(invoice: invoice, recipient: recipient, user: user)
  end

  it 'records a queued e-mail and enqueues the job with its id' do
    invoice = posted
    result = nil
    expect { result = call(invoice) }.to change(Accounting::InvoiceEmail, :count).by(1)
      .and have_enqueued_job(Accounting::InvoiceEmailJob)

    email = result[:email]
    expect(result).to be_success
    expect(email).to have_attributes(invoice: invoice, recipient: 'accounts@sodexo.example', sent_by: user, status: 'queued',
                                     subject: "Invoice #{invoice.invoice_number} from Acme Consulting")
    expect(Accounting::InvoiceEmailJob).to have_been_enqueued.with(email.id)
  end

  it 'words the subject for a credit note' do
    original = posted
    note = posted(document_type: :credit_note, credited: original)

    expect(call(note)[:email].subject).to eq("Credit note #{note.invoice_number} from Acme Consulting")
  end

  it 'trims the recipient' do
    expect(call(posted, recipient: '  accounts@sodexo.example ')[:email].recipient).to eq('accounts@sodexo.example')
  end

  it 'refuses an invalid recipient without creating anything' do
    result = nil
    expect { result = call(posted, recipient: 'nope') }.not_to change(Accounting::InvoiceEmail, :count)

    expect(result).to be_failure
    expect(result.message).to be_present
    expect(Accounting::InvoiceEmailJob).not_to have_been_enqueued
  end

  it 'refuses a draft' do
    draft = create(:invoice, :with_lines, invoice_type: :customer, fiscal_year: fiscal_year, journal: sale_journal)

    expect(call(draft)).to be_failure
    expect(Accounting::InvoiceEmail.count).to eq(0)
  end

  it 'refuses a supplier invoice' do
    expect(call(posted(type: :supplier))).to be_failure
  end

  %i[paid partially_paid].each do |status|
    it "accepts a #{status} invoice" do
      invoice = posted
      invoice.update_columns(status: Accounting::Invoice.statuses[status])

      expect(call(invoice)).to be_success
    end
  end
end
