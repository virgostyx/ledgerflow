require 'rails_helper'

RSpec.describe Accounting::AccountPresenter, type: :presenter do
  let(:account) { build(:account, code: '604000', label_fr: 'Services et biens divers') }

  describe '#full_label' do
    it 'retourne code em-dash libellé' do
      expect(described_class.new(account).full_label).to eq('604000 — Services et biens divers')
    end
  end

  describe '#option_label' do
    it 'retourne le même format pour les options de select' do
      expect(described_class.new(account).option_label).to eq('604000 — Services et biens divers')
    end
  end
end
