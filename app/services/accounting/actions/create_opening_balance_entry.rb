class Accounting::Actions::CreateOpeningBalanceEntry
  extend LightService::Action

  expects :new_fiscal_year, :carry_forward_lines, :closed_by
  promises :opening_entry

  executed do |ctx|
    ctx[:opening_entry] = nil

    # Nothing to carry forward (first fiscal year or empty previous year)
    next ctx if ctx.carry_forward_lines.empty?

    # Idempotency guard — do not create a second opening entry
    existing = Accounting::JournalEntry
      .joins(:journal)
      .where(
        fiscal_year: ctx.new_fiscal_year,
        accounting_journals: { journal_type: Accounting::Journal.journal_types[:misc] }
      )
      .where(entry_date: ctx.new_fiscal_year.start_date)
      .first

    if existing
      ctx[:opening_entry] = existing
      next ctx
    end

    opening_journal = Accounting::Journal.where(journal_type: :misc, active: true).first
    unless opening_journal
      ctx.fail_with_rollback!(I18n.t("accounting.fiscal_years.errors.missing_opening_journal"))
      next ctx
    end

    entry = Accounting::JournalEntry.new(
      journal:     opening_journal,
      fiscal_year: ctx.new_fiscal_year,
      entry_date:  ctx.new_fiscal_year.start_date,
      description: I18n.t("accounting.fiscal_years.opening_entry_description",
                           year: ctx.new_fiscal_year.year - 1),
      status:      :draft
    )
    entry.reference = opening_journal.next_sequence_number(year: ctx.new_fiscal_year.start_date.year)
    entry.save!

    ApplicationRecord.connection.execute("SET CONSTRAINTS enforce_double_entry DEFERRED")

    ctx.carry_forward_lines.each do |attrs|
      Accounting::JournalEntryLine.create!(
        journal_entry: entry,
        account_id:    attrs[:account_id],
        debit:         attrs[:debit],
        credit:        attrs[:credit],
        label:         I18n.t("accounting.fiscal_years.opening_entry_label")
      )
    end

    entry.post!
    ctx[:opening_entry] = entry
  rescue ActiveRecord::RecordInvalid => e
    ctx.fail_with_rollback!("Opening balance error: #{e.message}")
  end
end
