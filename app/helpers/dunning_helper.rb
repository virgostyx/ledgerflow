# The `policy(...)` view helper takes no policy class, and the dunning screens show records that are authorized through another one.
module DunningHelper
  def dunning_can?(action) = Accounting::DunningRunPolicy.new(current_user, nil).public_send(action)
  def dunning_rules_can?(action) = Accounting::DunningPolicyPolicy.new(current_user, nil).public_send(action)
end
