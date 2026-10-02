class Accounting::ClosingBundlePolicy < ApplicationPolicy
  def show? = can?("audit.view")
  def bundle? = show? && can_export?
  def audit_export? = show? && can_export?
  def filing_data? = show? && can_export?
end
