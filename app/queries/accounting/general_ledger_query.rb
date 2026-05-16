class Accounting::GeneralLedgerQuery
  Result = Struct.new(:line_id, :entry_date, :reference, :label,
                      :debit, :credit, :running_balance, :journal_entry_id,
                      keyword_init: true)

  def initialize(account:, fiscal_year:, date_from: nil, date_to: nil)
    @account     = account
    @fiscal_year = fiscal_year
    @date_from   = date_from || fiscal_year.start_date
    @date_to     = date_to   || fiscal_year.end_date
  end

  def call
    lines = Accounting::JournalEntryLine
      .joins(:journal_entry)
      .where(account: @account)
      .where(
        accounting_journal_entries: {
          fiscal_year_id: @fiscal_year.id,
          status: Accounting::JournalEntry.statuses[:posted]
        }
      )
      .where(
        "accounting_journal_entries.entry_date BETWEEN ? AND ?",
        @date_from, @date_to
      )
      .order(
        "accounting_journal_entries.entry_date ASC",
        "accounting_journal_entry_lines.id ASC"
      )
      .includes(:journal_entry)

    running = BigDecimal("0")
    lines.map do |line|
      delta = if @account.normal_balance == "debit"
                line.debit - line.credit
      else
                line.credit - line.debit
      end
      running += delta

      Result.new(
        line_id:         line.id,
        entry_date:      line.journal_entry.entry_date,
        reference:       line.journal_entry.reference,
        label:           line.label,
        debit:           line.debit,
        credit:          line.credit,
        running_balance: running,
        journal_entry_id: line.journal_entry_id
      )
    end
  end
end
