require 'rails_helper'

RSpec.describe Accounting::MonetaryPrecision, type: :model do
  # Testé via Accounting::Account qui inclut le concern (champs balance_debit/credit)
  subject(:account) { build(:account) }

  describe 'coercition automatique vers BigDecimal' do
    it 'convertit automatiquement un Float en BigDecimal' do
      account.balance_debit = 100.5
      account.valid?
      expect(account.balance_debit).to be_a(BigDecimal)
    end

    it 'accepte un BigDecimal sans modification' do
      account.balance_debit = BigDecimal('100.50')
      account.valid?
      expect(account.balance_debit).to eq(BigDecimal('100.50'))
    end

    it 'convertit une string numérique en BigDecimal' do
      account.balance_debit = '100.50'
      account.valid?
      expect(account.balance_debit).to be_a(BigDecimal)
    end

    it 'préserve la précision à 2 décimales' do
      account.balance_credit = '1234.56'
      account.valid?
      expect(account.balance_credit).to eq(BigDecimal('1234.56'))
    end
  end
end
