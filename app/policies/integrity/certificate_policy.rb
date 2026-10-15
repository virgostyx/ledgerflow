# B03c: the integrity certificates. Seen (the page, the downloads) by whoever may read the reports and the audit (`integrity.view`); issued, revoked and verified again by the owner
# and the accountant (`integrity.issue`, with a second factor given a moment ago, asked by the controller); the authority of timestamps and the defaults by the owner alone.
class Integrity::CertificatePolicy < ApplicationPolicy
  def index? = can?("integrity.view")
  def show? = can?("integrity.view")
  def download? = can?("integrity.view")
  def create? = can?("integrity.issue")
  def revoke? = can?("integrity.issue")
  def verify? = can?("integrity.view")
  def configure? = can?("integrity.configure")
end
