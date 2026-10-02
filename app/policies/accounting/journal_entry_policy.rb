class Accounting::JournalEntryPolicy < ApplicationPolicy
  def post?
    can?("entries.post")
  end

  def reverse?
    can?("entries.reverse")
  end
end
