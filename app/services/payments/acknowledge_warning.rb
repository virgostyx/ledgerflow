# A person acknowledges a warning of the pre-flight report, with a reason (B01b). Only a warning: a blocking error cannot be waived. The acknowledgement is kept on the
# batch and holds for the same finding on a later run; it is in the audit trail with who and why.
# => ctx[:batch]; on a refusal ctx[:code] (:not_allowed, :reason_required, :not_a_warning)
class Payments::AcknowledgeWarning
  def self.call(batch:, key:, reason:, user:)
    ctx = LightService::Context.make(batch: batch)
    policy = Payments::BatchPolicy.new(user, batch)
    return refuse(ctx, :not_allowed) unless policy.prepare? || policy.approve?
    return refuse(ctx, :reason_required) if reason.blank?

    warning = Payments::Preflight.call(batch).warnings.find { |finding| finding.key == key }
    return refuse(ctx, :not_a_warning) unless warning

    report = batch.reload.preflight_report
    report["acknowledgements"] = (report["acknowledgements"] || {}).merge(key => { "user_id" => user.id, "user" => user.full_name, "reason" => reason, "at" => Time.current.iso8601 })
    batch.update_columns(preflight_report: report)
    Accounting::AuditLog.record!(auditable: batch, action: "payment_warning_acknowledged", user: user, payload: { code: warning.code.to_s, key: key, reason: reason })
    ctx
  end

  def self.refuse(ctx, code)
    ctx[:code] = code
    ctx.fail!(I18n.t("payments.preflight.errors.#{code}"))
    ctx
  end
  private_class_method :refuse
end
