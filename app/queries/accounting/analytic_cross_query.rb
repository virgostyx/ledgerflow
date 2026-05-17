class Accounting::AnalyticCrossQuery
  Result = Struct.new(:row_account, :col_account, :charges, :produits, :solde, keyword_init: true)

  EXPENSE_TYPE = Accounting::Account.account_types[:expense]
  REVENUE_TYPE = Accounting::Account.account_types[:revenue]

  def initialize(fiscal_year:, row_axis:, col_axis:)
    @fiscal_year = fiscal_year
    @row_axis    = row_axis
    @col_axis    = col_axis
  end

  def call
    rows = Accounting::JournalEntryLine
      .joins(:journal_entry, :account)
      .joins(row_annotation_join)
      .joins(col_annotation_join)
      .where(
        accounting_journal_entries: {
          fiscal_year_id: @fiscal_year.id,
          status: Accounting::JournalEntry.statuses[:posted]
        }
      )
      .where(accounting_accounts: { account_type: [ EXPENSE_TYPE, REVENUE_TYPE ] })
      .group(
        "row_ann.analytical_account_id",
        "col_ann.analytical_account_id",
        "accounting_accounts.account_type"
      )
      .select(
        "row_ann.analytical_account_id AS row_account_id",
        "col_ann.analytical_account_id AS col_account_id",
        "accounting_accounts.account_type",
        "SUM(accounting_journal_entry_lines.debit)  AS total_debit",
        "SUM(accounting_journal_entry_lines.credit) AS total_credit"
      )

    all_ids       = (rows.map(&:row_account_id) + rows.map(&:col_account_id)).uniq
    accounts_by_id = Accounting::AnalyticalAccount.where(id: all_ids).index_by(&:id)

    combo_data = {}
    rows.each do |row|
      key = [ row.row_account_id, row.col_account_id ]
      combo_data[key] ||= { charges: BigDecimal("0"), produits: BigDecimal("0") }
      case row.account_type
      when EXPENSE_TYPE then combo_data[key][:charges]  += BigDecimal(row.total_debit.to_s)
      when REVENUE_TYPE then combo_data[key][:produits] += BigDecimal(row.total_credit.to_s)
      end
    end

    combo_data.map do |(rid, cid), data|
      Result.new(
        row_account: accounts_by_id[rid],
        col_account: accounts_by_id[cid],
        charges:     data[:charges],
        produits:    data[:produits],
        solde:       data[:produits] - data[:charges]
      )
    end
  end

  private

  def row_annotation_join
    row_axis_id = Integer(@row_axis.id)
    <<~SQL.squish
      INNER JOIN accounting_analytical_annotations row_ann
        ON row_ann.journal_entry_line_id = accounting_journal_entry_lines.id
        AND row_ann.analytical_axis_id = #{row_axis_id}
    SQL
  end

  def col_annotation_join
    col_axis_id = Integer(@col_axis.id)
    <<~SQL.squish
      INNER JOIN accounting_analytical_annotations col_ann
        ON col_ann.journal_entry_line_id = accounting_journal_entry_lines.id
        AND col_ann.analytical_axis_id = #{col_axis_id}
    SQL
  end
end
