require "rails_helper"

RSpec.describe Accounting::Settings::AddBankAccount, type: :service do
  include_context "with_pcmn_accounts"

  let(:user)  { create(:user, role: :admin) }
  let(:valid_params) do
    {
      label_fr:           "ING Compte courant",
      journal_code:       "BNG1",
      iban:               "BE71096123456769",
      bic:                "BBRUBEBB",
      default_account_id: account_550.id,
      currency:           "EUR"
    }
  end

  describe ".call" do
    context "with valid params" do
      it "creates a bank journal" do
        expect {
          described_class.call(params: valid_params, user: user)
        }.to change(Accounting::Journal, :count).by(1)
      end

      it "creates a bank account" do
        expect {
          described_class.call(params: valid_params, user: user)
        }.to change(Accounting::BankAccount, :count).by(1)
      end

      it "links the bank account to the created journal" do
        result = described_class.call(params: valid_params, user: user)
        expect(result).to be_success
        bank_account = result[:bank_account]
        expect(bank_account.journal.journal_type).to eq("bank")
        expect(bank_account.journal.code).to eq("BNG1")
      end

      it "sets the correct default_account on the journal" do
        result = described_class.call(params: valid_params, user: user)
        expect(result[:bank_account].journal.default_account).to eq(account_550)
      end

      it "returns a successful context" do
        result = described_class.call(params: valid_params, user: user)
        expect(result).to be_success
      end
    end

    context "with an invalid IBAN" do
      it "fails and creates nothing" do
        params = valid_params.merge(iban: "BE00000000000000")
        expect {
          described_class.call(params: params, user: user)
        }.not_to change(Accounting::BankAccount, :count)
      end

      it "returns a failed context" do
        params = valid_params.merge(iban: "BE00000000000000")
        result = described_class.call(params: params, user: user)
        expect(result).to be_failure
      end
    end

    context "with a non-55xxxx counterpart account" do
      it "fails and creates nothing" do
        params = valid_params.merge(default_account_id: account_440.id)
        expect {
          described_class.call(params: params, user: user)
        }.not_to change(Accounting::Journal, :count)
        result = described_class.call(params: params, user: user)
        expect(result).to be_failure
      end
    end

    context "with a duplicate journal code" do
      before { create(:journal, :bank, code: "BNG1", default_account: account_550) }

      it "fails and rolls back" do
        expect {
          described_class.call(params: valid_params, user: user)
        }.not_to change(Accounting::BankAccount, :count)
      end
    end
  end
end
