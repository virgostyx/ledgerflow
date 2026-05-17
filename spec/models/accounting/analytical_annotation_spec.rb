require "rails_helper"

RSpec.describe Accounting::AnalyticalAnnotation, type: :model do
  let(:axis)    { create(:analytical_axis) }
  let(:account) { create(:analytical_account, analytical_axis: axis) }
  let(:line) do
    entry = create(:journal_entry)
    ApplicationRecord.connection.execute("SET CONSTRAINTS enforce_double_entry DEFERRED")
    create(:journal_entry_line, :debit, journal_entry: entry)
  end

  describe "associations" do
    it { should belong_to(:journal_entry_line) }
    it { should belong_to(:analytical_axis) }
    it { should belong_to(:analytical_account) }
  end

  describe "uniqueness per axis per line" do
    it "allows one annotation per axis per line" do
      create(:analytical_annotation, journal_entry_line: line,
             analytical_axis: axis, analytical_account: account)
      other_axis    = create(:analytical_axis)
      other_account = create(:analytical_account, analytical_axis: other_axis)
      annotation = build(:analytical_annotation, journal_entry_line: line,
                         analytical_axis: other_axis, analytical_account: other_account)
      expect(annotation).to be_valid
    end

    it "rejects a second annotation for the same axis on the same line" do
      create(:analytical_annotation, journal_entry_line: line,
             analytical_axis: axis, analytical_account: account)
      duplicate = build(:analytical_annotation, journal_entry_line: line,
                        analytical_axis: axis, analytical_account: account)
      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:analytical_axis_id]).to be_present
    end
  end

  describe "account must belong to axis" do
    it "is invalid when account belongs to a different axis" do
      other_axis    = create(:analytical_axis)
      other_account = create(:analytical_account, analytical_axis: other_axis)
      annotation = build(:analytical_annotation, journal_entry_line: line,
                         analytical_axis: axis, analytical_account: other_account)
      expect(annotation).not_to be_valid
      expect(annotation.errors[:analytical_account]).to be_present
    end

    it "is valid when account belongs to the correct axis" do
      annotation = build(:analytical_annotation, journal_entry_line: line,
                         analytical_axis: axis, analytical_account: account)
      expect(annotation).to be_valid
    end
  end
end
