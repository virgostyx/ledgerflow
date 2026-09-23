require 'rails_helper'

RSpec.describe Accounting::BuildIntervatXml do
  include_context 'with_open_fiscal_year'

  before { entity.update!(vat_number: 'BE0123456789', legal_name: 'Acme SA') }

  let(:declaration) do
    create(:vat_declaration, fiscal_year: fiscal_year, entity: entity,
           period_type: :quarterly, period_start: Date.new(2025, 1, 1), period_end: Date.new(2025, 3, 31),
           grids: { '01' => '1000.00', '54' => '210.00' })
  end

  subject(:xml) { described_class.new(declaration).build }

  it 'retourne une chaîne XML' do
    expect(xml).to be_a(String)
  end

  it 'produit du XML valide parsable par Nokogiri' do
    doc = Nokogiri::XML(xml) { |cfg| cfg.strict }
    expect(doc.errors).to be_empty
  end

  it "contient le numéro de TVA de l entité (sans le préfixe pays)" do
    expect(xml).to include('0123456789')
  end

  it 'contient un code de période trimestrielle' do
    expect(xml).to include('2025Q1')
  end

  it 'contient chaque montant de grille avec son numéro' do
    expect(xml).to include('GridNumber="01"').and include('1000.00')
    expect(xml).to include('GridNumber="54"').and include('210.00')
  end

  context 'période mensuelle' do
    let(:declaration) do
      create(:vat_declaration, fiscal_year: fiscal_year, entity: entity,
             period_type: :monthly, period_start: Date.new(2025, 4, 1), period_end: Date.new(2025, 4, 30),
             grids: {})
    end

    it 'contient un code de période AAAA-MM' do
      expect(xml).to include('2025-04')
    end
  end
end
