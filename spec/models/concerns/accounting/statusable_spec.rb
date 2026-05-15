require 'rails_helper'

RSpec.describe Accounting::Statusable, type: :model do
  # On teste le concern via FiscalYear qui possède un champ status
  # et via un modèle anonyme pour les transitions AASM
  describe 'inclus dans un modèle avec états draft/posted/reversed' do
    let(:model_class) do
      Class.new(ApplicationRecord) do
        # name must be set before include so AASM can register the enum
        def self.name = 'TestStatusableModel'
        self.table_name = 'accounting_fiscal_years'
        include Accounting::Statusable
      end
    end

    it 'répond à draft?' do
      record = model_class.new
      expect(record).to respond_to(:draft?)
    end

    it 'répond à posted?' do
      record = model_class.new
      expect(record).to respond_to(:posted?)
    end

    it 'répond à reversed?' do
      record = model_class.new
      expect(record).to respond_to(:reversed?)
    end

    it 'répond aux événements post! et reverse!' do
      record = model_class.new
      expect(record).to respond_to(:post!)
      expect(record).to respond_to(:reverse!)
    end
  end
end
