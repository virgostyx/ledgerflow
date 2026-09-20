# Cancels a posted entry with a counter-entry (debit/credit swapped) in the same journal and fiscal year.
# The original is kept and flagged reversed. Entries born from an invoice or payment batch must be undone
# from their source document (which then calls with from_source: true), and lettered lines must be unlettered first.
class Accounting::ReverseJournalEntry
  def self.call(entry:, from_source: false)
    ctx = LightService::Context.make(entry: entry, reversal: nil)
    refusal = refusal_for(entry, from_source)
    return ctx.tap { |c| c.fail!(refusal) } if refusal

    ApplicationRecord.transaction do
      ApplicationRecord.connection.execute("SET CONSTRAINTS enforce_double_entry DEFERRED")
      reversal = build_reversal(entry)
      reversal.save!
      posted = Accounting::PostJournalEntry.call(entry: reversal)
      if posted.failure?
        ctx.fail!(posted.message)
        raise ActiveRecord::Rollback
      end

      entry.reverse!
      Accounting::AuditLog.record!(auditable: entry, action: "reverse_entry", payload: { reversal_id: reversal.id })
      ctx[:reversal] = reversal
    end
    ctx
  rescue StandardError => e
    ctx.fail!("Error: #{e.message}")
    ctx
  end

  def self.refusal_for(entry, from_source)
    return I18n.t("accounting.errors.reverse_not_posted")  unless entry.posted?
    return I18n.t("accounting.errors.reverse_year_closed") if entry.fiscal_year.closed?
    return I18n.t("accounting.errors.reverse_has_source")  if entry.source_type.present? && !from_source
    I18n.t("accounting.errors.reverse_lettered")    if entry.lines.where.not(lettering_id: nil).exists?
  end
  private_class_method :refusal_for

  def self.build_reversal(entry)
    Accounting::JournalEntry.new(
      journal: entry.journal, fiscal_year: entry.fiscal_year, entry_date: entry.entry_date,
      description: I18n.t("accounting.journal_entries.reversal_description", reference: entry.reference),
      reversal_of_id: entry.id
    ).tap do |reversal|
      entry.lines.each do |l|
        reversal.lines.build(account_id: l.account_id, partner_id: l.partner_id, label: l.label,
                             debit: l.credit, credit: l.debit, sort_order: l.sort_order)
      end
    end
  end
  private_class_method :build_reversal
end
