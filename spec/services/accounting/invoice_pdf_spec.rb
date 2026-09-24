require 'rails_helper'

RSpec.describe Accounting::InvoicePdf, type: :service do
  include_context 'with_open_fiscal_year'
  include_context 'with_pcmn_accounts'

  let!(:sale_journal) { create(:journal, :sale) }
  let(:partner) do
    create(:partner, name: 'Sodexo Belgium', street: 'Avenue Louise 1', zip: '1050', city: 'Ixelles',
           vat_number: 'BE0987654321')
  end

  before do
    entity.update!(legal_name: 'Acme Consulting', legal_form: 'SRL', vat_number: 'BE0123456789',
                   address_line1: 'Rue de la Loi 16', zip_code: '1000', city: 'Bruxelles')
  end

  def post_invoice(lines: [ { description: 'Consulting', unit_price: '1000.00', vat_rate: '21.00' } ],
                   invoice_partner: partner, vat_treatment: :domestic, document_type: :invoice, credited: nil,
                   currency: 'EUR', exchange_rate: 1)
    inv = create(:invoice, invoice_type: :customer, partner: invoice_partner, fiscal_year: fiscal_year,
                 journal: sale_journal, vat_treatment: vat_treatment, document_type: document_type,
                 credited_invoice: credited, currency: currency, exchange_rate: exchange_rate,
                 due_date: Date.current + 30)
    lines.each_with_index do |l, i|
      create(:invoice_line, invoice: inv, account: account_700, quantity: l[:quantity] || 1,
             description: l[:description], unit_price: l[:unit_price], vat_rate: l[:vat_rate], position: i + 1)
    end
    Accounting::PostInvoice.call(invoice: inv).invoice.reload
  end

  def pdf_text(invoice)
    pdf = described_class.new(invoice).render
    PDF::Reader.new(StringIO.new(pdf)).pages.map(&:text).join("\n").gsub(/\s+/, ' ')
  end

  it 'renders a PDF document' do
    expect(described_class.new(post_invoice).render).to start_with('%PDF')
  end

  describe 'an invoice' do
    let(:invoice) { post_invoice }
    subject(:text) { pdf_text(invoice) }

    it 'shows the issuer from the entity' do
      expect(text).to include('Acme Consulting', 'BE0123456789', 'Rue de la Loi 16', '1000 Bruxelles')
    end

    it 'does not repeat the legal form when the legal name already ends with it' do
      entity.update!(legal_name: 'Acme Consulting SRL', legal_form: 'SRL')
      expect(pdf_text(invoice)).to include('Acme Consulting SRL').and(satisfy { |t| !t.include?('SRL SRL') })
    end

    it 'shows the customer' do
      expect(text).to include('Sodexo Belgium', 'Avenue Louise 1', '1050 Ixelles', 'BE0987654321')
    end

    it 'leaves out the country of a customer in the issuer country' do
      expect(text).not_to match(/1050 Ixelles BE\b/)
    end

    it 'shows the country of a customer abroad' do
      abroad = create(:partner, name: 'Paris SARL', street: '10 rue de Rivoli', zip: '75001', city: 'Paris', country: 'FR')
      expect(pdf_text(post_invoice(invoice_partner: abroad))).to match(/75001 Paris FR\b/)
    end

    it 'shows the title, number and dates' do
      expect(text).to include('Invoice', invoice.invoice_number,
                              Accounting::DatePresenter.new(invoice.invoice_date).format,
                              Accounting::DatePresenter.new(invoice.due_date).format)
    end

    it 'shows the lines and the totals' do
      expect(text).to include('Consulting', '1 000,00 €', '210,00 €', '1 210,00 €')
    end

    it 'has no legal VAT mention for a domestic invoice' do
      expect(text).not_to match(/VAT exempt|reverse charge/i)
    end
  end

  describe 'several VAT rates' do
    it 'breaks the VAT down per rate' do
      invoice = post_invoice(lines: [ { description: 'Training', unit_price: '1000.00', vat_rate: '21.00' },
                                      { description: 'Book', unit_price: '100.00', vat_rate: '6.00' } ])
      text = pdf_text(invoice)

      expect(text).to include('Training', 'Book', '21%', '6%', '210,00 €', '6,00 €', '1 316,00 €')
    end
  end

  describe 'payment details' do
    let!(:bank_account) { create(:bank_account) }

    it 'shows the IBAN, BIC and the structured communication of an invoice' do
      invoice = post_invoice
      text = pdf_text(invoice)

      expect(text).to include(bank_account.iban, 'BBVABEBB',
                              Accounting::StructuredCommunication.display(Accounting::StructuredCommunication.for_id(invoice.id)))
    end

    it 'is left out for a credit note' do
      original = post_invoice
      note = post_invoice(document_type: :credit_note, credited: original)
      text = pdf_text(note)

      expect(text).not_to include(bank_account.iban)
      expect(text).not_to include('+++')
    end

    it 'still renders when the entity has no bank account' do
      bank_account.destroy!
      expect(pdf_text(post_invoice)).to include('Consulting')
    end
  end

  describe 'a credit note' do
    it 'is titled and refers to the credited invoice' do
      original = post_invoice
      note = post_invoice(lines: [ { description: 'Refund', unit_price: '100.00', vat_rate: '21.00' } ],
                          document_type: :credit_note, credited: original)
      text = pdf_text(note)

      expect(text).to include('Credit note', note.invoice_number, "Credits invoice #{original.invoice_number}", '121,00 €')
    end
  end

  describe 'legal VAT mentions' do
    let(:eu_partner) { create(:partner, name: 'Paris SARL', vat_number: 'FR32123456789', country: 'FR') }

    {
      intracom_goods:              'Intra-community supply, VAT exempt',
      intracom_services:           'VAT reverse charge: VAT to be accounted for by the customer',
      construction_reverse_charge: 'VAT reverse charge: VAT to be accounted for by the customer',
      export:                      'Export, VAT exempt',
      exempt:                      'VAT exempt'
    }.each do |treatment, mention|
      it "prints '#{mention}' for #{treatment}" do
        invoice = post_invoice(invoice_partner: eu_partner, vat_treatment: treatment)
        expect(pdf_text(invoice)).to include(mention)
      end
    end

    it 'prints the small-business exemption for an entity under the franchise regime' do
      entity.update!(vat_regime: :franchise)
      expect(pdf_text(post_invoice)).to include('VAT exemption for small businesses')
    end
  end

  describe 'robustness' do
    it 'uses the invoice currency symbol' do
      invoice = post_invoice(currency: 'USD', exchange_rate: BigDecimal('0.9'))
      expect(pdf_text(invoice)).to include('1 210,00 $')
    end

    it 'does not fail on characters the built-in font cannot draw' do
      odd = create(:partner, name: 'Zażółć Sp. z o.o.')
      expect { pdf_text(post_invoice(invoice_partner: odd)) }.not_to raise_error
    end

    it 'wraps a long description over several lines' do
      words = Array.new(60) { |i| "word#{i}" }.join(' ')
      text = pdf_text(post_invoice(lines: [ { description: words, unit_price: '10.00', vat_rate: '21.00' } ]))

      expect(text).to include('word0', 'word59')
    end
  end
end
