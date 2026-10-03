# Letters a group of posted journal lines on one account whose debits and credits cancel out (total lettering).
# Lettering a supplier/customer invoice's payable/receivable line settles the invoice. All or nothing.
#
# The lines are locked first (two people lettering the same line at the same moment: the second finds it lettered and is refused).
# user: who does it (nil: the system); auto: an automatic lettering; cross_partner: lines of different partners, which needs the right
# `reconciliations.cross_partner` and a reason. The history of every line records it.
class Accounting::LetterLines
  extend LightService::Organizer

  def self.call(lines:, user: nil, reason: nil, cross_partner: false, auto: false)
    result = nil
    ApplicationRecord.transaction do
      locked = Accounting::JournalEntryLine.where(id: Array(lines).map(&:id)).order(:id).lock.includes(:journal_entry, :account).to_a
      result = with(lines: locked, user: user, reason: reason.to_s.strip.presence, cross_partner: cross_partner, auto: auto).reduce(
        Accounting::Actions::PostFxAdjustment,
        Accounting::Actions::ValidateLettering,
        Accounting::Actions::CreateLettering,
        Accounting::Actions::PayLetteredInvoices
      )
      raise ActiveRecord::Rollback if result.failure?
    end
    result
  rescue StandardError => e
    LightService::Context.make(lines: lines).tap { |ctx| ctx.fail!("Error: #{e.message}") }
  end
end
