class Accounting::PeriodMailer < ApplicationMailer
  def unlocked(owner, lock)
    @lock   = lock
    @entity = lock.entity
    mail(to: owner.email, subject: "[LedgerFlow] A locked period of #{@entity.legal_name} was reopened",
         from: email_address_with_name(Accounting::InvoiceMailer::FROM_ADDRESS, @entity.legal_name))
  end
end
