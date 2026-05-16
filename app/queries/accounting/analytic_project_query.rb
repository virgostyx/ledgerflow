class Accounting::AnalyticProjectQuery
  Result = Struct.new(:project_id, :charges, :produits, :solde, keyword_init: true)

  EXPENSE_TYPE = Accounting::Account.account_types[:expense]
  REVENUE_TYPE = Accounting::Account.account_types[:revenue]

  def initialize(fiscal_year:, project_id: nil)
    @fiscal_year = fiscal_year
    @project_id  = project_id
  end

  def call
    scope = Accounting::JournalEntryLine
      .joins(:journal_entry, :account)
      .where(
        accounting_journal_entries: {
          fiscal_year_id: @fiscal_year.id,
          status: Accounting::JournalEntry.statuses[:posted]
        }
      )
      .where(
        accounting_accounts: { account_type: [ EXPENSE_TYPE, REVENUE_TYPE ] }
      )

    scope = scope.where(
      accounting_journal_entries: { project_id: @project_id }
    ) if @project_id

    rows = scope
      .group(
        "accounting_journal_entries.project_id",
        "accounting_accounts.account_type"
      )
      .select(
        "accounting_journal_entries.project_id",
        "accounting_accounts.account_type",
        "SUM(accounting_journal_entry_lines.debit) AS total_debit",
        "SUM(accounting_journal_entry_lines.credit) AS total_credit"
      )

    project_data = {}
    rows.each do |row|
      pid = row.project_id
      project_data[pid] ||= { charges: BigDecimal("0"), produits: BigDecimal("0") }
      case row.account_type
      when EXPENSE_TYPE
        project_data[pid][:charges] += BigDecimal(row.total_debit.to_s)
      when REVENUE_TYPE
        project_data[pid][:produits] += BigDecimal(row.total_credit.to_s)
      end
    end

    project_data.map do |pid, data|
      Result.new(
        project_id: pid,
        charges:    data[:charges],
        produits:   data[:produits],
        solde:      data[:produits] - data[:charges]
      )
    end.sort_by { |r| r.project_id.to_i }
  end
end
