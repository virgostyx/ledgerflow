# B02c: the thread of messages of the company, from the firm: read, answer, turn a client's message into a task.
class Accounting::PortalMessagesController < ApplicationController
  before_action -> { require_feature!(:b02c) }
  before_action -> { authorize Accounting::PortalAccessPolicy, :index?, policy_class: Accounting::PortalAccessPolicy }

  def index
    @thread = Portal::MessageThread.of(entity.id)
    Portal::Message.where(thread_id: @thread.id, author_kind: "client", read_by_firm_at: nil).update_all(read_by_firm_at: Time.current)
    @messages = @thread.messages.includes(:portal_user).to_a
    @files = Portal::Upload.where(thread_id: @thread.id).includes(:portal_user).order(:created_at)
  end

  def create
    body = params[:body].to_s.strip.first(Portal::Message::MAX_BODY)
    return redirect_to(accounting_portal_messages_path, alert: "Write a message.") if body.blank?

    Portal::MessageThread.of(entity.id).messages.create!(entity_id: entity.id, author_kind: "firm", user_id: current_user.id, body: body)
    PortalAdmin::NotifyMessage.call(entity)
    redirect_to accounting_portal_messages_path, notice: "Sent."
  end

  def convert
    message = Portal::Message.where(entity_id: entity.id, author_kind: "client").find(params[:id])
    return redirect_to(accounting_portal_messages_path, alert: "Already a task.") if message.task_id

    task = Accounting::CreateTask.call(user: current_user, title: "Client message: #{message.body.squish}".truncate(120), description: "#{message.portal_user&.full_name}: #{message.body}", kind: :other)
    if task.success?
      message.update!(task_id: task[:task].id)
      Accounting::AuditLog.record!(auditable: task[:task], action: "portal_message_converted", user: current_user, payload: { message_id: message.id })
      redirect_to accounting_portal_messages_path, notice: "Task made."
    else
      redirect_to accounting_portal_messages_path, alert: task.message
    end
  end

  private

  def entity = ActsAsTenant.current_tenant
end
