require 'rails_helper'

RSpec.describe Peppol::HandleEvent do
  include_context 'with_open_fiscal_year'

  let(:partner) { create(:partner, :with_vat) }
  let!(:invoice) { create(:invoice, :posted, partner: partner, fiscal_year: fiscal_year, peppol_id: 'MSG-1', peppol_status: :queued) }

  # A webhook or a job runs with no tenant set.
  def handle(**attrs) = ActsAsTenant.without_tenant { described_class.call(event: Peppol::Event.new(**attrs)) }

  describe 'a delivery' do
    it 'marks the invoice delivered and records it' do
      result = handle(kind: :delivered, message_id: 'MSG-1')

      expect(result).to be_success
      expect(invoice.reload.peppol_status).to eq('delivered')
      expect(invoice.peppol_events.sole).to have_attributes(kind: 'delivered')
    end

    it 'finds the invoice whatever the entity, and works inside its tenant' do
      other_entity = create(:entity)
      other_invoice = ActsAsTenant.with_tenant(other_entity) do
        fy = create(:fiscal_year, year: 2026, start_date: Date.new(2026, 1, 1), end_date: Date.new(2026, 12, 31), status: :open)
        create(:invoice, :posted, fiscal_year: fy, peppol_id: 'MSG-OTHER', peppol_status: :queued)
      end

      handle(kind: :delivered, message_id: 'MSG-OTHER')

      expect(ActsAsTenant.with_tenant(other_entity) { other_invoice.reload.peppol_status }).to eq('delivered')
      expect(invoice.reload.peppol_status).to eq('queued')
    end
  end

  describe 'a failure' do
    it 'marks the invoice failed and keeps the reason in its history' do
      handle(kind: :failed, message_id: 'MSG-1', error: 'Receiver rejected the document')

      expect(invoice.reload.peppol_status).to eq('failed')
      expect(invoice.peppol_events.sole).to have_attributes(kind: 'failed', message: 'Receiver rejected the document')
    end

    it 'has a default reason when the Access Point gives none' do
      handle(kind: :failed, message_id: 'MSG-1')
      expect(invoice.peppol_events.sole.message).to be_present
    end
  end

  describe 'what it ignores' do
    it 'an unknown message id, without failing' do
      result = handle(kind: :delivered, message_id: 'NOPE')

      expect(result).to be_success
      expect(result[:ignored]).to be true
      expect(invoice.reload.peppol_status).to eq('queued')
    end

    it 'an event without a message id' do
      expect(handle(kind: :delivered)[:ignored]).to be true
    end

    it 'an event kind it cannot handle' do
      expect(handle(kind: :something, message_id: 'MSG-1')[:ignored]).to be true
    end
  end

  it 'does not repeat itself: a second identical event changes nothing more' do
    handle(kind: :delivered, message_id: 'MSG-1')
    expect { handle(kind: :delivered, message_id: 'MSG-1') }.not_to change { invoice.peppol_events.count }
  end
  describe 'a received document' do
    let(:xml) do
      <<~XML
        <?xml version="1.0" encoding="UTF-8"?>
        <Invoice xmlns="urn:oasis:names:specification:ubl:schema:xsd:Invoice-2"
                 xmlns:cac="urn:oasis:names:specification:ubl:schema:xsd:CommonAggregateComponents-2"
                 xmlns:cbc="urn:oasis:names:specification:ubl:schema:xsd:CommonBasicComponents-2">
          <cbc:ID>INCOMING-001</cbc:ID>
          <cbc:IssueDate>2025-06-01</cbc:IssueDate>
          <cbc:DocumentCurrencyCode>EUR</cbc:DocumentCurrencyCode>
          <cac:AccountingSupplierParty><cac:Party>
            <cac:PartyName><cbc:Name>Fournisseur Externe</cbc:Name></cac:PartyName>
            <cac:PartyTaxScheme><cbc:CompanyID>BE0123456789</cbc:CompanyID><cac:TaxScheme><cbc:ID>VAT</cbc:ID></cac:TaxScheme></cac:PartyTaxScheme>
          </cac:Party></cac:AccountingSupplierParty>
          <cac:TaxTotal><cbc:TaxAmount currencyID="EUR">105.00</cbc:TaxAmount></cac:TaxTotal>
          <cac:LegalMonetaryTotal>
            <cbc:TaxExclusiveAmount currencyID="EUR">500.00</cbc:TaxExclusiveAmount>
            <cbc:TaxInclusiveAmount currencyID="EUR">605.00</cbc:TaxInclusiveAmount>
          </cac:LegalMonetaryTotal>
        </Invoice>
      XML
    end

    before { entity.update!(peppol_participant_id: '0208:0555666777') }

    def received(receiver: '0208:0555666777') = handle(kind: :received, receiver: receiver, xml: xml)

    it 'creates a draft supplier invoice in the entity that owns the receiver identifier' do
      other = create(:entity, peppol_participant_id: '0208:0111222333')
      ActsAsTenant.with_tenant(other) { create(:fiscal_year, year: 2026, start_date: Date.new(2026, 1, 1), end_date: Date.new(2026, 12, 31), status: :open) }

      expect { received }.to change { ActsAsTenant.with_tenant(entity) { Accounting::Invoice.count } }.by(1)
        .and change { ActsAsTenant.with_tenant(other) { Accounting::Invoice.count } }.by(0)
      created = ActsAsTenant.with_tenant(entity) { Accounting::Invoice.find_by(external_ref: 'INCOMING-001') }
      expect(created).to have_attributes(invoice_type: 'supplier', status: 'draft', fiscal_year_id: fiscal_year.id)
    end

    it 'ignores a receiver that belongs to no entity, creating nothing' do
      expect { expect(received(receiver: '0208:0000000000')[:ignored]).to be true }.not_to change { ActsAsTenant.without_tenant { Accounting::Invoice.count } }
    end

    it 'creates nothing, and says why, when the entity has no open fiscal year' do
      fiscal_year.update!(status: :closed)
      result = nil
      expect { result = received }.not_to change { ActsAsTenant.without_tenant { Accounting::Invoice.count } }
      expect(result).to be_failure
      expect(result.message).to match(/open fiscal year/)
    end

    it 'fails when the document cannot be read' do
      result = handle(kind: :received, receiver: '0208:0555666777', xml: '<Invoice/>')
      expect(result).to be_failure
    end
  end
end
