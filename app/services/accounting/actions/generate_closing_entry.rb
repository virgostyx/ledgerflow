class Accounting::Actions::GenerateClosingEntry
  extend LightService::Action

  expects :fiscal_year, :closing_journal, :result_account, :closed_by
  promises :closing_entry

  executed do |ctx|
    ctx.closing_entry = nil

    rows = Accounting::TrialBalanceQuery.new(fiscal_year: ctx.fiscal_year).call
    class6 = rows.select { |r| r.account_type == "expense" && r.code != ctx.result_account.code && r.balance > 0 }
    class7 = rows.select { |r| r.account_type == "revenue" && r.balance > 0 }

    next unless class6.any? || class7.any?

    total_charges = class6.sum(&:balance)
    total_produits = class7.sum(&:balance)
    net_result = total_produits - total_charges

    entry = Accounting::JournalEntry.create!(
      journal:     ctx.closing_journal,
      fiscal_year: ctx.fiscal_year,
      entry_date:  ctx.fiscal_year.end_date,
      description: I18n.t("accounting.fiscal_years.closing_entry_description",
                           year: ctx.fiscal_year.year),
      status:      :draft
    )

    ApplicationRecord.connection.execute("SET CONSTRAINTS enforce_double_entry DEFERRED")

    class7.each do |row|
      Accounting::JournalEntryLine.create!(
        journal_entry: entry,
        account_id:    row.id,
        debit:         row.balance,
        credit:        BigDecimal("0"),
        label:         I18n.t("accounting.fiscal_years.closing_label")
      )
    end

    class6.each do |row|
      Accounting::JournalEntryLine.create!(
        journal_entry: entry,
        account_id:    row.id,
        debit:         BigDecimal("0"),
        credit:        row.balance,
        label:         I18n.t("accounting.fiscal_years.closing_label")
      )
    end

    if net_result >= 0
      Accounting::JournalEntryLine.create!(
        journal_entry: entry,
        account:       ctx.result_account,
        debit:         BigDecimal("0"),
        credit:        net_result,
        label:         I18n.t("accounting.fiscal_years.closing_label")
      )
    else
      Accounting::JournalEntryLine.create!(
        journal_entry: entry,
        account:       ctx.result_account,
        debit:         net_result.abs,
        credit:        BigDecimal("0"),
        label:         I18n.t("accounting.fiscal_years.closing_label")
      )
    end

    entry.post!
    ctx.closing_entry = entry
  rescue ActiveRecord::RecordInvalid => e
    ctx.fail_with_rollback!("Closing entry error: #{e.message}")
  end
end
