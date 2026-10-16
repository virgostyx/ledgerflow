# B02b: what the firm asks for, as the client may see it: a date, a label, an amount; never the counterparty's IBAN. The firm's request is copied into portal tables when it is made.
class Portal::DocumentRequestsController < Portal::BaseController
  def index
    lines = Portal::DocumentRequestLine.in_reach_of(current_portal_user).includes(:request).order("portal_document_request_lines.line_date DESC, portal_document_request_lines.id DESC").limit(200)
    @requests = lines.group_by(&:request)
    @may_answer = current_portal_user.open_grants.where("portal_grants.capabilities @> ?", [ "questions.answer" ].to_json).pluck(:entity_id)
    @may_upload = Portal::Upload.companies_open_to(current_portal_user).pluck(:id)
  end
end
