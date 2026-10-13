# B01b: who does what with a payment batch. Preparing, approving, exporting and confirming are four rights, held by different people when the entity asks it
# (the preparer does not approve their own batch, nor the person who gave the approval of its invoices authorize it: see the approval policies and the entity's options).
class Payments::BatchPolicy < ApplicationPolicy
  def index?   = can?("records.list")
  def show?    = can?("records.view")
  def prepare? = can?("payments.prepare")
  def create?  = prepare?
  def approve? = can?("payments.approve")
  def export?  = can?("payments.export")
  def confirm? = can?("payments.confirm")
  def reverse_payments? = confirm? && can?("entries.reverse") # a payment that came back: the entry of the payment is reversed (F07)
  def post_entries? = can?("entries.post") # validating the entries of the payments of a debited batch
end
