# The rules of the reminders (F09). The automatic sending of the first level is for the owner alone.
class Accounting::DunningPolicyPolicy < ApplicationPolicy
  def show?      = can?("records.view")
  def update?    = can?("dunning.configure")
  def auto_send? = can?("dunning.auto_send")
end
