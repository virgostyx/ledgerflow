# A company, as the portal sees it: a name and two flags. Read-only (a view).
class Portal::Company < ApplicationRecord
  self.table_name = "portal_companies"
  self.primary_key = :id

  def readonly? = true
end
