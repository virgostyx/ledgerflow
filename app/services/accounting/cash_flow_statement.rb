# R15 cash-flow statement (docs/dev/reports/spec.md §12), both methods from one ledger read.
#
# Cash = accounts 55 and 57. Movements ignore the closing entry and the opening (carry-forward)
# entry, which instead defines the opening cash. Every entry is balanced, so any set of whole
# entries sums to zero over all accounts: net result − Σ(non-cash balance-sheet movements) is the
# cash movement, whichever way the balance-sheet accounts are grouped. That identity is invariant I9.
#
# Indirect: result + non-cash charges (class 63) ± working-capital movements ± investing and
# financing movements. The class 63 add-back is offset where its counterpart lives: 630 (fixed-asset
# depreciation) inside investing, the other write-downs/provisions inside "other operating".
# Direct: each cash movement is classified by the counterpart line of the same entry (exact
# attribution — equal to a pro rata split whenever counterparts share a sign); an account's
# `cash_flow_category` overrides the family default; nothing classifiable goes to "unclassified".
class Accounting::CashFlowStatement
  Line  = Struct.new(:key, :section, :label, :amount, keyword_init: true)
  Sheet = Struct.new(:lines, keyword_init: true) do
    def section_total(section) = lines.select { |l| l.section == section }.sum(BigDecimal("0"), &:amount)
    def line(key) = lines.find { |l| l.key == key }&.amount
    def total = lines.sum(BigDecimal("0"), &:amount)
  end
  Result = Struct.new(:fiscal_year, :from, :to, :opening_cash, :closing_cash, :net_change, :indirect, :direct, keyword_init: true)

  SECTIONS = %i[operating investing financing transfer unclassified].freeze
  CATS = Accounting::CashFlowCategories
  DEBIT_MINUS_CREDIT = "accounting_journal_entry_lines.debit - accounting_journal_entry_lines.credit".freeze
  CASH_SQL = "(accounting_accounts.code LIKE '55%' OR accounting_accounts.code LIKE '57%')".freeze

  def initialize(fiscal_year:, from: nil, to: nil)
    @fiscal_year = fiscal_year
    @from = from || fiscal_year.start_date
    @to   = to || fiscal_year.end_date
  end

  def call
    opening = cash_sum(base.where("accounting_journal_entries.source_type = ? OR accounting_journal_entries.entry_date < ?",
                                  Accounting::JournalEntry::OPENING_SOURCE, @from))
    closing = cash_sum(base)
    Result.new(fiscal_year: @fiscal_year, from: @from, to: @to, opening_cash: opening, closing_cash: closing,
               net_change: closing - opening, indirect: indirect, direct: direct)
  end

  private

  def base
    Accounting::JournalEntryLine.joins(:journal_entry, :account)
      .where(accounting_journal_entries: { fiscal_year_id: @fiscal_year.id, status: Accounting::JournalEntry.statuses[:posted] })
      .where("accounting_journal_entries.entry_date <= ?", @to)
      .where("accounting_journal_entries.source_type IS DISTINCT FROM ?", Accounting::JournalEntry::CLOSING_SOURCE)
  end

  def period
    base.where("accounting_journal_entries.entry_date >= ?", @from)
        .where("accounting_journal_entries.source_type IS DISTINCT FROM ?", Accounting::JournalEntry::OPENING_SOURCE)
  end

  def cash_sum(scope) = BigDecimal(scope.where(CASH_SQL).sum(DEBIT_MINUS_CREDIT).to_s)

  def movements
    @movements ||= period.group("accounting_accounts.code").sum(DEBIT_MINUS_CREDIT).transform_values { |v| BigDecimal(v.to_s) }
  end

  def mv(*prefixes) = movements.sum(BigDecimal("0")) { |code, v| CATS.starts_with?(code, prefixes) ? v : 0 }

  def indirect
    non_cash_all   = mv("63")
    non_cash_fixed = mv("630")
    families = CATS::INVESTING_PREFIXES + CATS::FINANCING_PREFIXES + CATS::TRANSFER_PREFIXES + CATS::CASH_PREFIXES
    wc_groups = %w[3 40 44 45]
    other = movements.sum(BigDecimal("0")) do |code, v|
      pl_or_family = code.start_with?("6", "7") || CATS.starts_with?(code, families + wc_groups)
      pl_or_family ? 0 : v
    end

    lines = [
      Line.new(key: :net_result, section: :operating, label: "Net result", amount: -mv("6", "7")),
      Line.new(key: :non_cash, section: :operating, label: "Depreciation, write-downs and provisions (63)", amount: non_cash_all),
      Line.new(key: :stocks, section: :operating, label: "Change in stocks", amount: -mv("3")),
      Line.new(key: :trade_receivables, section: :operating, label: "Change in trade receivables", amount: -mv("40")),
      Line.new(key: :trade_payables, section: :operating, label: "Change in trade payables", amount: -mv("44")),
      Line.new(key: :tax_social_payables, section: :operating, label: "Change in tax and social payables", amount: -mv("45")),
      Line.new(key: :other_operating, section: :operating, label: "Other operating movements, net of non-cash provisions",
               amount: -(other + (non_cash_all - non_cash_fixed))),
      Line.new(key: :fixed_assets, section: :investing, label: "Acquisitions and disposals of fixed assets (20–28)",
               amount: -mv("20", "21", "22", "23", "24", "25", "26", "27", "28") - non_cash_fixed),
      Line.new(key: :cash_investments, section: :investing, label: "Cash investments (50–54)", amount: -mv("50", "51", "52", "53", "54")),
      Line.new(key: :equity, section: :financing, label: "Capital, reserves and grants (10–15)", amount: -mv("10", "11", "12", "13", "14", "15")),
      Line.new(key: :borrowings, section: :financing, label: "Borrowings and dividends (17, 42, 43, 47)", amount: -mv("17", "42", "43", "47")),
      Line.new(key: :internal_transfers, section: :transfer, label: "Internal transfers (58)", amount: -mv("58"))
    ]
    Sheet.new(lines: lines)
  end

  # Counterpart lines of the entries that touch cash, per account: cash effect = −(debit − credit).
  def direct
    rows = period.where("EXISTS (SELECT 1 FROM accounting_journal_entry_lines cl JOIN accounting_accounts ca ON ca.id = cl.account_id " \
                        "WHERE cl.journal_entry_id = accounting_journal_entries.id AND (ca.code LIKE '55%' OR ca.code LIKE '57%'))")
                 .where.not(CASH_SQL).group("accounting_accounts.id").sum(DEBIT_MINUS_CREDIT)
    accounts = Accounting::Account.where(id: rows.keys).index_by(&:id)

    lines = rows.filter_map do |id, value|
      account = accounts.fetch(id)
      amount  = -BigDecimal(value.to_s)
      next if amount.zero?

      section = (account.cash_flow_category.presence || CATS.default_for(account.code) || "unclassified").to_sym
      Line.new(key: account.code, section: section, label: "#{account.code} #{account.label_fr}", amount: amount)
    end
    Sheet.new(lines: lines.sort_by { |l| [ SECTIONS.index(l.section), l.key ] })
  end
end
