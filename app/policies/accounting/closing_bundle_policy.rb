class Accounting::ClosingBundlePolicy < ApplicationPolicy
  def show? = entity_auditor?
  def bundle? = show?
  def audit_export? = show?
  def filing_data? = show?
end
