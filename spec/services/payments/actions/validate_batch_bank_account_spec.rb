require "rails_helper"

RSpec.describe Payments::Actions::ValidateBatchBankAccount do
  include_context "with entity"

  it "accepts a euro account with an IBAN" do
    expect(described_class.execute(bank_account: create(:bank_account))).to be_success
  end

  it "refuses an account without an IBAN: a SEPA file needs the debtor IBAN" do
    account = create(:bank_account, iban: "0012345678", bic: "ZANAZMLU", no_iban: true)
    result = described_class.execute(bank_account: account)
    expect(result).to be_failure
    expect(result.message).to include(account.label_fr).and include("IBAN")
  end
end
