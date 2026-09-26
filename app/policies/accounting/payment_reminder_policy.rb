class Accounting::PaymentReminderPolicy < ApplicationPolicy
  # Reminding customers to pay speaks for the entity: admins and accountants only.
  def index? = entity_accountant?
end
