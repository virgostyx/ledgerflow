class Accounting::TrialBalanceQuery
  Result = Struct.new(:id, :code, :label_fr, :account_type, :normal_balance,
                      :total_debit, :total_credit, :balance, keyword_init: true)

  def initialize(fiscal_year:, as_of: nil)
    @fiscal_year = fiscal_year
    @as_of = as_of || fiscal_year.end_date
  end

  def call
    rows = Accounting::JournalEntryLine
      .joins(:journal_entry)
      .where(
        accounting_journal_entries: {
          fiscal_year_id: @fiscal_year.id,
          status: Accounting::JournalEntry.statuses[:posted]
        }
      )
      .where("accounting_journal_entries.entry_date <= ?", @as_of)
      .group(:account_id)
      .select(
        "account_id",
        "SUM(accounting_journal_entry_lines.debit) AS total_debit",
        "SUM(accounting_journal_entry_lines.credit) AS total_credit"
      )

    account_ids = rows.map(&:account_id)
    accounts    = Accounting::Account.where(id: account_ids).index_by(&:id)

    rows.map do |row|
      account = accounts[row.account_id]
      debit   = BigDecimal(row.total_debit.to_s)
      credit  = BigDecimal(row.total_credit.to_s)
      balance = account.normal_balance == "debit" ? debit - credit : credit - debit

      Result.new(
        id:             account.id,
        code:           account.code,
        label_fr:       account.label_fr,
        account_type:   account.account_type,
        normal_balance: account.normal_balance,
        total_debit:    debit,
        total_credit:   credit,
        balance:        balance
      )
    end.sort_by(&:code)
  end
end
