class Accounting::TrialBalanceQuery
  Result = Struct.new(:id, :code, :label_fr, :account_type, :normal_balance,
                      :total_debit, :total_credit, :balance,
                      :opening_debit, :opening_credit, :movement_debit, :movement_credit,
                      :currency, :balance_in_currency, # an account kept in a foreign currency (F11): the currency and the balance in it, signed like the debit
                      keyword_init: true) do
    # Ouverture/clôture: net soldes, placés en Débit s'ils sont positifs, en Crédit sinon
    # (docs/dev/reports/spec.md §5) — pas le même sens que #balance, qui suit le sens
    # normal du compte (voir docs/dev/reports/QUESTIONS.md).
    def opening_net = opening_debit - opening_credit
    def opening_display_debit  = opening_net.positive? ? opening_net : BigDecimal("0")
    def opening_display_credit = opening_net.negative? ? -opening_net : BigDecimal("0")

    def closing_net = total_debit - total_credit
    def closing_display_debit  = closing_net.positive? ? closing_net : BigDecimal("0")
    def closing_display_credit = closing_net.negative? ? -closing_net : BigDecimal("0")
  end

  # The entries that are not the closing entry, nor the reversal of one (a year reopened and closed again: the first closing entry was taken back).
  NOT_CLOSING = "accounting_journal_entries.source_type IS DISTINCT FROM ? AND (accounting_journal_entries.reversal_of_id IS NULL OR " \
                "accounting_journal_entries.reversal_of_id NOT IN (SELECT ce.id FROM accounting_journal_entries ce WHERE ce.source_type = ?))".freeze

  # date_from: start of the period shown (defaults to the fiscal year's start, i.e. no
  # opening — matches this query's original, still-used-by-balance_sheet/income_statement
  # behavior). Lines before it become the opening balance; from it to as_of, the movements.
  # exclude_closing: leave out the closing entry (and so the result account it fills), to read the income of a closed year.
  def initialize(fiscal_year:, as_of: nil, date_from: nil, exclude_closing: false)
    @fiscal_year = fiscal_year
    @as_of = as_of || fiscal_year.end_date
    @date_from = date_from || fiscal_year.start_date
    @exclude_closing = exclude_closing
  end

  def call
    quoted_from = Accounting::JournalEntryLine.connection.quote(@date_from)

    rows = base_scope
      .group(:account_id)
      .select(
        "account_id",
        "COALESCE(SUM(accounting_journal_entry_lines.debit)  FILTER (WHERE accounting_journal_entries.entry_date < #{quoted_from}), 0) AS opening_debit",
        "COALESCE(SUM(accounting_journal_entry_lines.credit) FILTER (WHERE accounting_journal_entries.entry_date < #{quoted_from}), 0) AS opening_credit",
        "COALESCE(SUM(accounting_journal_entry_lines.debit)  FILTER (WHERE accounting_journal_entries.entry_date >= #{quoted_from}), 0) AS movement_debit",
        "COALESCE(SUM(accounting_journal_entry_lines.credit) FILTER (WHERE accounting_journal_entries.entry_date >= #{quoted_from}), 0) AS movement_credit",
        "SUM(accounting_journal_entry_lines.debit) AS total_debit",
        "SUM(accounting_journal_entry_lines.credit) AS total_credit"
      )

    account_ids = rows.map(&:account_id)
    accounts    = Accounting::Account.where(id: account_ids).index_by(&:id)
    in_currency = balances_in_currency(accounts.values.select(&:currency))

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
        balance:        balance,
        opening_debit:  BigDecimal(row.opening_debit.to_s),
        opening_credit: BigDecimal(row.opening_credit.to_s),
        movement_debit: BigDecimal(row.movement_debit.to_s),
        movement_credit: BigDecimal(row.movement_credit.to_s),
        currency:       account.currency,
        balance_in_currency: (in_currency.fetch(account.id, BigDecimal("0")) if account.currency)
      )
    end.sort_by(&:code)
  end

  private

  # Σ of the amounts in the account's currency on the lines in that currency, up to the date (what the account holds in that currency).
  def balances_in_currency(accounts)
    return {} if accounts.empty?

    base_scope.where(account_id: accounts.map(&:id))
              .where("accounting_journal_entry_lines.currency = (SELECT a.currency FROM accounting_accounts a WHERE a.id = accounting_journal_entry_lines.account_id)")
              .group(:account_id).sum("accounting_journal_entry_lines.amount_currency").transform_values { |v| BigDecimal(v.to_s) }
  end

  def base_scope
    Accounting::JournalEntryLine
      .joins(:journal_entry)
      .where(
        accounting_journal_entries: {
          fiscal_year_id: @fiscal_year.id,
          status: Accounting::JournalEntry.ledger_status_values
        }
      )
      .where("accounting_journal_entries.entry_date <= ?", @as_of)
      .merge(@exclude_closing ? Accounting::JournalEntry.where(NOT_CLOSING, Accounting::JournalEntry::CLOSING_SOURCE, Accounting::JournalEntry::CLOSING_SOURCE) : Accounting::JournalEntry.all)
  end
end
