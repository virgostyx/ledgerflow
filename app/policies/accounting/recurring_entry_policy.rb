# Recurring entries (F07): `recurring.manage`; letting one post by itself is the owner's call (`recurring.approve_post`).
class Accounting::RecurringEntryPolicy < ApplicationPolicy
  def index?   = can?("recurring.manage")
  def show?    = index?
  def create?  = index?
  def update?  = index?
  def destroy? = index?
  def pause?   = index?
  def resume?  = index?
  def unblock? = index?
  def approve_post? = can?("recurring.approve_post")
end
