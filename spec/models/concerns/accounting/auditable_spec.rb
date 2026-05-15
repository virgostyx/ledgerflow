require 'rails_helper'

RSpec.describe Accounting::Auditable, type: :model do
  # Testé via Accounting::Account qui inclura le concern
  let!(:account) { create(:account, code: 'AUD001', label_fr: 'Compte auditable') }

  describe 'PaperTrail versioning' do
    it 'crée une version lors de la création' do
      expect(account.versions.count).to eq(1)
      expect(account.versions.last.event).to eq('create')
    end

    it 'crée une version lors d une mise à jour' do
      expect {
        account.update!(label_fr: 'Libellé modifié')
      }.to change { account.versions.count }.by(1)
      expect(account.versions.last.event).to eq('update')
    end

    it 'enregistre la valeur précédente dans la version' do
      original_label = account.label_fr
      account.update!(label_fr: 'Nouveau libellé')
      previous = account.versions.last.reify
      expect(previous.label_fr).to eq(original_label)
    end

    it 'permet de revenir à une version précédente (reify)' do
      account.update!(label_fr: 'V2')
      previous = account.versions.last.reify
      expect(previous.label_fr).to eq('Compte auditable')
    end
  end
end
