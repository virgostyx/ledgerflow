require "rails_helper"

RSpec.describe Accounting::DunningPolicy, type: :model do
  include_context "with entity"

  let(:policy) { described_class.for(ActsAsTenant.current_tenant) }

  it "is made once per entity with levels at 7, 21 and 45 days, no minimum, no charge, no interest and no automatic sending" do
    expect(policy).to have_attributes(level_1_days: 7, level_2_days: 21, level_3_days: 45, min_amount: 0, follow_up_days: 7,
                                      interest_enabled: false, indemnity_enabled: false, auto_send_level_1: false, fee_1: 0, fee_2: 0, fee_3: 0)
    expect(described_class.for(ActsAsTenant.current_tenant)).to eq(policy)
  end

  it "holds no legal rate: interest and indemnity have no figure until they are typed" do
    expect(policy).to have_attributes(interest_rate: nil, indemnity_amount: nil)
  end

  it "says which level a delay has reached" do
    expect([ 0, 6, 7, 20, 21, 44, 45, 200 ].map { |days| policy.level_for_delay(days) }).to eq([ 0, 0, 1, 1, 2, 2, 3, 3 ])
  end

  it "needs the delays to increase" do
    policy.level_2_days = 7
    expect(policy).not_to be_valid
  end

  it "needs a rate to charge interest and an amount to charge the indemnity" do
    policy.interest_enabled = true
    policy.indemnity_enabled = true
    expect(policy).not_to be_valid
    expect(policy.errors.attribute_names).to include(:interest_rate, :indemnity_amount)
    policy.assign_attributes(interest_rate: 8, indemnity_amount: 40)
    expect(policy).to be_valid
  end
end
