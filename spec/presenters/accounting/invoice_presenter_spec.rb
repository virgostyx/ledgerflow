require 'rails_helper'

RSpec.describe Accounting::InvoicePresenter, type: :presenter do
  include_context 'with_open_fiscal_year'

  let(:partner) { create(:partner, name: 'ACME SA') }

  describe '#invoice_number_or_draft' do
    it 'retourne le numéro quand présent' do
      invoice = build(:invoice, invoice_number: 'VTE2026/0001')
      presenter = described_class.new(invoice)
      expect(presenter.invoice_number_or_draft).to eq('VTE2026/0001')
    end

    it 'retourne Brouillon quand pas de numéro' do
      invoice = build(:invoice, invoice_number: nil)
      presenter = described_class.new(invoice)
      expect(presenter.invoice_number_or_draft).to eq('Brouillon')
    end
  end

  describe '#formatted_date' do
    it 'formate la date en dd/mm/yyyy' do
      invoice = build(:invoice, invoice_date: Date.new(2026, 3, 15))
      presenter = described_class.new(invoice)
      expect(presenter.formatted_date).to eq('15/03/2026')
    end
  end

  describe '#formatted_due_date' do
    it 'formate l échéance' do
      invoice = build(:invoice, due_date: Date.new(2026, 4, 14))
      presenter = described_class.new(invoice)
      expect(presenter.formatted_due_date).to eq('14/04/2026')
    end

    it 'retourne — si pas d échéance' do
      invoice = build(:invoice, due_date: nil)
      presenter = described_class.new(invoice)
      expect(presenter.formatted_due_date).to eq('—')
    end
  end

  describe '#formatted_total' do
    it 'formate le total en euros belges' do
      invoice = build(:invoice, total_incl_vat: BigDecimal('1234.56'))
      presenter = described_class.new(invoice)
      expect(presenter.formatted_total).to eq('1 234,56 €')
    end
  end

  describe '#type_label' do
    it 'retourne Client pour customer' do
      invoice = build(:invoice, invoice_type: :customer)
      presenter = described_class.new(invoice)
      expect(presenter.type_label).to eq('Client')
    end

    it 'retourne Fournisseur pour supplier' do
      invoice = build(:invoice, invoice_type: :supplier)
      presenter = described_class.new(invoice)
      expect(presenter.type_label).to eq('Fournisseur')
    end
  end

  describe '#status_label' do
    it { expect(described_class.new(build(:invoice, status: :draft)).status_label).to eq('Brouillon') }
    it { expect(described_class.new(build(:invoice, status: :posted)).status_label).to eq('Validée') }
    it { expect(described_class.new(build(:invoice, status: :paid)).status_label).to eq('Payée') }
    it { expect(described_class.new(build(:invoice, status: :cancelled)).status_label).to eq('Annulée') }
  end

  describe '#status_badge_variant' do
    it { expect(described_class.new(build(:invoice, status: :draft)).status_badge_variant).to eq(:default) }
    it { expect(described_class.new(build(:invoice, status: :posted)).status_badge_variant).to eq(:success) }
    it { expect(described_class.new(build(:invoice, status: :paid)).status_badge_variant).to eq(:success) }
    it { expect(described_class.new(build(:invoice, status: :cancelled)).status_badge_variant).to eq(:danger) }
  end
end
