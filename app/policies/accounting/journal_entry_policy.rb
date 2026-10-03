class Accounting::JournalEntryPolicy < ApplicationPolicy
  class Scope < ApplicationPolicy::Scope
    def resolve = in_allowed_journals
  end

  def show?   = super && journal_allowed?
  def create? = super && journal_allowed?
  def update? = super && journal_allowed?

  def post?
    can?("entries.post") && journal_allowed?
  end

  def reverse?
    can?("entries.reverse") && journal_allowed?
  end
end
