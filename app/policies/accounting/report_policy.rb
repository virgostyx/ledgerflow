class Accounting::ReportPolicy < ApplicationPolicy
  def trial_balance?    = user.admin? || user.accountant? || user.manager?
  def balance_sheet?    = trial_balance?
  def income_statement? = trial_balance?
  def general_ledger?   = trial_balance?
  def analytic_by_project? = trial_balance?
  def analytic_by_axis?    = trial_balance?
  def analytic_cross?      = trial_balance?
end
