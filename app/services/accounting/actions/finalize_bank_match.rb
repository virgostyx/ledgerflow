# F02: validating the draft payment entry of a matched bank line settles the line and pays the invoices the payment covers.
class Accounting::Actions::FinalizeBankMatch
  extend LightService::Action

  expects :entry

  executed do |ctx|
    transaction = Accounting::BankTransaction.matched.find_by(journal_entry_id: ctx.entry.id)
    next unless transaction

    transaction.update!(status: :reconciled)
    ctx.entry.lines.where.not(invoice_id: nil).includes(:invoice).filter_map(&:invoice).uniq.each do |invoice|
      invoice.pay! if invoice.remaining_amount.zero? && (invoice.posted? || invoice.partially_paid?)
    end
  end
end
