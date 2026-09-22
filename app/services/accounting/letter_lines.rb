# Letters a group of posted journal lines on one account whose debits and credits cancel out (total lettering).
# Lettering a supplier/customer invoice's payable/receivable line settles the invoice. All or nothing.
class Accounting::LetterLines
  extend LightService::Organizer

  def self.call(lines:)
    result = nil
    ApplicationRecord.transaction do
      result = with(lines: Array(lines)).reduce(
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
