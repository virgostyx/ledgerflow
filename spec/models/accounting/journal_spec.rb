require "rails_helper"

RSpec.describe Accounting::Journal, type: :model do
  include_context "with_pcmn_accounts"

  describe "validations" do
    subject { build(:journal) }

    it { should validate_presence_of(:code) }
    it { should validate_presence_of(:label_fr) }
    it { should validate_presence_of(:journal_type) }
    it { should validate_presence_of(:sequence_prefix) }
    it 'rejects a duplicate code within the same entity' do
      create(:journal, code: 'DUPL')
      expect(build(:journal, code: 'DUPL')).not_to be_valid
    end

    it 'allows the same code in a different entity' do
      create(:journal, code: 'DUPL')
      ActsAsTenant.with_tenant(create(:entity)) do
        expect(build(:journal, code: 'DUPL')).to be_valid
      end
    end
  end

  describe "enums" do
    it do
      should define_enum_for(:journal_type)
        .with_values(purchase: 0, sale: 1, bank: 2, cash: 3, misc: 4, payroll: 5)
    end
  end

  describe "counterpart account requirement" do
    %i[bank cash purchase sale].each do |type|
      it "requires default_account_id for #{type} journal" do
        journal = build(:journal, journal_type: type, default_account_id: nil,
                        code: type.to_s.upcase[0..4], sequence_prefix: type.to_s.upcase[0..4])
        expect(journal).not_to be_valid
        expect(journal.errors[:default_account_id]).to be_present
      end
    end

    %i[misc payroll].each do |type|
      it "does not require default_account_id for #{type} journal" do
        journal = build(:journal, journal_type: type, default_account_id: nil)
        journal.valid?
        expect(journal.errors[:default_account_id]).to be_empty
      end
    end
  end

  describe "counterpart account class matching" do
    it "accepts a 55xxxx account for a bank journal" do
      journal = build(:journal, :bank, default_account: account_550)
      expect(journal).to be_valid
    end

    it "rejects a non-55xxxx account for a bank journal" do
      journal = build(:journal, :bank, default_account: account_440)
      expect(journal).not_to be_valid
      expect(journal.errors[:default_account_id]).to be_present
    end

    it "accepts a 57xxxx account for a cash journal" do
      journal = build(:journal, journal_type: :cash, default_account: account_570,
                      code: "CSH", sequence_prefix: "CSH")
      expect(journal).to be_valid
    end

    it "accepts a 44xxxx account for a purchase journal" do
      journal = build(:journal, :purchase, default_account: account_440)
      expect(journal).to be_valid
    end

    it "accepts a 40xxxx account for a sale journal" do
      journal = build(:journal, journal_type: :sale, default_account: account_400,
                      code: "VTE", sequence_prefix: "VTE")
      expect(journal).to be_valid
    end
  end

  describe "#destroyable? and #deactivatable?" do
    include_context "with_open_fiscal_year"

    let(:journal) { create(:journal, :purchase, default_account: account_440) }

    context "with no entries" do
      it "is destroyable" do
        expect(journal.destroyable?).to be true
      end

      it "is deactivatable" do
        expect(journal.deactivatable?).to be true
      end
    end

    context "with a draft entry" do
      before { create(:journal_entry, :draft, journal: journal, fiscal_year: fiscal_year) }

      it "is not destroyable" do
        expect(journal.destroyable?).to be false
      end

      it "is not deactivatable" do
        expect(journal.deactivatable?).to be false
      end
    end

    context "with only posted entries" do
      before { create(:journal_entry, :posted, journal: journal, fiscal_year: fiscal_year) }

      it "is not destroyable" do
        expect(journal.destroyable?).to be false
      end

      it "is deactivatable" do
        expect(journal.deactivatable?).to be true
      end
    end
  end

  describe "code immutability after entries" do
    include_context "with_open_fiscal_year"

    let(:journal) { create(:journal, :purchase, default_account: account_440) }

    it "prevents changing the code once entries exist" do
      create(:journal_entry, journal: journal, fiscal_year: fiscal_year)
      journal.code = "NEWCD"
      expect(journal).not_to be_valid
      expect(journal.errors[:code]).to be_present
    end

    it "allows updating other fields when entries exist" do
      create(:journal_entry, journal: journal, fiscal_year: fiscal_year)
      journal.label_fr = "Achats mis à jour"
      expect(journal).to be_valid
    end

    it "allows changing the code before any entries" do
      journal.code = "NEWCD"
      expect(journal).to be_valid
    end
  end

  describe "#next_sequence_number" do
    let(:journal) { create(:journal, :purchase, current_sequence: 0, default_account: account_440) }

    it "increments the sequence and returns the formatted reference" do
      ref = journal.next_sequence_number(year: 2025)
      expect(ref).to eq("ACH2025/0001")
      expect(journal.reload.current_sequence).to eq(1)
    end

    it "generates unique sequential references" do
      journal2 = create(:journal, journal_type: :sale, default_account: account_400,
                        code: "VTE", sequence_prefix: "VTE", current_sequence: 5)
      ref = journal2.next_sequence_number(year: 2025)
      expect(ref).to eq("VTE2025/0006")
    end
  end

  describe "scopes" do
    it ".active returns active journals" do
      active   = create(:journal, active: true)
      inactive = create(:journal, :purchase, active: false, default_account: account_440)
      expect(Accounting::Journal.active).to include(active)
      expect(Accounting::Journal.active).not_to include(inactive)
    end
  end
end
