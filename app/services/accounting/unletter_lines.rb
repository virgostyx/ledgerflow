# Undoes a lettering. Invoices that lettering had settled go back to posted, except those also tied to a payment
# batch (they were paid for real, the lettering only matched the entries). All or nothing.
#
# A reason is required (F04). Lines in a locked period ask for the right `reconciliations.unreconcile_locked`. The history of each line
# keeps the unlettering, with its reason and who did it (nil: the system, which then gives its own reason).
class Accounting::UnletterLines
  extend LightService::Organizer

  def self.call(lettering:, reason:, user: nil)
    ctx = LightService::Context.make(lettering: lettering)
    return ctx.tap { |c| c.fail!(I18n.t("accounting.lettering.reason_required")) } if reason.to_s.strip.blank?

    ApplicationRecord.transaction do
      lettering.lock!
      lines = lettering.lines.includes(:journal_entry).to_a
      line_ids = lines.map(&:id)
      if (problem = locked_period_problem(lines, user))
        ctx.fail!(problem)
        raise ActiveRecord::Rollback
      end

      reopen_invoices(lettering)
      Accounting::LineAllocation.touching(line_ids).destroy_all
      Accounting::LetteringEvent.record!(lines: lines, action: "unletter", code: lettering.code, user: user, auto: false, reason: reason)
      fx_entries = Accounting::JournalEntry.where(lettering_id: lettering.id).to_a
      lettering.destroy!
      Accounting::JournalEntryLine.resync_amount_residual!(line_ids)
      undo_fx_adjustments(fx_entries, reason, user)
    end
    ctx
  rescue StandardError => e
    ctx.fail!("Error: #{e.message}")
    ctx
  end

  # Lettering changes no amount and stays possible in a locked period; undoing it there is for those who hold the right.
  def self.locked_period_problem(lines, user)
    return unless lines.any? { |line| Accounting::PeriodLock.covering(line.journal_entry.entry_date).exists? }
    return if user && Accounting::LetteringPolicy.new(user, :lettering).unreconcile_locked?

    I18n.t("accounting.lettering.locked_period")
  end

  # The exchange difference the lettering generated goes with it (F11): a draft is deleted, a posted one is reversed (the reversal pair is lettered by itself).
  def self.undo_fx_adjustments(entries, reason, user)
    entries.each do |entry|
      next entry.destroy! if entry.draft?

      undone = Accounting::ReverseJournalEntry.call(entry: entry, from_source: true, reason: reason, user: user)
      raise Accounting::PostRefused, undone.message if undone.failure?
    end
  end

  def self.reopen_invoices(lettering)
    return unless Accounting::Actions::PayLetteredInvoices::TRADE_ACCOUNTS.include?(lettering.account.code)

    entry_ids = lettering.lines.pluck(:journal_entry_id)
    Accounting::Invoice.paid.where(journal_entry_id: entry_ids).find_each do |invoice|
      invoice.reopen! unless Accounting::PaymentBatchLine.active.exists?(invoice_id: invoice.id)
    end
  end
  private_class_method :locked_period_problem, :reopen_invoices, :undo_fx_adjustments
end
