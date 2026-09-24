require 'rails_helper'

RSpec.describe Accounting::InvoiceEmail, type: :model do
  include_context 'with entity'

  describe 'associations' do
    it { should belong_to(:invoice).class_name('Accounting::Invoice') }
    it { should belong_to(:sent_by).class_name('User') }
  end

  describe 'validations' do
    subject { build(:invoice_email) }

    it { should validate_presence_of(:recipient) }
    it { should validate_presence_of(:subject) }

    it 'accepte une adresse e-mail valide' do
      expect(build(:invoice_email, recipient: 'a.b@compagnie.be')).to be_valid
    end

    it 'rejette une adresse mal formée' do
      email = build(:invoice_email, recipient: 'pas-un-email')
      expect(email).not_to be_valid
      expect(email.errors[:recipient]).to be_present
    end

    it 'rejette plusieurs adresses collées' do
      expect(build(:invoice_email, recipient: 'a@b.be, c@d.be')).not_to be_valid
    end
  end

  describe 'status' do
    it { should define_enum_for(:status).with_values(queued: 0, sent: 1, failed: 2) }

    it 'démarre en queued' do
      expect(described_class.new).to be_queued
    end
  end

  describe 'scope' do
    it 'est limité à l entité courante' do
      mine  = create(:invoice_email)
      other_entity = create(:entity)
      other = ActsAsTenant.with_tenant(other_entity) { create(:invoice_email) }

      expect(described_class.all).to include(mine)
      expect(described_class.all).not_to include(other)
    end
  end

  describe 'Accounting::Invoice#emails' do
    it 'liste les envois d une facture, du plus récent au plus ancien' do
      invoice = create(:invoice)
      old = create(:invoice_email, invoice: invoice, created_at: 2.days.ago)
      recent = create(:invoice_email, invoice: invoice, created_at: 1.hour.ago)

      expect(invoice.emails).to eq([ recent, old ])
    end
  end
end
