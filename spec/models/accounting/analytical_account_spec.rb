require "rails_helper"

RSpec.describe Accounting::AnalyticalAccount, type: :model do
  include_context 'with entity'

  describe "validations" do
    subject { build(:analytical_account) }

    it { should validate_presence_of(:code) }
    it { should validate_presence_of(:label_fr) }
    it { should validate_uniqueness_of(:code).scoped_to(:analytical_axis_id).case_insensitive }
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
