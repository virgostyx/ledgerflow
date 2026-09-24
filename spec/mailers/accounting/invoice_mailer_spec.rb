require 'rails_helper'

RSpec.describe Accounting::InvoiceMailer, type: :mailer do
  include_context 'with_open_fiscal_year'
  include_context 'with_pcmn_accounts'

  let!(:sale_journal) { create(:journal, :sale) }
  let(:partner) { create(:partner, name: 'Sodexo Belgium') }

  before do
    entity.update!(legal_name: 'Acme Consulting', legal_form: 'SRL')
  end

  def posted_invoice(document_type: :invoice, credited: nil, unit_price: '1000.00')
    inv = create(:invoice, invoice_type: :customer, partner: partner, fiscal_year: fiscal_year, journal: sale_journal,
                 document_type: document_type, credited_invoice: credited, due_date: Date.current + 30)
    create(:invoice_line, invoice: inv, account: account_700, quantity: 1, description: 'Consulting',
           unit_price: unit_price, vat_rate: '21.00', position: 1)
    Accounting::PostInvoice.call(invoice: inv).invoice.reload
  end

  def email_for(invoice, **attrs)
    create(:invoice_email, invoice: invoice, recipient: 'accounts@sodexo.example',
           subject: "Invoice #{invoice.invoice_number} from Acme Consulting", **attrs)
  end

  describe '#invoice_email' do
    let(:invoice) { posted_invoice }
    let(:mail)    { described_class.invoice_email(email_for(invoice)) }

    it 'is addressed to the recipient with the stored subject' do
      expect(mail.to).to eq([ 'accounts@sodexo.example' ])
      expect(mail.subject).to eq("Invoice #{invoice.invoice_number} from Acme Consulting")
    end

    it 'is sent in the name of the entity' do
      expect(mail[:from].to_s).to include('Acme Consulting')
      expect(mail.from).to eq([ ENV.fetch('MAILER_FROM', 'invoices@ledgerflow.example') ])
    end

    it 'mentions the invoice in a plain text body' do
      body = mail.body.parts.first&.decoded || mail.body.decoded
      expect(body).to include(invoice.invoice_number, 'Acme Consulting', '1 210,00 €')
    end

    it 'attaches the invoice PDF, named after the number without slashes' do
      attachment = mail.attachments.first

      expect(mail.attachments.size).to eq(1)
      expect(attachment.filename).to eq("#{invoice.invoice_number.tr('/', '-')}.pdf")
      expect(attachment.content_type).to start_with('application/pdf')
      text = PDF::Reader.new(StringIO.new(attachment.body.decoded)).pages.map(&:text).join(' ').gsub(/\s+/, ' ')
      expect(text).to include(invoice.invoice_number, 'Sodexo Belgium')
    end

    it 'renders the attachment even outside a tenant block (the way a job calls it)' do
      email = email_for(invoice)
      built = ActsAsTenant.without_tenant { described_class.invoice_email(email).message }

      expect(built.attachments.size).to eq(1)
    end
  end

  describe 'a credit note' do
    it 'says so in the body and attaches its PDF' do
      original = posted_invoice
      note = posted_invoice(document_type: :credit_note, credited: original, unit_price: '100.00')
      mail = described_class.invoice_email(email_for(note))
      body = mail.body.parts.first&.decoded || mail.body.decoded

      expect(body).to include('credit note', note.invoice_number)
      expect(mail.attachments.first.filename).to eq("#{note.invoice_number.tr('/', '-')}.pdf")
    end
  end
end
