# Undoes the match of a bank line (F02), whoever made it, however it was booked:
# - matched (a draft payment entry): the draft is deleted;
# - reconciled (a validated entry): the entry is reversed (a reason is required, a locked period or a lettered entry refuses it)
#   and the invoices it paid are reopened.
# A transfer between the entity's own accounts is undone on both lines at once (and unlettered first when it was validated).
# The lines become pending again. Audited. All or nothing.
class Banking::UndoMatch
  def self.call(transaction:, user:, reason: nil)
    ctx = LightService::Context.make(transaction: transaction)
    group = group_of(transaction)
    return ctx.tap { |c| c.fail!(I18n.t("banking.undo.nothing_to_undo")) } unless group.all? { |t| t.journal_entry && (t.matched? || t.reconciled?) }
    return ctx.tap { |c| c.fail!(I18n.t("banking.undo.reason_required")) } if group.any?(&:reconciled?) && reason.blank?

    ApplicationRecord.transaction do
      unletter(group, user, reason)
      group.each do |line|
        refusal = undo_one(line, user, reason)
        next unless refusal

        ctx.fail!(refusal)
        raise ActiveRecord::Rollback
      end
    end
    ctx
  end

  def self.group_of(transaction)
    pair = Accounting::BankTransaction.find_by(id: transaction.match_data["pair_id"]) if transaction.match_data["kind"] == "transfer"
    [ transaction, pair ].compact
  end

  # The transit lines of a validated transfer are lettered together: that goes first, or the reversal would be refused.
  def self.unletter(group, user, reason)
    entry_ids = group.filter_map(&:journal_entry_id)
    letterings = Accounting::Lettering.where(id: Accounting::JournalEntryLine.where(journal_entry_id: entry_ids).where.not(lettering_id: nil).select(:lettering_id))
    letterings.each { |lettering| Accounting::UnletterLines.call(lettering: lettering, user: user, reason: reason.presence || I18n.t("banking.undo.unletter_reason")) }
  end

  def self.undo_one(transaction, user, reason)
    entry = transaction.journal_entry
    invoices = entry.lines.where.not(invoice_id: nil).includes(:invoice).filter_map(&:invoice).uniq
    kind = transaction.matched? ? "deleted_draft" : "reversed_entry"
    refusal = transaction.matched? ? delete_draft(transaction, entry) : reverse(transaction, entry, reason)
    return refusal if refusal

    reopen(invoices)
    Accounting::AuditLog.record!(auditable: transaction, action: "bank_match_undone", user: user, reason: reason.presence,
                                 payload: { how: kind, amount: transaction.amount.to_s("F"), journal_entry_id: entry.id })
    nil
  end

  def self.delete_draft(transaction, entry)
    transaction.update!(status: :pending, journal_entry: nil, match_data: {})
    Accounting::JournalEntry.includes(lines: :analytical_annotations).find(entry.id).destroy! # eager: its lines go with it
    nil
  end

  def self.reverse(transaction, entry, reason)
    reversed = Accounting::ReverseJournalEntry.call(entry: entry, reason: reason, date: entry.entry_date) # strict: a locked period still refuses an undo (F02)
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
  private_class_method :group_of, :unletter, :undo_one, :delete_draft, :reverse, :reopen
end
