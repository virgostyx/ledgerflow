require "rails_helper"

RSpec.describe Accounting::Settings::CreateCustomAccount, type: :service do
  include_context 'with entity'

  let(:user)    { create(:user, role: :admin) }
  let!(:parent) { create(:account, code: "604000", is_leaf: false, account_class: 6) }

  let(:valid_params) do
    {
      parent_id:      parent.id,
      code:           "6040001",
      label_fr:       "Matériel bureau",
      label_nl:       "Kantoormateriaal",
      account_class:  6,
      account_type:   "expense",
      normal_balance: "debit"
    }
  end

  describe ".call" do
    context "with valid params" do
      it "creates a custom account" do
        expect {
          described_class.call(params: valid_params, user: user)
        }.to change(Accounting::Account, :count).by(1)
      end

      it "sets custom: true on the new account" do
        result = described_class.call(params: valid_params, user: user)
        expect(result[:account].custom).to be true
      end

      it "sets is_leaf: true by default" do
        result = described_class.call(params: valid_params, user: user)
        expect(result[:account].is_leaf).to be true
      end

      it "returns a successful context" do
        result = described_class.call(params: valid_params, user: user)
        expect(result).to be_success
      end
    end

    context "when code does not follow parent hierarchy" do
      it "fails and creates nothing" do
        params = valid_params.merge(code: "7000001")
        expect {
          described_class.call(params: params, user: user)
        }.not_to change(Accounting::Account, :count)
      end

      it "returns a failed context" do
        params = valid_params.merge(code: "7000001")
        result = described_class.call(params: params, user: user)
        expect(result).to be_failure
      end
    end

    context "when code is already taken" do
      before { create(:account, code: "6040001") }

      it "fails and returns an error" do
        result = described_class.call(params: valid_params, user: user)
        expect(result).to be_failure
      end
    end

    context "without a parent" do
      it "fails — custom accounts require a parent" do
        params = valid_params.merge(parent_id: nil)
        result = described_class.call(params: params, user: user)
        expect(result).to be_failure
      end
    end

    context "when an unexpected error occurs" do
      before do
        allow(ApplicationRecord).to receive(:transaction).and_raise(StandardError, "unexpected DB error")
      end

      it "returns a failed context" do
        result = described_class.call(params: valid_params, user: user)
        expect(result).to be_failure
      end
    end
  end
end
