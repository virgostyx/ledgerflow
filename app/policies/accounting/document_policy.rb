class Accounting::DocumentPolicy < ApplicationPolicy
  def index?    = can?("documents.view")
  def show?     = can?("documents.view")
  def download? = can?("documents.view")
  def new?      = can?("documents.upload")
  def create?   = can?("documents.upload")
  def link?     = can?("documents.link")
  def unlink?   = can?("documents.link")
  def update?   = can?("documents.link")
  def archive?  = can?("documents.archive")
  def destroy?  = can?("documents.delete_expired")
end
