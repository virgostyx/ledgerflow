class Accounting::RecurringInvoicePolicy < ApplicationPolicy
  # Deleting a recurrence destroys no accounting data (the drafts it generated are kept): whoever can edit it can delete it.
  def destroy? = update?
end
