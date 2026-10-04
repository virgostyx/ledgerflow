class Accounting::RecurringMailer < ApplicationMailer
  def blocked(owner, recurring, reason)
    @recurring = recurring
    @reason = reason
    @entity = recurring.entity
    mail(to: owner.email, subject: "[LedgerFlow] The recurring entry #{recurring.name} of #{@entity.legal_name} is blocked",
         from: email_address_with_name(Accounting::InvoiceMailer::FROM_ADDRESS, @entity.legal_name))
  end

  def backlog(owner, recurring)
    @recurring = recurring
    @entity = recurring.entity
    mail(to: owner.email, subject: "[LedgerFlow] The recurring entry #{recurring.name} of #{@entity.legal_name} is behind",
         from: email_address_with_name(Accounting::InvoiceMailer::FROM_ADDRESS, @entity.legal_name))
  end
end
