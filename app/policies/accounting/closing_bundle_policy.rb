class Accounting::ClosingBundlePolicy < ApplicationPolicy
  def show? = can?("audit.view")
  def bundle? = show?
  def audit_export? = show?
  def filing_data? = show?
end
