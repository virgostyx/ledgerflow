require "rails_helper"

RSpec.describe Accounting::AnalyticalAccount, type: :model do
  include_context 'with entity'

  describe "validations" do
    subject { build(:analytical_account) }

    it { should validate_presence_of(:code) }
    it { should validate_presence_of(:label_fr) }
    it { should validate_uniqueness_of(:code).scoped_to(:analytical_axis_id).case_insensitive }
  end

  describe "an account kept by an application" do
    let(:axis) { create(:analytical_axis) }

    it "is managed when it has an external reference, and not otherwise" do
      expect(build(:analytical_account, analytical_axis: axis, external_ref: "bf-project-1")).to be_managed
      expect(build(:analytical_account, analytical_axis: axis)).not_to be_managed
    end

    it "takes a code up to 40 characters (project code, chapter, line, sub line)" do
      expect(build(:analytical_account, analytical_axis: axis, code: "PRODEM-ZAMBIA-12.345.6789012345678")).to be_valid
    end

    it "has a reference that is unique in the entity" do
      create(:analytical_account, analytical_axis: axis, external_ref: "bf-subline-1")

      expect { create(:analytical_account, analytical_axis: axis, external_ref: "bf-subline-1") }.to raise_error(ActiveRecord::RecordNotUnique)
    end
  end

  describe "associations" do
    it { should belong_to(:analytical_axis) }
    it { should have_many(:analytical_annotations).dependent(:destroy) }
  end

  describe "scopes" do
    let!(:axis) { create(:analytical_axis) }

    it ".active returns only active accounts" do
      active   = create(:analytical_account, analytical_axis: axis, active: true)
      inactive = create(:analytical_account, analytical_axis: axis, active: false)
      expect(Accounting::AnalyticalAccount.active).to include(active)
      expect(Accounting::AnalyticalAccount.active).not_to include(inactive)
    end
  end

  describe "#destroyable?" do
    let(:axis)    { create(:analytical_axis) }
    let(:account) { create(:analytical_account, analytical_axis: axis) }

    it "returns true when no annotations exist" do
      expect(account.destroyable?).to be true
    end

    it "returns false for an account an application manages (BudgetFlow): it is deactivated there, never deleted" do
      expect(create(:analytical_account, analytical_axis: axis, external_ref: "bf-subline-1")).not_to be_destroyable
    end

    it "returns false when annotations exist" do
      entry = create(:journal_entry)
      ApplicationRecord.connection.execute("SET CONSTRAINTS enforce_double_entry DEFERRED")
      line = create(:journal_entry_line, :debit, journal_entry: entry)
      create(:analytical_annotation, analytical_account: account, analytical_axis: axis,
             journal_entry_line: line)
      expect(account.destroyable?).to be false
    end
  end
end
