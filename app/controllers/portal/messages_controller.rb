# B02c: the thread of messages of a company. A person reads the thread of the companies where a right in force lists messages.use; what they write is cleaned and limited, and is no accounting
# instruction. Documents sent into the thread (B02b) appear in it.
class Portal::MessagesController < Portal::BaseController
  def index
    ids = companies.pluck(:id)
    @threads = Portal::MessageThread.where(entity_id: ids).includes(:company, messages: :portal_user).order(:entity_id)
    @threads = ids.map { |id| @threads.find { |t| t.entity_id == id } || Portal::MessageThread.of(id) } if @threads.size < ids.size
    @files = Portal::Upload.where(entity_id: ids).where.not(thread_id: nil).order(:created_at)
    @company_names = companies.pluck(:id, :name).to_h
  end

  def create
    company = companies.find_by(id: params[:company])
    return not_in_scope(params[:company]) unless company

    body = Portal::Message.clean(params[:body])
    return head(:unprocessable_content) if body.blank?
    return render(plain: t("portal.messages.too_many"), status: :too_many_requests) if Portal::Message.written_today_by(current_portal_user) >= Portal::Message::PER_DAY

    thread = Portal::MessageThread.of(company.id)
    thread.messages.create!(entity_id: company.id, author_kind: "client", portal_user: current_portal_user, body: body)
    record_event("message_sent", entity_id: company.id)
    redirect_to messages_path, notice: t("portal.messages.sent")
  end

  private

  def companies
    Portal::Company.where(questions_enabled: true, id: current_portal_user.open_grants.where("portal_grants.capabilities @> ?", [ "messages.use" ].to_json).select(:entity_id))
  end
end
