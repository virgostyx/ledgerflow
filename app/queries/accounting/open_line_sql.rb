# Shared SQL fragments for "is this client/supplier line still open as of a date"
# (docs/dev/reports/spec.md §7), used by AgedBalanceQuery, StaleCreditsQuery and
# UnletteredLinesQuery so they can never disagree (critère d'acceptation #4 : le
# sous-total tiers de R05 doit égaler le total du tiers dans R04).
#
# Callers must join accounting_journal_entries AS e, accounting_accounts AS a,
# LEFT JOIN accounting_partners AS p, LEFT JOIN accounting_invoices AS i,
# LEFT JOIN accounting_letterings AS lt (on l.lettering_id = lt.id).
module Accounting::OpenLineSql
  PREFIX = { customer: "40%", supplier: "44%" }.freeze
  LINES = "accounting_journal_entry_lines".freeze

  # Residual amount, signed like the line, 0 once closed by a lettering dated on/before
  # `as_of` — only allocations dated on/before `as_of` reduce it otherwise.
  def self.residual(kind:, as_of:)
    net  = kind.to_sym == :customer ? "#{LINES}.debit - #{LINES}.credit" : "#{LINES}.credit - #{LINES}.debit"
    used = "COALESCE((SELECT SUM(al.amount) FROM accounting_line_allocations al " \
           "WHERE (al.debit_line_id = #{LINES}.id OR al.credit_line_id = #{LINES}.id) " \
           "AND al.allocated_on <= #{quote(as_of)}), 0)"
    "CASE WHEN #{LINES}.lettering_id IS NOT NULL AND lt.lettered_on <= #{quote(as_of)} THEN 0 " \
    "ELSE (#{net}) - SIGN(#{net}) * #{used} END"
  end

  # Invoice due date, else the entry date plus the partner's payment terms, else the entry date alone.
  def self.due_date
    "COALESCE(i.due_date, (e.entry_date + COALESCE(p.payment_terms_days, 0) * INTERVAL '1 day')::date)"
  end

  # Open-item scope (partner, invoice, lettering joined as documented above) for `kind` as of `as_of`.
  def self.open_scope(kind:, as_of:)
    Accounting::JournalEntryLine
      .joins("JOIN accounting_journal_entries e ON e.id = #{LINES}.journal_entry_id")
      .joins("JOIN accounting_accounts a ON a.id = #{LINES}.account_id")
      .joins("LEFT JOIN accounting_partners p ON p.id = #{LINES}.partner_id")
      .joins("LEFT JOIN accounting_invoices i ON i.id = #{LINES}.invoice_id")
      .joins("LEFT JOIN accounting_letterings lt ON lt.id = #{LINES}.lettering_id")
      .where("e.status IN (?) AND e.entry_date <= ?", Accounting::JournalEntry.ledger_status_values, as_of)
      .where("a.code LIKE ? AND a.reconcilable", PREFIX.fetch(kind.to_sym))
  end

  def self.quote(value) = ApplicationRecord.connection.quote(value)
end
