class Accounting::PaymentReminderPolicy < ApplicationPolicy
  # Reminding customers to pay speaks for the entity: admins and accountants only.
  def index? = can?("dunning.send")
end
