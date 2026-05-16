class Accounting::Actions::ValidateNoOpenEntries
  extend LightService::Action

  expects :fiscal_year

  executed do |ctx|
    count = Accounting::JournalEntry
      .for_fiscal_year(ctx.fiscal_year)
      .where(status: Accounting::JournalEntry.statuses[:draft])
      .count

    if count > 0
      ctx.fail!(
        I18n.t("accounting.fiscal_years.errors.open_entries", count: count)
      )
    end
  end
end
