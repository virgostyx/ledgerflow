class Accounting::JournalEntryPolicy < ApplicationPolicy
  def post?
    entity_accountant?
  end

  def reverse?
    entity_accountant?
  end
end
