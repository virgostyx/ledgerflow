# Peppol messages and settings (F06): who looks at the received invoices, who sends, who configures.
class Accounting::PeppolMessagePolicy < ApplicationPolicy
  def index?     = can?("peppol.review")
  def show?      = index?
  def reprocess? = index?
  def dismiss?   = index?
  def assign_supplier? = index?
  def pdf?       = index?
  def resend?    = can?("peppol.send")
  def configure? = can?("peppol.configure")
end
