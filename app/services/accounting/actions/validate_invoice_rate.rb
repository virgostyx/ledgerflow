# An invoice in a foreign currency takes the official rate of its date, or a rate typed by hand with a reason (F11, Fx::RateGuard): a missing rate or
# an unexplained one refuses the posting, naming the currency and the date. The rate is then frozen on the lines of the entry. A rate that strays
# from the official one is accepted with a warning.
class Accounting::Actions::ValidateInvoiceRate
  extend LightService::Action

  expects  :invoice
  promises :rate_warning

  executed do |ctx|
    ctx.rate_warning = nil
    invoice = ctx.invoice
    next if invoice.currency == "EUR"

    checked = Fx::RateGuard.call(currency: invoice.currency, date: invoice.invoice_date, rate: invoice.exchange_rate,
                                 reason: invoice.exchange_rate_reason, user: Current.user)
    ctx.rate_warning = checked.warning
  rescue Fx::MissingRate, Fx::RateRefused => e
    ctx.fail_with_rollback!(e.message)
  end
end
