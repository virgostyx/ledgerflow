require 'rails_helper'

RSpec.describe Accounting::FixedAsset, type: :model do
  include_context 'with entity'

  describe 'validations' do
    subject { build(:fixed_asset) }

    it { should validate_presence_of(:description) }
    it { should validate_presence_of(:acquisition_date) }
    it { should validate_presence_of(:vat_amount_initial) }
    it { should validate_numericality_of(:vat_amount_initial).is_greater_than_or_equal_to(0) }
    it { should validate_numericality_of(:prorata_at_acquisition).is_greater_than_or_equal_to(0).is_less_than_or_equal_to(100) }
  end

  describe 'enums' do
    it { should define_enum_for(:asset_category).with_values(movable: 0, immovable: 1) }
  end

  describe '#review_period_years' do
    it 'vaut 5 ans pour un bien meuble' do
      expect(build(:fixed_asset, asset_category: :movable).review_period_years).to eq(5)
    end

    it 'vaut 15 ans pour un immeuble' do
      expect(build(:fixed_asset, asset_category: :immovable).review_period_years).to eq(15)
    end
  end

  describe '#annual_tranche' do
    it 'divise la TVA initiale par la période de révision' do
      asset = build(:fixed_asset, asset_category: :movable, vat_amount_initial: '1000.00')
      expect(asset.annual_tranche).to eq(BigDecimal('200.00'))
    end
  end

  describe '#under_review?' do
    let(:asset) { build(:fixed_asset, asset_category: :movable, acquisition_date: Date.new(2024, 6, 1)) }

    it "est vrai pour l année d acquisition" do
      expect(asset.under_review?(2024)).to be true
    end

    it "est vrai pour la dernière année de la période (4 ans plus tard pour un meuble)" do
      expect(asset.under_review?(2028)).to be true
    end

    it "est faux après la fin de la période de révision" do
      expect(asset.under_review?(2029)).to be false
    end

    it "est faux avant l année d acquisition" do
      expect(asset.under_review?(2023)).to be false
    end

    context 'bien cédé' do
      let(:asset) { build(:fixed_asset, asset_category: :movable, acquisition_date: Date.new(2024, 6, 1), disposed_on: Date.new(2026, 3, 1)) }

      it "est faux pour l année suivant la cession" do
        expect(asset.under_review?(2027)).to be false
      end

      it "est vrai pour l année de la cession elle-même" do
        expect(asset.under_review?(2026)).to be true
      end
    end
  end

  describe '#remaining_review_years' do
    let(:asset) { build(:fixed_asset, asset_category: :movable, acquisition_date: Date.new(2024, 6, 1)) }

    it "compte l année en cours et les années restantes jusqu à la fin de la période" do
      # 2024..2028 = 5 ans ; à partir de 2026 il reste 2026,2027,2028 = 3
      expect(asset.remaining_review_years(2026)).to eq(3)
    end
  end

  describe 'depreciation setup' do
    def account(code, klass: 2, type: :asset)
      Accounting::Account.find_by(code: code) ||
        create(:account, code: code, account_class: klass, account_type: type, normal_balance: type == :asset ? :debit : :credit)
    end

    it 'reste valide sans données d amortissement (immobilisation suivie pour la seule révision de TVA)' do
      expect(build(:fixed_asset)).to be_valid
    end

    it 'accepte une TVA initiale nulle' do
      expect(build(:fixed_asset, :depreciable, vat_amount_initial: 0)).to be_valid
    end

    it 'est valide avec une configuration complète' do
      expect(build(:fixed_asset, :depreciable)).to be_valid
    end

    it 'exige un compte d immobilisation et une durée quand une valeur d acquisition est saisie' do
      asset = build(:fixed_asset, acquisition_value: '1000.00')
      expect(asset).not_to be_valid
      expect(asset.errors[:asset_account]).to be_present
      expect(asset.errors[:useful_life_years]).to be_present
    end

    it 'rejette une valeur d acquisition négative ou nulle' do
      expect(build(:fixed_asset, :depreciable, acquisition_value: 0)).not_to be_valid
      expect(build(:fixed_asset, :depreciable, acquisition_value: -1)).not_to be_valid
    end

    it 'rejette une durée non entière ou nulle' do
      expect(build(:fixed_asset, :depreciable, useful_life_years: 0)).not_to be_valid
      expect(build(:fixed_asset, :depreciable, useful_life_years: 2.5)).not_to be_valid
    end

    it 'rejette une valeur résiduelle négative ou supérieure à la valeur d acquisition' do
      expect(build(:fixed_asset, :depreciable, residual_value: -1)).not_to be_valid
      expect(build(:fixed_asset, :depreciable, residual_value: '12000.01')).not_to be_valid
      expect(build(:fixed_asset, :depreciable, residual_value: '12000.00')).to be_valid
    end

    %w[220100 250100 604000].each do |code|
      it "rejette le compte #{code}, non amortissable" do
        asset = build(:fixed_asset, :depreciable, asset_account: account(code, klass: code[0].to_i, type: code.start_with?('6') ? :expense : :asset))
        expect(asset).not_to be_valid
        expect(asset.errors[:asset_account]).to be_present
      end
    end

    it 'a la méthode linéaire par défaut' do
      expect(build(:fixed_asset)).to be_depreciation_method_linear
    end

    it { should define_enum_for(:depreciation_method).with_values(linear: 0).with_prefix(:depreciation_method) }
  end

  describe '#depreciable?' do
    it 'est faux sans configuration' do
      expect(build(:fixed_asset).depreciable?).to be false
    end

    it 'est vrai avec une configuration complète' do
      expect(build(:fixed_asset, :depreciable).depreciable?).to be true
    end
  end

  describe '#depreciation_accounts' do
    {
      '210200' => %w[630100 219000],
      '220200' => %w[630200 229000],
      '230200' => %w[630200 239000],
      '240200' => %w[630200 249000]
    }.each do |code, (expense, contra)|
      it "déduit #{expense} et #{contra} du compte #{code}" do
        account = Accounting::Account.find_by(code: code) || create(:account, code: code, account_class: 2, account_type: :asset, normal_balance: :debit)
        asset = build(:fixed_asset, :depreciable, asset_account: account)

        expect(asset.depreciation_accounts).to eq(expense: expense, accumulated: contra)
      end
    end
  end

  describe '#depreciation_for' do
    def fiscal_year(year, start_date: Date.new(year, 1, 1), end_date: Date.new(year, 12, 31))
      build(:fiscal_year, year: year, start_date: start_date, end_date: end_date)
    end

    let(:asset) { build(:fixed_asset, :depreciable) } # 12 000, 60 months from October 2026: 200/month

    it 'amortit au prorata des mois restants la première année (octobre à décembre : 3 mois)' do
      expect(asset.depreciation_for(fiscal_year(2026))).to eq(BigDecimal('600.00'))
    end

    it 'amortit 12 mois les années pleines' do
      expect(asset.depreciation_for(fiscal_year(2027))).to eq(BigDecimal('2400.00'))
      expect(asset.depreciation_for(fiscal_year(2030))).to eq(BigDecimal('2400.00'))
    end

    it 'solde la dernière année (9 mois) puis s arrête' do
      expect(asset.depreciation_for(fiscal_year(2031))).to eq(BigDecimal('1800.00'))
      expect(asset.depreciation_for(fiscal_year(2032))).to eq(BigDecimal('0'))
    end

    it 'vaut zéro avant la mise en service' do
      expect(asset.depreciation_for(fiscal_year(2025))).to eq(BigDecimal('0'))
    end

    it 'commence le mois de la mise en service, pas celui de l acquisition' do
      asset.in_service_date = Date.new(2027, 2, 1)
      expect(asset.depreciation_for(fiscal_year(2026))).to eq(BigDecimal('0'))
      expect(asset.depreciation_for(fiscal_year(2027))).to eq(BigDecimal('2200.00')) # février à décembre : 11 mois
    end

    it 'prend la date d acquisition quand il n y a pas de date de mise en service' do
      asset.in_service_date = nil
      expect(asset.depreciation_for(fiscal_year(2026))).to eq(BigDecimal('600.00')) # octobre à décembre depuis le 1er octobre : 3 mois
    end

    it 'déduit la valeur résiduelle de la base' do
      asset.residual_value = 2000
      expect(asset.depreciation_for(fiscal_year(2027))).to eq(BigDecimal('2000.00')) # (12 000 - 2 000) / 5
    end

    it 'suit un exercice décalé' do
      broken = fiscal_year(2027, start_date: Date.new(2026, 4, 1), end_date: Date.new(2027, 3, 31))
      # octobre 2026 à mars 2027 : 6 mois
      expect(asset.depreciation_for(broken)).to eq(BigDecimal('1200.00'))
    end

    it 'arrondit sans dérive : la somme du plan égale exactement la base' do
      odd = build(:fixed_asset, :depreciable, acquisition_value: '1000.00', useful_life_years: 3, in_service_date: Date.new(2026, 1, 1))
      amounts = (2026..2028).map { |y| odd.depreciation_for(fiscal_year(y)) }

      expect(amounts).to eq([ BigDecimal('333.33'), BigDecimal('333.34'), BigDecimal('333.33') ])
      expect(amounts.sum).to eq(BigDecimal('1000.00'))
    end

    it 'cesse au mois de la cession, inclus' do
      asset.disposed_on = Date.new(2028, 3, 20)
      expect(asset.depreciation_for(fiscal_year(2028))).to eq(BigDecimal('600.00')) # janvier à mars : 3 mois
      expect(asset.depreciation_for(fiscal_year(2029))).to eq(BigDecimal('0'))
    end

    it 'vaut zéro pour une immobilisation non configurée' do
      expect(build(:fixed_asset).depreciation_for(fiscal_year(2026))).to eq(BigDecimal('0'))
    end
  end

  describe '#depreciation_plan' do
    it 'liste une ligne par année civile avec le cumul et la valeur nette comptable' do
      plan = build(:fixed_asset, :depreciable).depreciation_plan

      expect(plan.map { |r| r[:year] }).to eq((2026..2031).to_a)
      expect(plan.map { |r| r[:amount] }).to eq(%w[600 2400 2400 2400 2400 1800].map { |v| BigDecimal(v) })
      expect(plan.last).to include(accumulated: BigDecimal('12000'), net_book_value: BigDecimal('0'))
      expect(plan.first).to include(accumulated: BigDecimal('600'), net_book_value: BigDecimal('11400'))
    end

    it 'garde la valeur résiduelle comme valeur nette finale' do
      plan = build(:fixed_asset, :depreciable, residual_value: 2000).depreciation_plan
      expect(plan.last[:net_book_value]).to eq(BigDecimal('2000'))
    end

    it 'est vide pour une immobilisation non configurée' do
      expect(build(:fixed_asset).depreciation_plan).to eq([])
    end
  end

  describe 'disposal' do
    it { should belong_to(:disposal_journal_entry).class_name('Accounting::JournalEntry').optional }

    def exit_entry = create(:journal_entry)

    context 'sur une immobilisation configurée en amortissement' do
      let(:asset) { create(:fixed_asset, :depreciable) }

      it 'refuse de saisir la date de cession librement' do
        asset.disposed_on = Date.new(2027, 3, 20)

        expect(asset).not_to be_valid
        expect(asset.errors[:disposed_on]).to be_present
      end

      it 'accepte la date de cession quand elle vient avec l écriture de sortie' do
        asset.assign_attributes(disposed_on: Date.new(2027, 3, 20), disposal_journal_entry: exit_entry)
        expect(asset).to be_valid
      end

      it 'refuse de modifier ou d effacer la date de cession après coup' do
        asset.update!(disposed_on: Date.new(2027, 3, 20), disposal_journal_entry: exit_entry)

        asset.disposed_on = Date.new(2027, 4, 20)
        expect(asset).not_to be_valid

        asset.disposed_on = nil
        expect(asset).not_to be_valid
      end

      it 'reste modifiable pour le reste (description) après la cession' do
        asset.update!(disposed_on: Date.new(2027, 3, 20), disposal_journal_entry: exit_entry)
        expect(asset.update(description: 'Renamed')).to be true
      end
    end

    context 'sur une immobilisation suivie pour la seule révision de TVA' do
      it 'garde la saisie libre de la date de cession' do
        asset = create(:fixed_asset)
        expect(asset.update(disposed_on: Date.new(2027, 3, 20))).to be true
      end
    end

    describe '#disposed?' do
      it 'suit la date de cession' do
        expect(build(:fixed_asset).disposed?).to be false
        expect(build(:fixed_asset, disposed_on: Date.new(2027, 3, 20)).disposed?).to be true
      end
    end
  end
end
