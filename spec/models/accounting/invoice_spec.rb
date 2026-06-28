require 'rails_helper'

RSpec.describe Accounting::Invoice, type: :model do
  include_context 'with entity'

  describe 'associations' do
    it { should belong_to(:partner).class_name('Accounting::Partner') }
    it { should belong_to(:fiscal_year).class_name('Accounting::FiscalYear') }
    it { should belong_to(:journal_entry).class_name('Accounting::JournalEntry').optional }
    it { should have_many(:lines).class_name('Accounting::InvoiceLine').dependent(:destroy) }
  end

  describe 'validations' do
    subject { build(:invoice) }

    it { should validate_presence_of(:invoice_type) }
    it { should validate_presence_of(:invoice_date) }
    it { should validate_presence_of(:partner) }
  end

  describe 'enums' do
    it { should define_enum_for(:invoice_type).with_values(customer: 0, supplier: 1) }
    it { should define_enum_for(:status).with_values(draft: 0, posted: 1, paid: 2, cancelled: 3) }
  end

  describe 'statuts AASM' do
    let(:invoice) { create(:invoice) }

    it 'démarre en draft' do
      expect(invoice).to be_draft
    end

    it 'peut passer en posted via post!' do
      invoice.post!
      expect(invoice.reload).to be_posted
    end

    it 'peut passer en paid depuis posted' do
      invoice.update!(status: :posted)
      invoice.pay!
      expect(invoice.reload).to be_paid
    end

    it 'peut être annulé depuis draft' do
      invoice.cancel!
      expect(invoice.reload).to be_cancelled
    end

    it 'ne peut pas être annulé depuis posted' do
      invoice.update!(status: :posted)
      expect { invoice.cancel! }.to raise_error(AASM::InvalidTransition)
    end
  end

  describe 'scopes' do
    include_context 'with_open_fiscal_year'

    let!(:draft_invoice)     { create(:invoice, :draft,     fiscal_year: fiscal_year) }
    let!(:posted_invoice)    { create(:invoice, :posted,    fiscal_year: fiscal_year) }
    let!(:customer_invoice)  { create(:invoice, :customer,  fiscal_year: fiscal_year) }
    let!(:supplier_invoice)  { create(:invoice, :supplier,  fiscal_year: fiscal_year) }

    it '.draft retourne les factures brouillon' do
      expect(Accounting::Invoice.draft).to include(draft_invoice)
    end

    it '.posted retourne les factures validées' do
      expect(Accounting::Invoice.posted).to include(posted_invoice)
    end

    it '.customer retourne les factures clients' do
      expect(Accounting::Invoice.customer).to include(customer_invoice)
    end

    it '.supplier retourne les factures fournisseurs' do
      expect(Accounting::Invoice.supplier).to include(supplier_invoice)
    end
  end

  describe '#compute_totals' do
    include_context 'with_open_fiscal_year'

    let(:invoice) { create(:invoice, fiscal_year: fiscal_year) }
    let(:account) { create(:account) }

    before do
      create(:invoice_line, invoice: invoice, account: account,
             quantity: 2, unit_price: '100.00', vat_rate: '21.00')
      create(:invoice_line, invoice: invoice, account: account,
             quantity: 1, unit_price: '50.00', vat_rate: '6.00')
    end

    it 'calcule correctement subtotal_excl_vat' do
      invoice.compute_totals
      expect(invoice.subtotal_excl_vat).to eq(BigDecimal('250.00'))
    end

    it 'calcule correctement vat_amount' do
      invoice.compute_totals
      # 200 * 21% + 50 * 6% = 42 + 3 = 45
      expect(invoice.vat_amount).to eq(BigDecimal('45.00'))
    end

    it 'calcule correctement total_incl_vat' do
      invoice.compute_totals
      expect(invoice.total_incl_vat).to eq(BigDecimal('295.00'))
    end
  end
end
