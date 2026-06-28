require "rails_helper"

RSpec.describe Accounting::AnalyticalAxis, type: :model do
  include_context 'with entity'

  describe "validations" do
    subject { build(:analytical_axis) }

    it { should validate_presence_of(:code) }
    it { should validate_presence_of(:label_fr) }
    it 'rejects a duplicate code within the same entity (case-insensitive)' do
      create(:analytical_axis, code: 'PROJ')
      expect(build(:analytical_axis, code: 'proj')).not_to be_valid
    end

    it 'allows the same code in a different entity' do
      create(:analytical_axis, code: 'PROJ')
      ActsAsTenant.with_tenant(create(:entity)) do
        expect(build(:analytical_axis, code: 'PROJ')).to be_valid
      end
    end
    it { should validate_length_of(:code).is_at_most(10) }
  end

  describe "associations" do
    it { should have_many(:analytical_accounts).dependent(:destroy) }
    it { should have_many(:analytical_annotations) }
  end

  describe "scopes" do
    let!(:active_axis)   { create(:analytical_axis, active: true) }
    let!(:inactive_axis) { create(:analytical_axis, active: false) }

    it ".active returns only active axes" do
      expect(Accounting::AnalyticalAxis.active).to include(active_axis)
      expect(Accounting::AnalyticalAxis.active).not_to include(inactive_axis)
    end
  end

  describe "#required_for_class?" do
    let(:axis) { build(:analytical_axis, required_for_account_classes: [ 6, 7 ]) }

    it "returns true for a class in the list" do
      expect(axis.required_for_class?(6)).to be true
    end

    it "returns false for a class not in the list" do
      expect(axis.required_for_class?(4)).to be false
    end
  end
end
