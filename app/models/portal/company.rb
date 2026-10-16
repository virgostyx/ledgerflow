# A company, as the portal sees it: a name and two flags. Read-only (a view).
class Portal::Company < ApplicationRecord
  self.table_name = "portal_companies"
  self.primary_key = :id

  def readonly? = true

  # The address of the company for documents sent by e-mail; the mail is taken in only from the people of the portal and the addresses the firm lists.
  def documents_email = "documents+#{documents_mail_token}@#{Rails.configuration.x.documents_mail_domain}"
end
