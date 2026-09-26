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

  it 'contient la période trimestrielle (trimestre et année)' do
    doc = Nokogiri::XML(xml)
    doc.remove_namespaces!
    expect(doc.at_xpath('//Period/Quarter').text).to eq('1')
    expect(doc.at_xpath('//Period/Year').text).to eq('2025')
  end

  it 'contient chaque montant de grille avec son numéro' do
    expect(xml).to include('GridNumber="1"').and include('1000.00')
    expect(xml).to include('GridNumber="54"').and include('210.00')
  end

  # XSD Intervat v0.7 (schémas de 2012, seule copie disponible : à remplacer par le XSD officiel courant).
  def xsd_errors(xml)
    dir = Rails.root.join('spec/fixtures/intervat')
    schema = Dir.chdir(dir) { Nokogiri::XML::Schema(File.open('NewTVA-in_v0_7.xsd')) }
    schema.validate(Nokogiri::XML(xml)).map(&:message)
  end

  it 'est valide contre le XSD Intervat' do
    expect(xsd_errors(xml)).to be_empty
  end

  it 'reste valide avec une grille négative (ramenée à zéro) et le solde 72' do
    declaration.update!(grids: { '81' => '-50.00', '59' => '80.00', '72' => '80.00' })
    expect(xsd_errors(xml)).to be_empty
    expect(xml).to include('>0.00<')
  end

  context 'période mensuelle' do
    let(:declaration) do
      create(:vat_declaration, fiscal_year: fiscal_year, entity: entity,
             period_type: :monthly, period_start: Date.new(2025, 4, 1), period_end: Date.new(2025, 4, 30),
             grids: { '71' => '0.00' })
    end

    it 'contient le mois et l année, et est valide contre le XSD' do
      doc = Nokogiri::XML(xml)
      doc.remove_namespaces!
      expect(doc.at_xpath('//Period/Month').text).to eq('4')
      expect(xsd_errors(xml)).to be_empty
    end
  end
end
