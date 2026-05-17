require "rails_helper"

RSpec.describe Accounting::Account, type: :model do
  describe "validations" do
    subject { build(:account) }

    it { should validate_presence_of(:code) }
    it { should validate_presence_of(:label_fr) }
    it { should validate_presence_of(:account_class) }
    it { should validate_presence_of(:account_type) }
    it { should validate_presence_of(:normal_balance) }
    it { should validate_uniqueness_of(:code).ignoring_case_sensitivity }
    it { should validate_inclusion_of(:account_class).in_range(1..7) }
  end

  describe "enums" do
    it { should define_enum_for(:account_type).with_values(asset: 0, liability: 1, equity: 2, revenue: 3, expense: 4) }
    it { should define_enum_for(:normal_balance).with_values(debit: 0, credit: 1) }
  end

  describe "code immutability" do
    let(:account) { create(:account, code: "604000") }

    it "prevents changing the code after creation" do
      account.code = "604001"
      expect(account).not_to be_valid
      expect(account.errors[:code]).to be_present
    end

    it "allows updating other fields" do
      account.label_fr = "Updated label"
      expect(account).to be_valid
    end
  end

  describe "custom sub-account hierarchy" do
    let(:parent) { create(:account, code: "604000", is_leaf: false) }

    it "accepts a custom sub-account whose code starts with the parent code" do
      child = build(:account, code: "6040001", parent: parent, custom: true)
      expect(child).to be_valid
    end

    it "rejects a custom sub-account whose code does not match the parent" do
      child = build(:account, code: "7000001", parent: parent, custom: true)
      expect(child).not_to be_valid
      expect(child.errors[:code]).to be_present
    end

    it "does not enforce hierarchy for seeded (non-custom) accounts" do
      child = build(:account, code: "700000", parent: parent, custom: false)
      expect(child).to be_valid
    end
  end

  describe "#destroyable?" do
    it "returns false for seeded accounts" do
      account = create(:account, custom: false)
      expect(account.destroyable?).to be false
    end

    it "returns false for custom accounts with children" do
      parent = create(:account, code: "6040001", custom: true, is_leaf: false)
      create(:account, code: "60400011", parent: parent, custom: true)
      expect(parent.destroyable?).to be false
    end

    it "returns false for custom accounts with journal entry lines" do
      account = create(:account, code: "6040001", custom: true)
      other   = create(:account, code: "6040002", custom: true)
      entry   = create(:journal_entry)
      ApplicationRecord.connection.execute("SET CONSTRAINTS enforce_double_entry DEFERRED")
      create(:journal_entry_line, journal_entry: entry, account: account,
             debit: BigDecimal("100"), credit: BigDecimal("0"))
      create(:journal_entry_line, journal_entry: entry, account: other,
             debit: BigDecimal("0"), credit: BigDecimal("100"))
      expect(account.destroyable?).to be false
    end

    it "returns true for a custom account with no children and no lines" do
      account = create(:account, code: "6040001", custom: true)
      expect(account.destroyable?).to be true
    end
  end

  describe "#deactivatable?" do
    it "returns true when no active children exist" do
      account = create(:account)
      expect(account.deactivatable?).to be true
    end

    it "returns false when active children exist" do
      parent = create(:account, code: "600000", is_leaf: false)
      create(:account, code: "604000", parent: parent, active: true)
      expect(parent.deactivatable?).to be false
    end
  end

  describe "scopes" do
    let!(:active_account)   { create(:account, active: true) }
    let!(:inactive_account) { create(:account, active: false) }

    it ".active returns only active accounts" do
      expect(Accounting::Account.active).to include(active_account)
      expect(Accounting::Account.active).not_to include(inactive_account)
    end

    it ".leaf returns only leaf accounts" do
      leaf   = create(:account, is_leaf: true)
      parent = create(:account, is_leaf: false)
      expect(Accounting::Account.leaf).to include(leaf)
      expect(Accounting::Account.leaf).not_to include(parent)
    end

    it ".by_class filters by account_class" do
      class6 = create(:account, account_class: 6)
      class4 = create(:account, account_class: 4, account_type: :asset)
      expect(Accounting::Account.by_class(6)).to include(class6)
      expect(Accounting::Account.by_class(6)).not_to include(class4)
    end
  end

  describe "#full_label" do
    it "returns code and label" do
      account = build(:account, code: "604000", label_fr: "Services divers")
      expect(account.full_label).to eq("604000 — Services divers")
    end
  end

  describe "tree structure" do
    it "can have a parent account" do
      parent = create(:account, code: "600000", is_leaf: false)
      child  = create(:account, code: "604000", parent_id: parent.id)
      expect(child.parent).to eq(parent)
    end
  end
end
