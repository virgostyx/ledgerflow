require 'rails_helper'

RSpec.describe Accounting::PostInvoice, type: :service do
  include_context 'with_open_fiscal_year'
  include_context 'with_pcmn_accounts'

  let!(:sale_journal)     { create(:journal, :sale) }
  let!(:purchase_journal) { create(:journal, :purchase) }

  describe '.call — facture client' do
    let(:invoice) { create(:invoice, :with_lines, invoice_type: :customer, fiscal_year: fiscal_year) }
    subject(:result) { described_class.call(invoice: invoice) }

    it 'retourne un contexte de succès' do
      expect(result).to be_success
    end

    it 'passe la facture en posted' do
      expect { result }.to change { invoice.reload.status }
        .from('draft').to('posted')
    end

    it 'assigne un numéro de facture' do
      result
      expect(invoice.reload.invoice_number).to be_present
    end

    it 'crée une écriture comptable liée' do
      expect { result }.to change(Accounting::JournalEntry, :count).by(1)
      expect(invoice.reload.journal_entry).to be_present
    end

    it 'l écriture est équilibrée' do
      result
      entry = invoice.reload.journal_entry
      total_debit  = entry.lines.sum(:debit)
      total_credit = entry.lines.sum(:credit)
      expect(total_debit).to eq(total_credit)
    end

    it 'est atomique : rollback si une action échoue' do
      allow(Accounting::Actions::GenerateInvoiceJournalEntry)
        .to receive(:execute).and_raise(StandardError, 'simulated error')
      expect { result }.not_to change { invoice.reload.status }
    end
  end

  describe '.call — facture fournisseur' do
    let(:invoice) { create(:invoice, :with_lines, invoice_type: :supplier, fiscal_year: fiscal_year) }
    subject(:result) { described_class.call(invoice: invoice) }

    it 'retourne un contexte de succès' do
      expect(result).to be_success
    end

    it 'utilise le journal achats' do
      result
      entry = invoice.reload.journal_entry
      expect(entry.journal.journal_type).to eq('purchase')
    end
  end

  describe '.call — facture déjà validée' do
    let(:invoice) { create(:invoice, :posted, :with_lines, fiscal_year: fiscal_year) }
    subject(:result) { described_class.call(invoice: invoice) }

    it 'retourne un échec' do
      expect(result).to be_failure
    end

    it 'ne crée pas d écriture supplémentaire' do
      expect { result }.not_to change(Accounting::JournalEntry, :count)
    end
  end

  describe '.call — facture client TVA 0%' do
    let(:invoice) do
      inv = create(:invoice, invoice_type: :customer, fiscal_year: fiscal_year)
      create(:invoice_line, invoice: inv, account: account_700,
             quantity: 1, unit_price: '500.00', vat_rate: '0.00')
      inv.compute_totals
      inv.save!
      inv
    end
    subject(:result) { described_class.call(invoice: invoice) }

    it 'retourne un succès sans ligne TVA' do
      expect(result).to be_success
    end

    it 'l écriture n a que 2 lignes (débit client + crédit produit)' do
      result
      expect(invoice.reload.journal_entry.lines.count).to eq(2)
    end
  end

  describe '.call — facture sans lignes' do
    let(:invoice) { create(:invoice, :draft, fiscal_year: fiscal_year) }
    subject(:result) { described_class.call(invoice: invoice) }

    it 'retourne un échec' do
      expect(result).to be_failure
    end

    it 'inclut un message d erreur' do
      expect(result.message).to be_present
    end
  end

  describe '.call — sans journal de vente' do
    let(:invoice) { create(:invoice, :with_lines, invoice_type: :customer, fiscal_year: fiscal_year) }
    subject(:result) { described_class.call(invoice: invoice) }

    before do
      allow(Accounting::Journal).to receive(:active).and_return(
        double(find_by: nil)
      )
    end

    it 'retourne un échec si aucun journal actif n est trouvé' do
      expect(result).to be_failure
    end
  end

  describe '.call — rescue StandardError' do
    let(:invoice) { create(:invoice, :with_lines, invoice_type: :customer, fiscal_year: fiscal_year) }

    it 'renvoie un contexte d échec si une erreur inattendue survient' do
      allow(ApplicationRecord).to receive(:transaction).and_raise(RuntimeError, 'DB down')
      result = described_class.call(invoice: invoice)
      expect(result).to be_failure
      expect(result.message).to include('DB down')
    end
  end
end
