require "rails_helper"

# Charges are the accountant's figures, never the code's: nothing is added until the policy says so.
RSpec.describe Accounting::DunningCharges do
  include_context "with entity"

  let(:policy) { Accounting::DunningPolicy.for(ActsAsTenant.current_tenant) }
  let(:rows)   { [ Struct.new(:residual, :age_days).new(BigDecimal("1000"), 73), Struct.new(:residual, :age_days).new(BigDecimal("500"), 36) ] }

  it "charges nothing by default" do
    expect(described_class.call(policy: policy, level: 3, rows: rows)).to eq(fees: 0, interest: 0, indemnity: 0)
  end

  it "adds the fee of the level" do
    policy.update!(fee_2: 7.5)
    expect(described_class.call(policy: policy, level: 2, rows: rows)[:fees]).to eq(BigDecimal("7.5"))
    expect(described_class.call(policy: policy, level: 1, rows: rows)[:fees]).to eq(0)
  end

  it "computes simple interest per line over the days late and a 365-day year, at the yearly rate typed" do
    policy.update!(interest_enabled: true, interest_rate: 10)
    # 1000 x 10% x 73/365 = 20.00 ; 500 x 10% x 36/365 = 4.93
    expect(described_class.call(policy: policy, level: 1, rows: rows)[:interest]).to eq(BigDecimal("24.93"))
  end

  it "adds the fixed indemnity once, as typed" do
    policy.update!(indemnity_enabled: true, indemnity_amount: 40)
    expect(described_class.call(policy: policy, level: 1, rows: rows)[:indemnity]).to eq(BigDecimal("40"))
  end
end
