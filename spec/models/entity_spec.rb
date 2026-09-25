require 'rails_helper'

RSpec.describe Entity, type: :model do
  let(:digiteal_credentials) { { 'api_key' => 'k', 'webhook_secret' => 's' } }
  subject { build(:entity) }

  describe 'validations' do
    it { should validate_presence_of(:name) }
    it { should validate_presence_of(:legal_name) }
    it { should validate_presence_of(:country) }
  end

  describe 'associations' do
    it { should belong_to(:created_by).class_name('User') }
    it { should have_many(:user_entities).dependent(:destroy) }
    it { should have_many(:users).through(:user_entities) }
  end

  describe 'scopes' do
    let!(:active_entity)   { create(:entity, active: true) }
    let!(:inactive_entity) { create(:entity, active: false) }

    it '.active retourne les entités actives' do
      expect(Entity.active).to include(active_entity)
      expect(Entity.active).not_to include(inactive_entity)
    end
  end

  describe 'defaults' do
    it 'est active par défaut' do
      expect(Entity.new.active).to be true
    end

    it 'a BE comme pays par défaut' do
      expect(Entity.new.country).to eq('BE')
    end

    it 'a une périodicité de dépôt TVA trimestrielle par défaut' do
      expect(Entity.new).to be_quarterly
    end

    it 'a un régime TVA normal par défaut' do
      expect(Entity.new).to be_normal
    end
  end

  describe 'vat_filing_frequency' do
    it { should define_enum_for(:vat_filing_frequency).with_values(monthly: 0, quarterly: 1) }
  end

  describe 'vat_regime' do
    it { should define_enum_for(:vat_regime).with_values(normal: 0, franchise: 1) }
  end

  describe 'vat_scheme' do
    it { should define_enum_for(:vat_scheme).with_values(normal: 0, mixed: 1).with_prefix(:vat_scheme) }

    it 'vaut normal par défaut' do
      expect(Entity.new).to be_vat_scheme_normal
    end
  end

  describe 'vat_prorata_rate' do
    it 'est nil par défaut (déduction totale)' do
      expect(Entity.new.vat_prorata_rate).to be_nil
    end
  end

  describe 'vat_number uniqueness' do
    it 'accepte deux entités sans vat_number' do
      create(:entity, vat_number: nil)
      entity2 = build(:entity, vat_number: nil)
      expect(entity2).to be_valid
    end

    it 'rejette deux entités avec le même vat_number' do
      create(:entity, vat_number: 'BE0123456789')
      entity2 = build(:entity, vat_number: 'BE0123456789')
      expect(entity2).not_to be_valid
    end
  end

  describe 'vat_number normalization' do
    it 'stocke un numéro vide comme NULL, pour ne pas heurter l index unique partiel' do
      entity = create(:entity, vat_number: '  ')
      expect(entity.reload.vat_number).to be_nil
    end

    it 'accepte deux entités dont le numéro de TVA est saisi vide' do
      create(:entity, vat_number: '')
      expect { create(:entity, vat_number: '') }.not_to raise_error
    end

    it 'retire les espaces autour d un numéro valide' do
      expect(create(:entity, vat_number: ' BE0123456789 ').reload.vat_number).to eq('BE0123456789')
    end
  end

  describe 'vat_number format' do
    it 'accepte un numéro de TVA valide' do
      expect(build(:entity, vat_number: 'BE0123456789')).to be_valid
    end

    it 'accepte un numéro de TVA d un autre État membre' do
      expect(build(:entity, vat_number: 'FR32123456789')).to be_valid
    end

    it 'accepte un numéro vide' do
      expect(build(:entity, vat_number: '')).to be_valid
    end

    it 'rejette un préfixe pays inconnu' do
      entity = build(:entity, vat_number: 'XX123456789')
      expect(entity).not_to be_valid
      expect(entity.errors[:vat_number]).to be_present
    end

    it 'rejette un numéro mal formé pour son pays' do
      expect(build(:entity, vat_number: 'BE12')).not_to be_valid
    end
  end

  describe 'Peppol settings' do
    it { should define_enum_for(:peppol_access_point).with_values(simulator: 0, digiteal: 1).with_prefix(:peppol_ap) }

    it 'n a pas d Access Point tant qu il n est pas choisi' do
      expect(Entity.new.peppol_access_point).to be_nil
    end

    describe 'peppol_participant_id' do
      it 'accepte un identifiant schéma:valeur' do
        expect(build(:entity, peppol_participant_id: '0208:0123456789')).to be_valid
      end

      it 'accepte un identifiant vide' do
        expect(build(:entity, peppol_participant_id: '')).to be_valid
      end

      it 'rejette un identifiant mal formé' do
        %w[0123456789 abc:123 0208: 0208:01 23].each do |bad|
          expect(build(:entity, peppol_participant_id: bad)).not_to be_valid, "#{bad.inspect} should be refused"
        end
      end

      it 'est unique entre entités, car il sert à router les factures reçues' do
        create(:entity, peppol_participant_id: '0208:0123456789')
        expect(build(:entity, peppol_participant_id: '0208:0123456789')).not_to be_valid
      end

      it 'accepte plusieurs entités sans identifiant (stocké NULL, pas chaîne vide)' do
        create(:entity, peppol_participant_id: '')
        expect { create(:entity, peppol_participant_id: '  ') }.not_to raise_error
        expect(Entity.where(peppol_participant_id: nil).count).to be >= 2
      end
    end

    describe 'peppol_credentials' do
      it 'se relit tel quel, sous forme de Hash' do
        entity = create(:entity, peppol_credentials: { 'api_key' => 'k-123', 'webhook_secret' => 's-456' })

        expect(entity.reload.peppol_credentials).to eq('api_key' => 'k-123', 'webhook_secret' => 's-456')
      end

      it 'est chiffré en base : le secret n y apparaît jamais en clair' do
        entity = create(:entity, peppol_credentials: { 'api_key' => 'super-secret-key' })
        raw = Entity.connection.select_value("SELECT peppol_credentials FROM entities WHERE id = #{entity.id}")

        expect(raw).to be_present
        expect(raw).not_to include('super-secret-key')
      end

      it 'est vide par défaut' do
        expect(create(:entity).peppol_credentials).to be_blank
      end
    end

    describe 'peppol_webhook_token' do
      it 'est généré à la création, unique et illisible à deviner' do
        a, b = create(:entity), create(:entity)

        expect(a.peppol_webhook_token).to be_present.and(have_attributes(length: be >= 24))
        expect(a.peppol_webhook_token).not_to eq(b.peppol_webhook_token)
      end

      it 'peut être renouvelé' do
        entity = create(:entity)
        expect { entity.regenerate_peppol_webhook_token }.to change { entity.reload.peppol_webhook_token }
      end
    end

    describe 'le simulateur' do
      it 'est autorisé là où la configuration le permet (développement et test)' do
        expect(build(:entity, peppol_access_point: :simulator)).to be_valid
      end

      it 'est refusé quand la configuration ne le permet pas (production)' do
        allow(Rails.configuration.x).to receive(:peppol_simulator_allowed).and_return(false)
        entity = build(:entity, peppol_access_point: :simulator)

        expect(entity).not_to be_valid
        expect(entity.errors[:peppol_access_point]).to be_present
      end

      it 'ne bloque pas un vrai fournisseur en production' do
        allow(Rails.configuration.x).to receive(:peppol_simulator_allowed).and_return(false)
        expect(build(:entity, peppol_access_point: :digiteal, peppol_credentials: digiteal_credentials)).to be_valid
      end
    end

    describe 'credentials required by the Access Point' do
      it 'are asked for when a provider needing them is chosen' do
        entity = build(:entity, peppol_access_point: :digiteal, peppol_credentials: { 'api_key' => 'k' })

        expect(entity).not_to be_valid
        expect(entity.errors[:peppol_credentials].join).to include('Webhook secret')
      end

      it 'are accepted when complete' do
        expect(build(:entity, peppol_access_point: :digiteal, peppol_credentials: digiteal_credentials)).to be_valid
      end

      it 'are not needed by the simulator, nor without an Access Point' do
        expect(build(:entity, peppol_access_point: :simulator)).to be_valid
        expect(build(:entity, peppol_access_point: nil)).to be_valid
      end
    end
  end
end
