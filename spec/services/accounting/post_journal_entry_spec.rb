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
      expect(result.message).to include('Unbalanced entry')
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

  describe '.call — période verrouillée (F01)' do
    let(:month_start) { fiscal_year.start_date }
    let(:month_end)   { fiscal_year.start_date.end_of_month }
    let!(:lock)       { create(:period_lock, starts_on: month_start, ends_on: month_end) }

    def post_dated(date)
      described_class.call(entry: create(:journal_entry, :with_balanced_lines, fiscal_year: fiscal_year, entry_date: date))
    end

    it 'refuse une écriture datée le premier jour de la période verrouillée' do
      expect(post_dated(month_start)).to be_failure
    end

    it 'refuse une écriture datée le dernier jour de la période verrouillée' do
      result = post_dated(month_end)

      expect(result).to be_failure
      expect(result.message).to include('is locked')
    end

    it 'accepte une écriture datée le premier jour qui suit la période' do
      expect(post_dated(month_end + 1)).to be_success
    end

    it 'ne valide pas le brouillon refusé' do
      entry = create(:journal_entry, :with_balanced_lines, fiscal_year: fiscal_year, entry_date: month_start)

      expect { described_class.call(entry: entry) }.not_to change { entry.reload.status }
    end

    it 'accepte de nouveau après le déverrouillage' do
      lock.update!(status: :unlocked)

      expect(post_dated(month_start)).to be_success
    end
  end

  describe '.call — quatre yeux (F01)' do
    let(:author)   { create(:user) }
    let(:reviewer) { create(:user) }
    let(:entry)    { create(:journal_entry, :with_balanced_lines, fiscal_year: fiscal_year, created_by: author) }

    def post_as(user) = Current.set(user: user) { described_class.call(entry: entry) }

    context 'quand l option est active sans seuil' do
      before { entity.update!(four_eyes: true) }

      it 'refuse que l auteur valide sa propre écriture' do
        result = post_as(author)

        expect(result).to be_failure
        expect(result.message).to match(/another person/i)
        expect(entry.reload).to be_draft
      end

      it 'accepte qu un autre utilisateur la valide' do
        expect(post_as(reviewer)).to be_success
      end

      it 'ne bloque pas une écriture sans auteur (générée par le système)' do
        entry.update_columns(created_by_id: nil)

        expect(post_as(author)).to be_success
      end

      it 'ne bloque pas un traitement sans utilisateur (tâche de fond, API)' do
        expect(Current.set(user: nil) { described_class.call(entry: entry) }).to be_success
      end
    end

    context 'quand l option est inactive' do
      it 'laisse l auteur valider' do
        expect(post_as(author)).to be_success
      end
    end

    context 'avec un seuil' do
      let(:total) { entry.lines.sum(:debit) }

      before { entity.update!(four_eyes: true) }

      it 'applique la règle à partir du seuil (borne incluse)' do
        entity.update!(four_eyes_threshold: total)

        expect(post_as(author)).to be_failure
      end

      it 'laisse l auteur valider sous le seuil' do
        entity.update!(four_eyes_threshold: total + 0.01)

        expect(post_as(author)).to be_success
      end
    end
  end
end
