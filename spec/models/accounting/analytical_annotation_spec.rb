require "rails_helper"

RSpec.describe Accounting::AnalyticalAnnotation, type: :model do
  include_context 'with entity'

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

  describe "percentage split (R12)" do
    let(:second_account) { create(:analytical_account, analytical_axis: axis) }

    it "defaults to 100" do
      expect(create(:analytical_annotation, journal_entry_line: line, analytical_axis: axis,
                    analytical_account: account).percentage).to eq(100)
    end

    it "allows several accounts of one axis on a line when the percentages fit in 100" do
      create(:analytical_annotation, journal_entry_line: line, analytical_axis: axis, analytical_account: account, percentage: 50)
      expect(build(:analytical_annotation, journal_entry_line: line, analytical_axis: axis,
                   analytical_account: second_account, percentage: 50)).to be_valid
    end

    it "rejects a split above 100 % on one axis" do
      create(:analytical_annotation, journal_entry_line: line, analytical_axis: axis, analytical_account: account, percentage: 60)
      over = build(:analytical_annotation, journal_entry_line: line, analytical_axis: axis,
                   analytical_account: second_account, percentage: 50)
      expect(over).not_to be_valid
      expect(over.errors[:percentage]).to be_present
    end

    it "rejects zero, negative and >100 percentages" do
      [ 0, -5, 100.01 ].each do |pct|
        expect(build(:analytical_annotation, journal_entry_line: line, analytical_axis: axis,
                     analytical_account: account, percentage: pct)).not_to be_valid
      end
    end
  end
end
