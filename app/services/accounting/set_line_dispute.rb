# Marks a customer line as in dispute, or the dispute as over (F09): while it lasts the line is never asked for. Changes no amount, so it is allowed in a
# locked period; it is in the audit trail.
class Accounting::SetLineDispute
  def self.call(line:, disputed:, user:)
    ctx = LightService::Context.make(line: line)
    return ctx.tap { |c| c.fail!(I18n.t("accounting.dunning.errors.not_a_customer_line")) } unless Accounting::DunningLines.customer_line?(line)

    line.update!(disputed: disputed)
    Accounting::RefreshDunningItems.call(line: line)
    Accounting::AuditLog.record!(auditable: line, action: "dunning_dispute", user: user, payload: { disputed: disputed })
    ctx
  end
end
