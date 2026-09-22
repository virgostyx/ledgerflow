require 'rails_helper'

RSpec.describe Accounting::Invoice, type: :model do
  include_context 'with entity'

  describe 'associations' do
    it { should belong_to(:partner).class_name('Accounting::Partner') }
    it { should belong_to(:fiscal_year).class_name('Accounting::FiscalYear') }
    it { should belong_to(:journal_entry).class_name('Accounting::JournalEntry').optional }
    it { should belong_to(:journal).class_name('Accounting::Journal').optional }
    it { should have_many(:lines).class_name('Accounting::InvoiceLine').dependent(:destroy) }
  end

  describe 'validations' do
    subject { build(:invoice) }

    it { should validate_presence_of(:invoice_type) }
    it { should validate_presence_of(:invoice_date) }
    it { should validate_presence_of(:partner) }
  end

  describe 'cash journal validation' do
    it 'is valid for a supplier invoice with a cash journal' do
      expect(build(:invoice, :supplier, cash_journal: create(:journal, :cash))).to be_valid
    end

    it 'is invalid with a non-cash journal' do
      invoice = build(:invoice, :supplier, cash_journal: create(:journal, :purchase))
      expect(invoice).not_to be_valid
      expect(invoice.errors[:cash_journal]).to be_present
    end

    it 'is valid on a customer invoice' do
      expect(build(:invoice, :customer, cash_journal: create(:journal, :cash))).to be_valid
    end
  end

  describe 'journal type validation' do
    let(:sale_journal)     { create(:journal, :sale) }
    let(:purchase_journal) { create(:journal, :purchase) }

    it 'is valid when a customer invoice uses a sale journal' do
      invoice = build(:invoice, :customer, journal: sale_journal)
      expect(invoice).to be_valid
    end

    it 'is valid when a supplier invoice uses a purchase journal' do
      invoice = build(:invoice, :supplier, journal: purchase_journal)
      expect(invoice).to be_valid
    end

    it 'is invalid when a customer invoice uses a purchase journal' do
      invoice = build(:invoice, :customer, journal: purchase_journal)
      expect(invoice).not_to be_valid
      expect(invoice.errors[:journal]).to be_present
    end

    it 'is invalid when a supplier invoice uses a sale journal' do
      invoice = build(:invoice, :supplier, journal: sale_journal)
      expect(invoice).not_to be_valid
      expect(invoice.errors[:journal]).to be_present
    end

    it 'is valid with no journal (optional)' do
      invoice = build(:invoice, :supplier, journal: nil)
      expect(invoice).to be_valid
    end
  end

  describe 'enums' do
    it { should define_enum_for(:invoice_type).with_values(customer: 0, supplier: 1) }
    it { should define_enum_for(:status).with_values(draft: 0, posted: 1, paid: 2, cancelled: 3, partially_paid: 4) }
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

    it 'passe en partially_paid puis paid, ou revient en posted' do
      invoice.update!(status: :posted)
      invoice.part_pay!
      expect(invoice.reload).to be_partially_paid
      invoice.release!
      expect(invoice.reload).to be_posted
      invoice.part_pay!
      invoice.pay!
      expect(invoice.reload).to be_paid
    end

    it 'ne peut pas être annulé depuis partially_paid' do
      invoice.update!(status: :partially_paid)
      expect { invoice.cancel! }.to raise_error(AASM::InvalidTransition)
    end

    it 'inclut partially_paid dans les filtres unpaid et overdue' do
      invoice.update!(status: :partially_paid, due_date: Date.current - 1)
      expect(described_class.filter_by(unpaid: '1')).to include(invoice)
      expect(described_class.filter_by(overdue: '1')).to include(invoice)
    end

    it 'peut être annulé depuis draft' do
      invoice.cancel!
      expect(invoice.reload).to be_cancelled
    end

    it 'peut être annulé depuis posted' do
      invoice.update!(status: :posted)
      invoice.cancel!
      expect(invoice.reload).to be_cancelled
    end

    it 'ne peut pas être annulé depuis paid' do
      invoice.update!(status: :paid)
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

  describe 'nested attributes for lines' do
    include_context 'with_open_fiscal_year'

    let(:invoice) { create(:invoice, fiscal_year: fiscal_year) }
    let(:account) { create(:account) }

    it 'crée des lignes via lines_attributes' do
      expect {
        invoice.update!(lines_attributes: [
          { description: 'Service A', account_id: account.id,
            quantity: '2', unit_price: '100.00', vat_rate: '21.00', position: 1 }
        ])
      }.to change { invoice.lines.reload.count }.from(0).to(1)
    end

    it 'supprime une ligne via _destroy' do
      line = create(:invoice_line, invoice: invoice, account: account)
      expect {
        invoice.update!(lines_attributes: [{ id: line.id, _destroy: '1' }])
      }.to change { invoice.lines.reload.count }.by(-1)
    end

    it 'ignore les lignes totalement vides (reject_if: :all_blank)' do
      expect {
        invoice.update!(lines_attributes: [
          { description: '', account_id: '', quantity: '', unit_price: '', vat_rate: '', position: '' }
        ])
      }.not_to change { invoice.lines.reload.count }
    end
  end

  describe '#related_journal_entries' do
    include_context 'with_open_fiscal_year'

    let(:invoice) { create(:invoice, fiscal_year: fiscal_year) }
    let(:account) { create(:account) }

    it 'inclut l\'écriture de comptabilisation (journal_entry)' do
      entry = create(:journal_entry, fiscal_year: fiscal_year)
      invoice.update!(journal_entry: entry)

      expect(invoice.related_journal_entries).to contain_exactly(entry)
    end

    it 'inclut les écritures dont une ligne référence la facture via invoice_id' do
      settlement_entry = create(:journal_entry, fiscal_year: fiscal_year)
      ApplicationRecord.connection.execute('SET CONSTRAINTS enforce_double_entry DEFERRED')
      create(:journal_entry_line, :credit, journal_entry: settlement_entry, account: account, invoice: invoice)

      expect(invoice.related_journal_entries).to contain_exactly(settlement_entry)
    end

    it 'combine les deux sans doublon' do
      posting_entry    = create(:journal_entry, fiscal_year: fiscal_year)
      settlement_entry = create(:journal_entry, fiscal_year: fiscal_year)
      invoice.update!(journal_entry: posting_entry)
      ApplicationRecord.connection.execute('SET CONSTRAINTS enforce_double_entry DEFERRED')
      create(:journal_entry_line, :credit, journal_entry: settlement_entry, account: account, invoice: invoice)

      expect(invoice.related_journal_entries).to contain_exactly(posting_entry, settlement_entry)
    end

    it 'retourne une relation vide quand aucune écriture n\'est liée' do
      expect(invoice.related_journal_entries).to be_empty
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
