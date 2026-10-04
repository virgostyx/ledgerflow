# Records the date a customer promised to pay a line, or clears it (F09): the line is left alone until the day after that date, then comes back
# (Accounting::DunningPromisesJob). Changes no amount, so it is allowed in a locked period; it is in the audit trail.
class Accounting::SetPaymentPromise
  def self.call(line:, on:, user:)
    ctx = LightService::Context.make(line: line)
    return ctx.tap { |c| c.fail!(I18n.t("accounting.dunning.errors.not_a_customer_line")) } unless Accounting::DunningLines.customer_line?(line)
    return ctx.tap { |c| c.fail!(I18n.t("accounting.dunning.errors.promise_in_the_past")) } if on && on < Date.current

    line.update!(payment_promised_on: on)
    Accounting::RefreshDunningItems.call(line: line)
    Accounting::AuditLog.record!(auditable: line, action: "dunning_promise", user: user, payload: { payment_promised_on: on&.iso8601 })
    ctx
  end
end
