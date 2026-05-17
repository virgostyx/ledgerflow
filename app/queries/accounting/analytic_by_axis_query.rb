class Accounting::AnalyticByAxisQuery
  Result = Struct.new(:analytical_account, :charges, :produits, :solde, keyword_init: true)

  EXPENSE_TYPE = Accounting::Account.account_types[:expense]
  REVENUE_TYPE = Accounting::Account.account_types[:revenue]

  def initialize(fiscal_year:, axis:)
    @fiscal_year = fiscal_year
    @axis        = axis
  end

  def call
    rows = Accounting::JournalEntryLine
      .joins(:journal_entry, :account)
      .joins(annotation_join)
      .where(
        accounting_journal_entries: {
          fiscal_year_id: @fiscal_year.id,
          status: Accounting::JournalEntry.statuses[:posted]
        }
      )
      .where(accounting_accounts: { account_type: [ EXPENSE_TYPE, REVENUE_TYPE ] })
      .group("ann.analytical_account_id", "accounting_accounts.account_type")
      .select(
        "ann.analytical_account_id",
        "accounting_accounts.account_type",
        "SUM(accounting_journal_entry_lines.debit)  AS total_debit",
        "SUM(accounting_journal_entry_lines.credit) AS total_credit"
      )

    account_ids   = rows.map(&:analytical_account_id).uniq
    accounts_by_id = Accounting::AnalyticalAccount.where(id: account_ids).index_by(&:id)

    account_data = {}
    rows.each do |row|
      aid = row.analytical_account_id
      account_data[aid] ||= { charges: BigDecimal("0"), produits: BigDecimal("0") }
      case row.account_type
      when EXPENSE_TYPE then account_data[aid][:charges]  += BigDecimal(row.total_debit.to_s)
      when REVENUE_TYPE then account_data[aid][:produits] += BigDecimal(row.total_credit.to_s)
      end
    end

    account_data.map do |aid, data|
      Result.new(
        analytical_account: accounts_by_id[aid],
        charges:  data[:charges],
        produits: data[:produits],
        solde:    data[:produits] - data[:charges]
      )
    end.sort_by { |r| r.analytical_account.code }
  end

  private

  def annotation_join
    axis_id = Integer(@axis.id)
    <<~SQL.squish
      INNER JOIN accounting_analytical_annotations ann
        ON ann.journal_entry_line_id = accounting_journal_entry_lines.id
        AND ann.analytical_axis_id = #{axis_id}
    SQL
  end
end
