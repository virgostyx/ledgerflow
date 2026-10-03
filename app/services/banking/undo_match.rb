# Undoes the match of a bank line (F02), whoever made it, however it was booked:
# - matched (a draft payment entry): the draft is deleted;
# - reconciled (a validated entry): the entry is reversed (a reason is required, a locked period or a lettered entry refuses it)
#   and the invoices it paid are reopened.
# The line becomes pending again. Audited. All or nothing.
class Banking::UndoMatch
  def self.call(transaction:, user:, reason: nil)
    ctx = LightService::Context.make(transaction: transaction)
    entry = transaction.journal_entry
    return ctx.tap { |c| c.fail!(I18n.t("banking.undo.nothing_to_undo")) } unless entry && (transaction.matched? || transaction.reconciled?)
    return ctx.tap { |c| c.fail!(I18n.t("banking.undo.reason_required")) } if transaction.reconciled? && reason.blank?

    ApplicationRecord.transaction do
      invoices = entry.lines.where.not(invoice_id: nil).includes(:invoice).filter_map(&:invoice).uniq
      kind = transaction.matched? ? "deleted_draft" : "reversed_entry"
      refusal = transaction.matched? ? delete_draft(transaction, entry) : reverse(transaction, entry, reason)
      if refusal
        ctx.fail!(refusal)
        raise ActiveRecord::Rollback
      end

      reopen(invoices)
      Accounting::AuditLog.record!(auditable: transaction, action: "bank_match_undone", user: user, reason: reason.presence,
                                   payload: { how: kind, amount: transaction.amount.to_s("F"), journal_entry_id: entry.id })
    end
    ctx
  end

  def self.delete_draft(transaction, entry)
    transaction.update!(status: :pending, journal_entry: nil, match_data: {})
    Accounting::JournalEntry.includes(lines: :analytical_annotations).find(entry.id).destroy! # eager: its lines go with it
    nil
  end

  def self.reverse(transaction, entry, reason)
    reversed = Accounting::ReverseJournalEntry.call(entry: entry, reason: reason)
    return reversed.message if reversed.failure?

    transaction.update!(status: :pending, journal_entry: nil, match_data: {})
    nil
  end

  # A paid invoice whose payment is gone goes back to posted; a partly paid one too when nothing else paid it.
  def self.reopen(invoices)
    invoices.each do |invoice|
      invoice.reload
      invoice.reopen! if invoice.paid?
      invoice.release! if invoice.partially_paid? && invoice.paid_amount.zero?
    end
  end
  private_class_method :delete_draft, :reverse, :reopen
end
