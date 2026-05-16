require 'rails_helper'

RSpec.describe Accounting::VatDeclaration, type: :model do
  include_context 'with_open_fiscal_year'

  describe 'associations' do
    it { should belong_to(:fiscal_year).class_name('Accounting::FiscalYear') }
  end

  describe 'validations' do
    subject { build(:vat_declaration, fiscal_year: fiscal_year) }

    it { should validate_presence_of(:period_start) }
    it { should validate_presence_of(:period_end) }
    it { should validate_presence_of(:period_type) }

    it 'rejette si period_end < period_start' do
      decl = build(:vat_declaration, fiscal_year: fiscal_year,
                   period_start: Date.new(2025, 4, 1),
                   period_end:   Date.new(2025, 3, 31))
      expect(decl).not_to be_valid
      expect(decl.errors[:period_end]).to be_present
    end
  end

  describe 'enums' do
    it { should define_enum_for(:status).with_values(draft: 0, submitted: 1, accepted: 2) }
    it { should define_enum_for(:period_type).with_values(monthly: 0, quarterly: 1) }
  end

  describe 'defaults' do
    it 'démarre en statut draft' do
      decl = build(:vat_declaration, fiscal_year: fiscal_year)
      expect(decl.status).to eq('draft')
    end

    it 'a des grilles vides par défaut' do
      decl = build(:vat_declaration, fiscal_year: fiscal_year)
      expect(decl.grids).to eq({})
    end
  end

  describe '#grid_total' do
    let(:decl) do
      build(:vat_declaration, fiscal_year: fiscal_year,
            grids: { '01' => '1000.00', '54' => '210.00', '71' => '800.00' })
    end

    it 'retourne le montant pour le code grille' do
      expect(decl.grid_total('01')).to eq(BigDecimal('1000.00'))
    end

    it 'retourne 0 pour un code absent' do
      expect(decl.grid_total('99')).to eq(BigDecimal('0'))
    end
  end
end
