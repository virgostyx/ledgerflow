# Entry templates (F07): everything is `entry_templates.manage`.
class Accounting::EntryTemplatePolicy < ApplicationPolicy
  def index?   = can?("entry_templates.manage")
  def show?    = index?
  def create?  = index?
  def update?  = index?
  def destroy? = index?
  def examples? = index?
  def entry? = index?
  def create_entry? = index?
end
