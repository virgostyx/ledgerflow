require 'rails_helper'

RSpec.describe Accounting::InvoicePresenter, type: :presenter do
  include_context 'with_open_fiscal_year'

  let(:partner) { create(:partner, name: 'ACME SA') }

  describe '#entry_number_display' do
    it 'retourne le numéro assigné quand présent' do
      invoice = build(:invoice, invoice_number: 'ACH2026/0001')
      expect(described_class.new(invoice).entry_number_display).to eq('ACH2026/0001')
    end

    it 'calcule le prochain numéro depuis le journal pour un draft' do
      journal = create(:journal, :purchase, current_sequence: 4)
      invoice = build(:invoice, :draft, invoice_number: nil, journal: journal, invoice_date: Date.new(2026, 6, 1))
      expect(described_class.new(invoice).entry_number_display).to eq('ACH2026/0005')
    end

    it 'retourne — si draft sans journal' do
      invoice = build(:invoice, :draft, invoice_number: nil, journal: nil)
      expect(described_class.new(invoice).entry_number_display).to eq('—')
    end
  end

  describe '#invoice_number_or_draft' do
    it 'retourne le numéro quand présent' do
      invoice = build(:invoice, invoice_number: 'VTE2026/0001')
      presenter = described_class.new(invoice)
      expect(presenter.invoice_number_or_draft).to eq('VTE2026/0001')
    end

    it 'retourne Brouillon quand pas de numéro' do
      invoice = build(:invoice, invoice_number: nil)
      presenter = described_class.new(invoice)
      expect(presenter.invoice_number_or_draft).to eq('Draft')
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
      expect(presenter.type_label).to eq('Customer')
    end

    it 'retourne Fournisseur pour supplier' do
      invoice = build(:invoice, invoice_type: :supplier)
      presenter = described_class.new(invoice)
      expect(presenter.type_label).to eq('Supplier')
    end
  end

  describe '#status_label' do
    it { expect(described_class.new(build(:invoice, status: :draft)).status_label).to eq('Draft') }
    it { expect(described_class.new(build(:invoice, status: :posted)).status_label).to eq('Posted') }
    it { expect(described_class.new(build(:invoice, status: :paid)).status_label).to eq('Paid') }
    it { expect(described_class.new(build(:invoice, status: :cancelled)).status_label).to eq('Cancelled') }
  end

  describe '#status_badge_variant' do
    it { expect(described_class.new(build(:invoice, status: :draft)).status_badge_variant).to eq(:default) }
    it { expect(described_class.new(build(:invoice, status: :posted)).status_badge_variant).to eq(:success) }
    it { expect(described_class.new(build(:invoice, status: :paid)).status_badge_variant).to eq(:success) }
    it { expect(described_class.new(build(:invoice, status: :cancelled)).status_badge_variant).to eq(:danger) }
  end
end
