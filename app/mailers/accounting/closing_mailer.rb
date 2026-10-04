# The owners are told when a closed year is reopened (F10).
class Accounting::ClosingMailer < ApplicationMailer
  def reopened(owner, run)
    @run = run
    @entity = run.entity
    mail(to: owner.email, subject: "Fiscal year #{run.fiscal_year.year} reopened — #{@entity.name}")
  end
end
