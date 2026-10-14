# B03b: the report "What changed". Reading it is reading the history of the books (`time_travel.view`) and the reports; the names of the authors need `audit.view`.
class Accounting::ChangesPolicy < ApplicationPolicy
  def index? = can?("time_travel.view") && can?("reports.view")
  def export? = index? && Accounting::ReportPolicy.new(user, :report).export?
  def review? = index? && can?("changes.review")
  def authors? = can?("audit.view")
  def erase_visit? = index?
end
