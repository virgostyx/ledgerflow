require "rails_helper"

RSpec.describe Seeders::VatCodesSeeder do
  # The suite seeds these once (rails_helper); start from empty to see what the seeder creates.
  before do
    Accounting::VatGridMapping.delete_all
    Accounting::VatAccountGridRule.delete_all
    Accounting::VatCode.delete_all
  end
  after { described_class.call } # restore the suite-wide reference data

  def seed = expect { described_class.call }.to output(/\[VatCodes\]/).to_stdout

  it "creates every sale and purchase code with an invoice and a credit-note mapping, plus the account rules" do
    seed
    codes = described_class::SALE.size + described_class::PURCHASE.size
    expect(Accounting::VatCode.count).to eq(codes)
    expect(Accounting::VatGridMapping.count).to eq(codes * 2)
    expect(Accounting::VatAccountGridRule.count).to eq(described_class::ACCOUNT_RULES.size)
  end

  it "is idempotent" do
    seed
    expect { seed }.not_to change(Accounting::VatCode, :count)
  end
end
