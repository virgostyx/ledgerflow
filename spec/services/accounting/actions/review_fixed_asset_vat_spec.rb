require 'rails_helper'

RSpec.describe Accounting::Actions::ReviewFixedAssetVat, type: :service do
  include_context 'with_open_fiscal_year'
  include_context 'with_pcmn_accounts'

  let!(:misc_journal) { create(:journal, journal_type: :misc) }

  def fiscal_year_for(year)
    create(:fiscal_year, entity: entity, year: year, status: :closed,
           start_date: Date.new(year, 1, 1), end_date: Date.new(year, 12, 31))
  end

  describe '.call — revue annuelle' do
    let(:asset) do
      create(:fixed_asset, entity: entity, asset_category: :movable,
             acquisition_date: Date.new(2024, 6, 1), vat_amount_initial: '1000.00',
             prorata_at_acquisition: '80.00')
    end

    it "ne crée aucune écriture si l écart de prorata est sous le seuil de 10 points" do
      result = described_class.call(fixed_asset: asset, fiscal_year: fiscal_year_for(2025), final_prorata_rate: BigDecimal('85'))
      expect(result).to be_success
      expect(result[:journal_entry]).to be_nil
    end

    it "régularise en faveur de l entité si le prorata final est nettement plus élevé" do
      # tranche = 1000/5 = 200 ; écart = 95-80 = 15 points > seuil ; ajustement = 200*15% = 30
      result = described_class.call(fixed_asset: asset, fiscal_year: fiscal_year_for(2025), final_prorata_rate: BigDecimal('95'))
      expect(result).to be_success
      entry = result[:journal_entry]
      expect(entry).to be_posted

      deductible_line = entry.lines.find { |l| l.account == account_411 }
      expect(deductible_line.debit).to eq(BigDecimal('30.00'))
      expect(deductible_line.vat_code).to eq(62)
    end

    it "régularise en défaveur de l entité si le prorata final est nettement plus bas" do
      # écart = 60-80 = -20 points ; ajustement = 200*-20% = -40 (à reverser)
      result = described_class.call(fixed_asset: asset, fiscal_year: fiscal_year_for(2025), final_prorata_rate: BigDecimal('60'))
      entry = result[:journal_entry]

      deductible_line = entry.lines.find { |l| l.account == account_411 }
      expect(deductible_line.credit).to eq(BigDecimal('40.00'))
      expect(deductible_line.vat_code).to eq(61)
    end

    it "l écriture de révision est équilibrée" do
      result = described_class.call(fixed_asset: asset, fiscal_year: fiscal_year_for(2025), final_prorata_rate: BigDecimal('95'))
      entry = result[:journal_entry]
      expect(entry.lines.sum(:debit)).to eq(entry.lines.sum(:credit))
    end

    it "ne fait rien si l année est hors période de révision" do
      result = described_class.call(fixed_asset: asset, fiscal_year: fiscal_year_for(2030), final_prorata_rate: BigDecimal('95'))
      expect(result[:journal_entry]).to be_nil
    end
  end

  describe '.call — cession en cours de période de révision' do
    let(:asset) do
      create(:fixed_asset, entity: entity, asset_category: :movable,
             acquisition_date: Date.new(2024, 6, 1), vat_amount_initial: '1000.00',
             prorata_at_acquisition: '80.00', disposed_on: Date.new(2026, 3, 1))
    end

    it "régularise les années restantes en une fois, comme si l usage était taxé à 100%" do
      # période 2024-2028, cession en 2026 -> années restantes 2026,2027,2028 = 3
      # tranche 200 x 3 ans x (100-80)% = 120
      result = described_class.call(fixed_asset: asset, fiscal_year: fiscal_year, final_prorata_rate: nil)
      expect(result).to be_success
      entry = result[:journal_entry]

      deductible_line = entry.lines.find { |l| l.account == account_411 }
      expect(deductible_line.debit).to eq(BigDecimal('120.00'))
      expect(deductible_line.vat_code).to eq(62)
    end

    it "applique la régularisation même si l écart est sous le seuil de 10 points (règle obligatoire, pas de tolérance)" do
      asset.update!(prorata_at_acquisition: '95.00')
      # tranche 200 x 3 x (100-95)% = 30, sous le seuil de 10 points mais quand même régularisé
      result = described_class.call(fixed_asset: asset, fiscal_year: fiscal_year, final_prorata_rate: nil)
      expect(result[:journal_entry]).not_to be_nil
    end
  end
end
