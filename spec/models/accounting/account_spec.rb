require 'rails_helper'

RSpec.describe Accounting::Account, type: :model do
  describe 'validations' do
    subject { build(:account) }

    it { should validate_presence_of(:code) }
    it { should validate_presence_of(:label_fr) }
    it { should validate_presence_of(:account_class) }
    it { should validate_presence_of(:account_type) }
    it { should validate_presence_of(:normal_balance) }
    it { should validate_uniqueness_of(:code).ignoring_case_sensitivity }
    it { should validate_inclusion_of(:account_class).in_range(1..7) }
  end

  describe 'enums' do
    it { should define_enum_for(:account_type)
           .with_values(asset: 0, liability: 1, equity: 2, revenue: 3, expense: 4) }
    it { should define_enum_for(:normal_balance)
           .with_values(debit: 0, credit: 1) }
  end

  describe 'scopes' do
    let!(:active_account)   { create(:account, active: true) }
    let!(:inactive_account) { create(:account, active: false) }

    it '.active retourne uniquement les comptes actifs' do
      expect(Accounting::Account.active).to include(active_account)
      expect(Accounting::Account.active).not_to include(inactive_account)
    end

    it '.leaf retourne uniquement les comptes feuilles' do
      leaf   = create(:account, is_leaf: true)
      parent = create(:account, is_leaf: false)
      expect(Accounting::Account.leaf).to include(leaf)
      expect(Accounting::Account.leaf).not_to include(parent)
    end
  end

  describe '#full_label' do
    it 'retourne le code et le libellé' do
      account = build(:account, code: '604000', label_fr: 'Services divers')
      expect(account.full_label).to eq('604000 — Services divers')
    end
  end

  describe 'tree structure' do
    it 'peut avoir un compte parent' do
      parent = create(:account, code: '600000', is_leaf: false)
      child  = create(:account, code: '604000', parent_id: parent.id)
      expect(child.parent).to eq(parent)
    end
  end
end
