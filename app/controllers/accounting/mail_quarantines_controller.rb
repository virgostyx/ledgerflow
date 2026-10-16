# B02b: the mail to the documents address that was held back, for a person of the firm to release or discard, and the addresses allowed besides the people of the client portal.
class Accounting::MailQuarantinesController < ApplicationController
  before_action -> { require_feature!(:b02b) }
  before_action -> { authorize Accounting::PortalAccessPolicy, "#{action_name == 'settings' ? 'branding' : 'index'}?".to_sym, policy_class: Accounting::PortalAccessPolicy }
  before_action :set_item, only: %i[release discard]

  def index
    @items = Accounting::MailQuarantine.pending.order(:created_at).limit(200)
    @allowed_senders = entity.documents_allowed_senders
  end

  def release
    result = PortalAdmin::ReviewMail.release(@item, by: current_user)
    redirect_to accounting_mail_quarantines_path, notice: result.success? ? "Released: #{result[:created].size} documents taken in, #{result[:refused].size} refused." : nil, alert: result.success? ? nil : result.message
  end

  def discard
    result = PortalAdmin::ReviewMail.discard(@item, by: current_user)
    redirect_to accounting_mail_quarantines_path, notice: result.success? ? "Discarded." : nil, alert: result.success? ? nil : result.message
  end

  def settings
    senders = params[:allowed_senders].to_s.lines.map { |line| line.strip.downcase }.select { |line| line.match?(URI::MailTo::EMAIL_REGEXP) }.uniq
    if senders != entity.documents_allowed_senders
      entity.update!(documents_allowed_senders: senders)
      Accounting::AuditLog.record!(auditable: entity, action: "documents_allowed_senders_changed", user: current_user, payload: { count: senders.size })
    end
    redirect_to accounting_mail_quarantines_path, notice: "Saved."
  end

  private

  def entity = ActsAsTenant.current_tenant
  def set_item = @item = Accounting::MailQuarantine.find(params[:id])
end
