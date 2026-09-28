class Accounting::ConsistencyMailer < ApplicationMailer
  def blocking_findings(user, run, count)
    @run   = run
    @count = count
    @entity = run.entity
    mail(to: user.email, subject: "[LedgerFlow] #{count} new blocking consistency #{'anomaly'.pluralize(count)}",
         from: email_address_with_name(Accounting::InvoiceMailer::FROM_ADDRESS, @entity.legal_name))
  end
end
