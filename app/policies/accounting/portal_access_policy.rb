# B02a: who may open the client portal to people from outside, and close it again.
class Accounting::PortalAccessPolicy < ApplicationPolicy
  def index? = can?("portal.manage")
  def create? = can?("portal.manage")
  def destroy? = can?("portal.manage")
  def reset? = can?("portal.manage")
  def verify_identity? = can?("portal.manage")
  def reinstate? = can?("portal.manage")
  def branding? = can?("portal.manage")
  def grant? = can?("portal.manage")
  def decline? = can?("portal.manage")
  def withdraw? = can?("portal.manage")
end
