# Tasks (F08): seen like what they are about; created, changed and closed by those who may manage tasks (`tasks.manage`) and may see their target.
class Accounting::TaskPolicy < ApplicationPolicy
  class Scope < ApplicationPolicy::Scope
    def resolve = scope.visible_to(user)
  end

  def index?   = can?("records.list")
  def show?    = can?("records.view") && sees_target?
  def create?  = can?("tasks.manage") && sees_target?
  def update?  = create?
  def status?  = create?
  def comment? = can?("comments.write") && sees_target?

  private

  # A task about nothing is seen by those it concerns (the scope), a task about something by whoever sees that thing.
  def sees_target?
    return true unless record.respond_to?(:target) && record.target

    Accounting::TaskTargets.visible?(user, record.target)
  end
end
