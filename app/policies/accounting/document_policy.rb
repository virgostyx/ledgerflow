class Accounting::DocumentPolicy < ApplicationPolicy
  def index?    = can?("documents.view")
  def show?     = can?("documents.view")
  def download? = can?("documents.view")
  def new?      = can?("documents.upload")
  def create?   = can?("documents.upload")
  def link?     = can?("documents.link")
  def confirm_field? = can?("documents.link") # a person confirms what was read from the document
  def rerun?    = can?("documents.upload")
  def create_invoice? = can?("documents.link") && can?("records.write") # a draft invoice is a record to write
  def unlink?   = can?("documents.link")
  def update?   = can?("documents.link")
  def archive?  = can?("documents.archive")
  def destroy?  = can?("documents.delete_expired")
end
