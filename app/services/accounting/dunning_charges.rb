# What a reminder adds to the amount owed, from the policy and nothing else (F09): the fee of the level, simple interest at the yearly rate the
# accountant typed (per line, on the days late over a 365-day year), and the fixed indemnity. All zero until the policy turns them on.
module Accounting::DunningCharges
  def self.call(policy:, level:, rows:)
    interest = policy.interest_enabled ? rows.sum(BigDecimal("0")) { |r| r.residual * policy.interest_rate / 100 * r.age_days / 365 } : 0
    { fees: policy.fee_for(level), interest: interest.round(2), indemnity: policy.indemnity_enabled ? policy.indemnity_amount : 0 }
  end
end
