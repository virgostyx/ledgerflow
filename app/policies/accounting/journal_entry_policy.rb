class Accounting::JournalEntryPolicy < ApplicationPolicy
  def post?
    user.admin? || user.accountant?
  end

  def reverse?
    user.admin? || user.accountant?
  end
end
