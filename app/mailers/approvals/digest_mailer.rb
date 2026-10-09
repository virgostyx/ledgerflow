# The daily summary to an approver (B01a): how many invoices wait for them and how many are late, and a link to the screen where they are looked
# at once signed in. Counts and a link only - no amount, no name, and nothing in the link decides anything: an e-mail never approves.
class Approvals::DigestMailer < ApplicationMailer
  helper ActionView::Helpers::TextHelper

  def pending(user:, entity:, count:, overdue:)
    @count = count
    @overdue = overdue
    @entity = entity
    @url = accounting_approvals_url
    mail(to: user.email, subject: "[LedgerFlow] #{ActionController::Base.helpers.pluralize(count, 'invoice')} to approve — #{entity.legal_name}")
  end
end
