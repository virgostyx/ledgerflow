class Accounting::VatGridQuery
  def self.call(fiscal_year_id:, period_start:, period_end:)
    rows = Accounting::JournalEntryLine
      .joins(:journal_entry)
      .where(
        accounting_journal_entries: {
          fiscal_year_id: fiscal_year_id,
          status: Accounting::JournalEntry.statuses[:posted]
        }
      )
      .where("accounting_journal_entries.entry_date BETWEEN ? AND ?", period_start, period_end)
      .where.not(vat_code: nil)
      .group(:vat_code)
      .sum(:vat_amount)

    rows.each_with_object({}) do |(code, total), hash|
      hash[format("%02d", code)] = total
    end
  end
end
