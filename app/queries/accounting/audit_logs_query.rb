# R18 audit-trail report filters (docs/dev/reports/spec.md §13): period, user, action, object type,
# journal entry reference, free text (payload and reason) and reason presence.
class Accounting::AuditLogsQuery
  def initialize(params)
    @params = params
  end

  def call
    scope = Accounting::AuditLog.order(id: :desc)
    scope = scope.where("accounting_audit_logs.created_at >= ?", date(:from).beginning_of_day) if date(:from)
    scope = scope.where("accounting_audit_logs.created_at <= ?", date(:to).end_of_day) if date(:to)
    scope = scope.where(user_id: @params[:user_id]) if @params[:user_id].present?
    scope = scope.where(action: @params[:action_name]) if @params[:action_name].present?
    scope = scope.where(auditable_type: @params[:auditable_type]) if @params[:auditable_type].present?
    scope = scope.where(auditable_type: "Accounting::JournalEntry", auditable_id: entry_ids) if @params[:reference].present?
    scope = scope.where("accounting_audit_logs.payload::text ILIKE :q OR accounting_audit_logs.reason ILIKE :q", q: "%#{Accounting::AuditLog.sanitize_sql_like(@params[:q])}%") if @params[:q].present?
    scope = scope.where.not(reason: [ nil, "" ]) if @params[:with_reason] == "1"
    scope
  end

  def self.filter_options
    { actions: Accounting::AuditLog.distinct.order(:action).pluck(:action),
      types: Accounting::AuditLog.distinct.order(:auditable_type).pluck(:auditable_type),
      users: Accounting::AuditLog.where.not(user_id: nil).distinct.order(:user_email).pluck(:user_email, :user_id) }
  end

  private

  def entry_ids = Accounting::JournalEntry.where("reference ILIKE ?", "%#{Accounting::AuditLog.sanitize_sql_like(@params[:reference])}%").select(:id)

  def date(key)
    @params[key].present? ? Date.iso8601(@params[key].to_s) : nil
  rescue Date::Error
    nil
  end
end
