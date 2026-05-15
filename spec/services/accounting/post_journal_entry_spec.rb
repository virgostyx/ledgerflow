require 'rails_helper'

RSpec.describe Accounting::PostJournalEntry, type: :service do
  include_context 'with_open_fiscal_year'

  describe '.call — chemin de succès' do
    let(:entry)  { create(:journal_entry, :with_balanced_lines, fiscal_year: fiscal_year) }
    subject(:result) { described_class.call(entry: entry) }

    it 'retourne un contexte de succès' do
      expect(result).to be_success
    end

    it 'passe le statut en posted' do
      expect { result }.to change { entry.reload.status }
        .from('draft').to('posted')
    end

    it 'crée un audit log avec l action post_entry' do
      result
      expect(Accounting::AuditLog.last.action).to eq('post_entry')
    end

    it 'est atomique : rollback si une action échoue' do
      allow(Accounting::Actions::UpdateAccountBalances)
        .to receive(:execute).and_raise(StandardError, 'simulated error')
      expect { result }.not_to change { entry.reload.status }
    end
  end

  describe '.call — échec ValidateBalance' do
    let(:entry)  { create(:journal_entry, :with_unbalanced_lines, fiscal_year: fiscal_year) }
    subject(:result) { described_class.call(entry: entry) }

    it 'retourne un contexte d échec' do
      expect(result).to be_failure
    end

    it 'inclut le message déséquilibré' do
      expect(result.message).to include('déséquilibré')
    end

    it 'ne modifie pas le statut' do
      expect { result }.not_to change { entry.reload.status }
    end
  end

  describe 'idempotence — double soumission' do
    let(:entry) { create(:journal_entry, :with_balanced_lines, fiscal_year: fiscal_year) }

    it 'ne valide qu une seule fois même si appelé deux fois' do
      result1 = described_class.call(entry: entry)
      expect(result1).to be_success

      entry.reload
      result2 = described_class.call(entry: entry)
      expect(result2).to be_failure
    end
  end
end
