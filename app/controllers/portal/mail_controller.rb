# B02b: the address a company receives documents at, shown to those who may send them. The mail is taken in only from the people of the portal (and the addresses the firm lists): the address
# alone is not enough.
class Portal::MailController < Portal::BaseController
  def show
    @companies = Portal::Upload.companies_open_to(current_portal_user).order(:name)
  end
end
